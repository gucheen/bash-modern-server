#!/usr/bin/env python3
"""Check native suggestion rendering with an independent VT emulator (requires pyte)."""

import argparse
import fcntl
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import struct
import tempfile
import termios
import time

import pyte


ROOT = Path(__file__).resolve().parents[1]


class Screen(pyte.Screen):
    def select_graphic_rendition(self, *attributes, **options):
        # Vim's private key-reporting controls do not change text colors.
        if not options.get('private'):
            super().select_graphic_rendition(*attributes)


def check(bash, plugin, columns, length, async_mode, action=None, timeout_ms=10000):
    with tempfile.TemporaryDirectory(prefix='suggestion-display-') as temporary:
        directory = Path(temporary)
        (directory / 'user').mkdir()
        rc = directory / 'rc'
        command = 'echo ' + 'x' * (length - 5)
        rc.write_text(
            "PS1='\\[\\e[36m\\]PROMPT> \\[\\e[0m\\]'\nHISTFILE=/dev/null\n"
            "set -o emacs\nBASH_AUTOSUGGEST_STRATEGY=history\n"
            'BASH_AUTOSUGGEST_USE_ASYNC="$PROBE_ASYNC"\n'
            'if [[ $PROBE_ACTION == fzf ]]; then\n'
            '  _fzf_init=$(fzf --bash) || exit 90\n'
            '  eval "$_fzf_init"\n'
            'fi\n'
            'enable -f "$PROBE_PLUGIN" bash_autosuggestions || exit 91\n'
            'source "$PROBE_ROOT/bashrc.d/10-shell-options.sh"\n'
            'source "$PROBE_ROOT/bashrc.d/40-abbreviations.sh"\n'
            f"history -s '{command}'\n"
            "printf 'sentinel 1\\nsentinel 2\\nsentinel 3\\n'\n"
        )
        environment = dict(HOME=temporary, BASH_MODERN_HOME=temporary, PATH='/usr/bin:/bin',
                           TERM='xterm', INPUTRC='/dev/null', LC_ALL='C',
                           PROBE_ROOT=str(ROOT), PROBE_PLUGIN=str(plugin),
                           PROBE_ASYNC=async_mode, PROBE_ACTION=action or '',
                           PROBE_VIM=shutil.which('vim') or shutil.which('vim.tiny') or '',
                           FZF_DEFAULT_OPTS='--height=40% --no-mouse')
        pid, master = pty.fork()
        if pid == 0:
            os.execve(str(bash), [str(bash), '--noprofile', '--rcfile', str(rc), '-i'], environment)
        screen = Screen(columns, 24)
        screen.write_process_input = lambda reply: os.write(master, reply.encode())
        stream = pyte.ByteStream(screen)
        deadline = time.monotonic() + timeout_ms / 1000

        def drain(duration=0.08):
            end = min(deadline, time.monotonic() + duration)
            output = b''
            while time.monotonic() < end:
                if select.select([master], [], [], max(0, end - time.monotonic()))[0]:
                    try:
                        data = os.read(master, 65536)
                    except OSError as error:
                        raise AssertionError(('test shell exited', action, screen.display)) from error
                    output += data
                    stream.feed(data)
            if time.monotonic() >= deadline:
                raise AssertionError('terminal check timed out')
            return output

        def send(keys, duration=0.08):
            os.write(master, keys)
            return drain(duration)

        try:
            fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', 24, columns, 0, 0))
            drain(0.2)
            if action == 'vim':
                assert environment['PROBE_VIM'], 'Vim is required for --full-screen'
                output = send(b'"$PROBE_VIM" -u NONE -i NONE -n /dev/null\r', 0.3)
                assert b'\x1b[?1049h' in output, ('Vim did not enter alternate screen', output)
                send(b':q!\r', 0.3)
            elif action == 'fzf':
                output = send(b'\x12', 0.3)
                assert b'x' * 20 in output, ('fzf did not display command history', output)
                send(b'\x03', 0.3)
            if action:
                # Reposition after full-screen output so upward drift cannot be clamped at row zero.
                send(b"printf '\\033[H\\033[2J\\n\\n\\n\\n'\r", 0.2)
            start_x, start_y = screen.cursor.x, screen.cursor.y
            assert start_x == 8 and start_y >= 2, screen.display
            previous = screen.display[:start_y]
            typed = ''
            for key in b'echo\x7fo':
                typed = typed[:-1] if key == 127 else typed + chr(key)
                send(bytes([key]))
                actual = (screen.cursor.x, screen.cursor.y)
                expected = (start_x + len(typed), start_y)
                assert actual == expected, (columns, length, async_mode, action, typed, actual, expected)
                assert screen.display[:start_y] == previous, 'previous output was overwritten'
                visible = ''.join(screen.display[start_y:])
                assert visible.startswith('PROMPT> ' + command), visible
            send(b'\x06')
            expected = ((8 + length) % columns, start_y + (8 + length) // columns)
            assert (screen.cursor.x, screen.cursor.y) == expected, ('accept', screen.display)
            assert ''.join(screen.display[start_y:]).startswith('PROMPT> ' + command)
            send(b'\x03')
            start_x, start_y = screen.cursor.x, screen.cursor.y
            assert start_x == 8, ('interrupt', screen.display)
            send(b'e')
            assert (screen.cursor.x, screen.cursor.y) == (9, start_y), ('after interrupt', screen.display)
        finally:
            os.killpg(pid, signal.SIGKILL)
            os.close(master)
            os.waitpid(pid, 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bash', type=Path, default=Path('/bin/bash'))
    parser.add_argument('--plugin', type=Path, required=True)
    parser.add_argument('--full-screen', action='store_true', help='Also exercise installed Vim and fzf.')
    args = parser.parse_args()
    count = 0
    for mode in ('0', 'auto'):
        for columns in (40, 80, 120):
            for rows in (1, 2):
                for offset in (-1, 0, 1):
                    check(args.bash.resolve(), args.plugin.resolve(), columns, columns * rows - 8 + offset, mode)
                    count += 1
        if args.full_screen:
            for action in ('vim', 'fzf'):
                check(args.bash.resolve(), args.plugin.resolve(), 80, 72, mode, action)
                count += 1
    print(f'PASS: {count} native display cases (typing, backspace, acceptance and interruption).')


if __name__ == '__main__':
    main()
