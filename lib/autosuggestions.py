#!/usr/bin/env python3
"""Gate native autosuggestions on cached, isolated input and display checks."""

import argparse
from contextlib import contextmanager, redirect_stdout
import hashlib
import json
import os
from pathlib import Path
import re
import select
import signal
import sys
import tempfile
import time


SCHEMA = 1
TIMEOUT_MS = 10000
MAX_OUTPUT = 262144


def file_identity(path):
    path = Path(path)
    with path.open('rb') as source:
        before = os.fstat(source.fileno())
        digest = hashlib.sha256()
        for chunk in iter(lambda: source.read(131072), b''):
            digest.update(chunk)
        after = os.fstat(source.fileno())
    attributes = ('st_dev', 'st_ino', 'st_size', 'st_mtime_ns', 'st_ctime_ns')
    if any(getattr(before, name) != getattr(after, name) for name in attributes):
        raise OSError('file changed while being inspected')
    return {'path': str(path.resolve()), 'sha256': digest.hexdigest(),
            'stat': [getattr(after, name) for name in attributes]}


def cached_identity(path, cached=None):
    path = Path(path)
    current = path.stat()
    attributes = ('st_dev', 'st_ino', 'st_size', 'st_mtime_ns', 'st_ctime_ns')
    if (cached and cached.get('path') == str(path.resolve()) and
            cached.get('stat') == [getattr(current, name) for name in attributes]):
        return cached
    return file_identity(path)


def fingerprint(home, bash, version, plugin, cached=None):
    paths = [bash, plugin, home / 'vendor/bash-autosuggestions/bash-autosuggestions.bash',
             home / 'vendor/bash-autosuggestions/.bash-version',
             home / 'lib/autosuggestions.py', home / 'bashrc.d/10-shell-options.sh',
             home / 'bashrc.d/40-abbreviations.sh']
    cached = cached or {}
    files = {entry['path']: entry for entry in cached.get('files', [])}
    linker = {}
    for path in (Path('/etc/ld.so.cache'), Path('/etc/ld.so.preload')):
        linker[str(path)] = cached_identity(path, cached.get('linker', {}).get(str(path))) if path.exists() else None
    return {'schema': SCHEMA, 'version': version, 'linker': linker,
            'files': [cached_identity(path, files.get(str(Path(path).resolve()))) for path in paths]}


def mapped_dependencies(pid, excluded):
    maps = Path('/proc') / str(pid) / 'maps'
    if not maps.is_file():
        raise OSError('loaded-library inspection requires Linux /proc')
    paths = set()
    for line in maps.read_text().splitlines():
        fields = line.split(None, 5)
        if len(fields) == 6 and fields[5].startswith('/'):
            path = Path(fields[5])
            if str(path.resolve()) not in excluded:
                paths.add(path)
    return [file_identity(path) for path in sorted(paths)]


class ProbeFailure(Exception):
    pass


class ProbeCursor:
    """Track the ASCII probe's cursor, including the terminal's deferred wrap."""

    def __init__(self, columns=120, rows=24):
        self.columns, self.rows = columns, rows
        self.x = self.y = 0
        self.pending = b''

    def feed(self, data):
        self.pending += data
        while self.pending:
            if self.pending.startswith(b'\x1b'):
                if len(self.pending) < 2:
                    return
                if not self.pending.startswith(b'\x1b['):
                    raise ProbeFailure('unexpected terminal escape in display check')
                match = re.match(rb'\x1b\[([0-?]*)([ -/]*)([@-~])', self.pending)
                if not match:
                    return
                parameters, intermediate, operation = match.groups()
                self.pending = self.pending[match.end():]
                if operation in (b'm', b'K', b'J', b'h', b'l'):
                    continue
                if intermediate or (parameters and not parameters.isdigit()):
                    raise ProbeFailure('unexpected cursor parameters in display check')
                amount = int(parameters or b'1') or 1
                self.x = min(self.x, self.columns - 1)
                if operation == b'A':
                    self.y = max(0, self.y - amount)
                elif operation == b'B':
                    self.y = min(self.rows - 1, self.y + amount)
                elif operation == b'C':
                    self.x = min(self.columns - 1, self.x + amount)
                elif operation == b'D':
                    self.x = max(0, self.x - amount)
                elif operation == b'G':
                    self.x = min(self.columns - 1, amount - 1)
                else:
                    raise ProbeFailure('unexpected cursor operation in display check')
                continue
            character, self.pending = self.pending[0], self.pending[1:]
            if character == 13:
                self.x = 0
            elif character == 10:
                self.y = min(self.rows - 1, self.y + 1)
            elif character == 8:
                self.x = max(0, self.x - 1)
            elif 32 <= character < 127:
                # Filling the last column does not wrap until another character is printed.
                if self.x == self.columns:
                    self.x = 0
                    self.y = min(self.rows - 1, self.y + 1)
                self.x += 1
            elif character != 7:
                raise ProbeFailure('unexpected character in display check')


