#!/usr/bin/env python3
"""Gate native autosuggestions on a cached, isolated interactive input test."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import select
import signal
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


def fingerprint(home, bash, version, plugin):
    paths = [bash, plugin, home / 'vendor/bash-autosuggestions/bash-autosuggestions.bash',
             home / 'vendor/bash-autosuggestions/.bash-version',
             home / 'lib/autosuggestions.py', home / 'bashrc.d/10-shell-options.sh',
             home / 'bashrc.d/40-abbreviations.sh']
    linker = {}
    for path in (Path('/etc/ld.so.cache'), Path('/etc/ld.so.preload')):
        linker[str(path)] = file_identity(path) if path.exists() else None
    return {'schema': SCHEMA, 'version': version, 'linker': linker,
            'files': [file_identity(path) for path in paths]}


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


def probe(bash, home, plugin=None, async_mode='0', timeout_ms=TIMEOUT_MS,
          inspect_dependencies=True, dependencies=None):
    import pty
    import termios
    import struct
    import fcntl

    with tempfile.TemporaryDirectory(prefix='bash-modern-probe-') as temporary:
        directory = Path(temporary)
        (directory / 'user').mkdir()
        rc = directory / 'rc'
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

        def expect(token):
            nonlocal pending, total_output
            while token not in pending:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not select.select([master], [], [], remaining)[0]:
                    raise ProbeFailure('interactive input timed out')
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
            fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 120, 0, 0))
            expect(b'BASH_MODERN_PROBE> ')
            if dependencies is None:
                dependencies = []
            if inspect_dependencies:
                excluded = {str(Path(bash).resolve())}
                if plugin:
                    excluded.add(str(plugin.resolve()))
                dependencies.extend(mapped_dependencies(pid, excluded))
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
        if record.get('fingerprint') != fingerprint(home, bash, version, plugin):
            return 'unverified', 'unverified (Bash, plugin or probe changed; run bash-modern autosuggestions check)'
        for dependency in record['dependencies']:
            if file_identity(dependency['path']) != dependency:
                return 'unverified', 'unverified (runtime libraries changed; run bash-modern autosuggestions check)'
        state = record['status']
        if state not in ('passed', 'incompatible', 'unverified'):
            raise ValueError('unknown cache status')
        return state, record['detail']
    except (OSError, ValueError, KeyError, TypeError):
        return 'unverified', 'unverified (run bash-modern autosuggestions check)'


def check(home, bash, version, enable=False):
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
        record.update(status='passed', detail='ok (interactive input verified)')
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