def probe(bash, home, plugin=None, async_mode='0', timeout_ms=TIMEOUT_MS,
          inspect_dependencies=True, dependencies=None, check_display=True,
          dependencies_only=False):
    import pty
    import termios
    import struct
    import fcntl

    with tempfile.TemporaryDirectory(prefix='bash-modern-probe-') as temporary:
        directory = Path(temporary)
        (directory / 'user').mkdir()
        rc = directory / 'rc'
        prompt = b'BASH_MODERN_PROBE> '
        columns = 120
        display_setup = "printf '\\n\\n\\n\\n'\n"
        for index, prefix in enumerate(('#a ', '#b '), 1):
            command = prefix + 'x' * (columns * index - len(prompt) - len(prefix))
            display_setup += 'history -s "' + command + '"\n'
        rc.write_text(
            "PS1='BASH_MODERN_PROBE> '\nPS2='MORE> '\n"
            "HISTFILE=/dev/null\nset -o emacs\n"
            "BASH_AUTOSUGGEST_STRATEGY='match_prev_cmd history'\n"
            'BASH_AUTOSUGGEST_USE_ASYNC="$PROBE_ASYNC"\n'
            'if [[ -n $PROBE_PLUGIN ]]; then\n'
            '  enable -f "$PROBE_PLUGIN" bash_autosuggestions || exit 91\n'
            '  source "$PROBE_OPTIONS"\n'
            '  source "$PROBE_ABBR"\n'
            "  abbr --define bmprobe printf\n"
            'fi\n'
            + (display_setup if check_display else '')
        )
        environment = {
            'HOME': str(directory), 'BASH_MODERN_HOME': str(directory),
            'PATH': '/usr/bin:/bin', 'TERM': 'xterm', 'INPUTRC': '/dev/null',
            'LC_ALL': 'C', 'PROBE_PLUGIN': str(plugin or ''),
            'PROBE_ASYNC': async_mode,
            'PROBE_OPTIONS': str(home / 'bashrc.d/10-shell-options.sh'),
            'PROBE_ABBR': str(home / 'bashrc.d/40-abbreviations.sh'),
        }
        pid, master = pty.fork()
        if pid == 0:
            try:
                os.execve(str(bash), [str(bash), '--noprofile', '--rcfile', str(rc), '-i'],
                          environment)
            except BaseException:
                os._exit(127)
        pending = b''
        total_output = 0
        deadline = time.monotonic() + timeout_ms / 1000
        cursor = ProbeCursor(columns)

        def receive():
            nonlocal pending, total_output
            try:
                data = os.read(master, 4096)
            except OSError as error:
                raise ProbeFailure('test shell exited before completing input') from error
            if not data:
                raise ProbeFailure('test shell exited before completing input')
            total_output += len(data)
            if total_output > MAX_OUTPUT:
                raise ProbeFailure('test shell produced excessive output')
            pending += data
            if check_display:
                cursor.feed(data)
            return data

        def expect(token):
            nonlocal pending
            while token not in pending:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not select.select([master], [], [], remaining)[0]:
                    raise ProbeFailure('interactive input timed out')
                receive()
            pending = pending.split(token, 1)[1]

        def type_keys(keys):
            for key in keys:
                if time.monotonic() >= deadline:
                    raise ProbeFailure('interactive input timed out')
                try:
                    os.write(master, bytes([key]))
                except OSError as error:
                    raise ProbeFailure('test shell exited while receiving input') from error
                time.sleep(0.003)

        try:
            fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', 24, columns, 0, 0))
            expect(prompt)
            if dependencies is None:
                dependencies = []
            if inspect_dependencies:
                excluded = {str(Path(bash).resolve())}
                if plugin:
                    excluded.add(str(plugin.resolve()))
                dependencies.extend(mapped_dependencies(pid, excluded))
            if dependencies_only:
                return dependencies
            if check_display:
                for prefix in (b'#a ', b'#b '):
                    start_x, start_y = cursor.x, cursor.y
                    rendered = b''
                    for index, key in enumerate(prefix, 1):
                        type_keys(bytes([key]))
                        settle = min(deadline, time.monotonic() + 0.15)
                        while time.monotonic() < settle:
                            if select.select([master], [], [], max(0, settle - time.monotonic()))[0]:
                                rendered += receive()
                        if time.monotonic() >= deadline:
                            raise ProbeFailure('display check timed out')
                        if (cursor.x, cursor.y) != (start_x + index, start_y):
                            raise ProbeFailure('suggestion at terminal right margin moves the input cursor')
                    if plugin and b'x' * 20 not in rendered:
                        raise ProbeFailure('history suggestion was not rendered in display check')
                    type_keys(b'\x15\r')
                    expect(b'\r\n')
                    expect(prompt)
            type_keys(b"printf '%s%s\\n' BM_ SPACE\r")
            # Bracketed-paste teardown can put an escape sequence and CR before output.
            expect(b'BM_SPACE\r\n')
            expect(b'BASH_MODERN_PROBE> ')
            type_keys(b"printf '%s%s\\n' BM_ EDIQ\x7fT\r")
            expect(b'BM_EDIT\r\n')
            expect(b'BASH_MODERN_PROBE> ')
            type_keys(b'\x1b[A\r')
            expect(b'BM_EDIT\r\n')
            expect(b'BASH_MODERN_PROBE> ')
            if plugin:
                type_keys(b"bmprobe '%s%s\\n' BM_ ABBR\r")
                expect(b'BM_ABBR\r\n')
                expect(b'BASH_MODERN_PROBE> ')
            return dependencies
        finally:
            # Children, including suggestion workers, stay in this disposable session.
            try:
                os.killpg(pid, signal.SIGKILL)
            except PermissionError:
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            except ProcessLookupError:
                pass
            os.close(master)
            try:
                os.waitpid(pid, 0)
            except ChildProcessError:
                pass


def cache_path(home):
    return home / 'user/autosuggestions-check.json'


def plugin_path(home):
    return home / 'vendor/bash-autosuggestions/bash-autosuggestions.so'


def save_cache(home, record):
    directory = home / 'user'
    directory.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.autosuggestions-', dir=directory)
    try:
        with os.fdopen(fd, 'w') as output:
            json.dump(record, output)
            output.write('\n')
        os.replace(name, cache_path(home))
    finally:
        if os.path.exists(name):
            os.unlink(name)


def status(home, bash, version, honor_off=True):
    if honor_off and (home / 'user/autosuggestions.disabled').exists():
        return 'off', 'disabled by user'
    if any(os.environ.get(name) for name in ('LD_PRELOAD', 'LD_LIBRARY_PATH', 'LD_AUDIT')):
        return 'unverified', 'unverified (custom dynamic-linker environment)'
    plugin = plugin_path(home)
    if not plugin.is_file():
        if plugin.with_name(plugin.name + '.disabled').exists():
            return 'off', 'disabled by renamed plugin; run bash-modern autosuggestions on'
        return 'missing', 'missing'
    try:
        built_for = (plugin.parent / '.bash-version').read_text().strip()
        if built_for != version:
            return 'mismatch', 'rebuild required (built for ' + built_for + ')'
        record = json.loads(cache_path(home).read_text())
        if record.get('fingerprint') != fingerprint(home, bash, version, plugin, record.get('fingerprint')):
            return 'unverified', 'unverified (Bash, plugin or probe changed; run bash-modern autosuggestions check)'
        for dependency in record['dependencies']:
            if cached_identity(dependency['path'], dependency) != dependency:
                return 'unverified', 'unverified (runtime libraries changed; run bash-modern autosuggestions check)'
        state = record['status']
        if state not in ('passed', 'incompatible', 'unverified'):
            raise ValueError('unknown cache status')
        return state, record['detail']
    except (OSError, ValueError, KeyError, TypeError):
        return 'unverified', 'unverified (run bash-modern autosuggestions check)'


@contextmanager
def check_lock(home):
    import fcntl
    directory = home / 'user'
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / 'autosuggestions-check.lock').open('a') as lock:
        deadline = time.monotonic() + 40
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise OSError('compatibility check is busy; retry')
                time.sleep(0.05)
        yield


def check(home, bash, version, enable=False):
    with check_lock(home):
        return _check(home, bash, version, enable)


def allow(home, bash, version):
    state, _ = status(home, bash, version)
    if state != 'unverified':
        return state == 'passed'
    if any(os.environ.get(name) for name in ('LD_PRELOAD', 'LD_LIBRARY_PATH', 'LD_AUDIT')):
        return False
    with check_lock(home):
        state, _ = status(home, bash, version)
        if state != 'unverified':
            return state == 'passed'
        try:
            record = json.loads(cache_path(home).read_text())
            before = fingerprint(home, bash, version, plugin_path(home), record.get('fingerprint'))
            previous = record.get('fingerprint') or {}
            unchanged = all(before[key] == previous.get(key) for key in ('schema', 'version', 'files'))
            dependencies_unchanged = all(cached_identity(d['path'], d) == d for d in record['dependencies'])
            # Do not retry a failed check on every login when its environment is unchanged.
            if before == previous and dependencies_unchanged:
                return False
            if unchanged and dependencies_unchanged and record['status'] == 'passed':
                dependencies = []
                for plugin in (None, plugin_path(home)):
                    probe(bash, home, plugin, check_display=False, dependencies_only=True,
                          dependencies=dependencies)
                actual = {entry['path']: entry for entry in dependencies}
                expected = {entry['path']: entry for entry in record['dependencies']}
                if actual == expected and fingerprint(home, bash, version, plugin_path(home)) == before:
                    record['fingerprint'] = before
                    save_cache(home, record)
                    return True
        except (OSError, ValueError, KeyError, TypeError, ProbeFailure):
            pass
        with redirect_stdout(sys.stderr):
            print('bash-modern: environment changed; checking autosuggestions compatibility…')
            return _check(home, bash, version) == 0


def _check(home, bash, version, enable=False):
    user_off = home / 'user/autosuggestions.disabled'
    plugin = plugin_path(home)
    if enable and not plugin.is_file() and plugin.with_name(plugin.name + '.disabled').is_file():
        plugin = plugin.with_name(plugin.name + '.disabled')
    record = {'status': 'unverified', 'detail': 'unverified (check did not finish)',
              'fingerprint': None, 'dependencies': []}
    save_cache(home, record)
    before = None
    try:
        if any(os.environ.get(name) for name in ('LD_PRELOAD', 'LD_LIBRARY_PATH', 'LD_AUDIT')):
            raise OSError('custom dynamic-linker environment is not covered by the isolated probe')
        if not plugin.is_file():
            raise OSError('plugin missing; install it first')
        built_for = (plugin.parent / '.bash-version').read_text().strip()
        if built_for != version:
            raise OSError('Bash version changed; rerun the installer to rebuild the plugin')
        before = fingerprint(home, bash, version, plugin)
        record['fingerprint'] = before
        try:
            probe(bash, home, dependencies=record['dependencies'])
        except ProbeFailure as error:
            raise OSError('baseline input failed: ' + str(error)) from error
        for mode in ('0', 'auto'):
            probe(bash, home, plugin, mode, dependencies=record['dependencies'])
        if fingerprint(home, bash, version, plugin) != before:
            raise OSError('Bash or plugin changed during the check; retry')
        if plugin != plugin_path(home):
            plugin.rename(plugin_path(home))
            plugin = plugin_path(home)
            record['fingerprint'] = fingerprint(home, bash, version, plugin)
        record.update(status='passed', detail='ok (interactive input and display verified)')
    except ProbeFailure as error:
        record.update(status='incompatible', detail='incompatible; disabled (' + str(error) + ')')
    except (OSError, ImportError, ValueError) as error:
        record.update(status='unverified', detail='unverified; disabled (' + str(error) + ')')
    record['dependencies'] = list({entry['path']: entry for entry in record['dependencies']}.values())
    save_cache(home, record)
    if enable and record['status'] == 'passed':
        try:
            user_off.unlink()
        except FileNotFoundError:
            pass
    print(record['detail'])
    if user_off.exists():
        print('User preference remains off; use bash-modern autosuggestions on to enable.')
    return 0 if record['status'] == 'passed' else 2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['status', 'allow', 'check', 'on'])
    parser.add_argument('--home', required=True, type=Path)
    parser.add_argument('--bash', required=True, type=Path)
    parser.add_argument('--version', required=True)
    args = parser.parse_args()
    if args.action in ('check', 'on'):
        return check(args.home, args.bash, args.version, args.action == 'on')
    if args.action == 'allow':
        return 0 if allow(args.home, args.bash, args.version) else 1
    state, detail = status(args.home, args.bash, args.version)
    if args.action == 'status':
        print(detail)
        return 0
    return 0 if state == 'passed' else 1


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print('unverified; disabled (' + str(error) + ')')
        raise SystemExit(2)
