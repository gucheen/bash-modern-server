#!/usr/bin/env python3

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PATCH = ROOT / 'patches/bash-autosuggestions-deferred-wrap.patch'
SOURCE = r'''static void bas_draw_suggestion(void) {
  bas_move_cursor(out, cursor_row, suggestion_row, suggestion_col);
  fputs(style, out);
  fputs(bas_suffix, out);
  fputs("\033[0m", out);
  bas_move_cursor(out, bas_drawn_end_row, cursor_row, cursor_col);
  fflush(out);
}
'''


class BuildTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='autosuggestions-build-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.target = self.root / 'plugin'
        (self.target / 'src').mkdir(parents=True)
        (self.target / 'src/bash_autosuggestions.c').write_text(SOURCE)
        (self.target / 'Makefile').touch()
        (self.target / 'bash-autosuggestions.bash').touch()
        self.tools = self.root / 'tools'
        self.tools.mkdir()
        self.environment = dict(os.environ, PATH=str(self.tools) + ':' + os.environ['PATH'],
                                BM_BUILD_COUNT=str(self.root / 'build-count'))
        self.tool('make', '''import os, sys
from pathlib import Path
target = Path(sys.argv[sys.argv.index('-C') + 1])
count = Path(os.environ['BM_BUILD_COUNT'])
count.write_text(count.read_text() + 'build\\n' if count.exists() else 'build\\n')
if os.environ.get('BM_BUILD_MISSING'): sys.exit(0)
(target / 'bash-autosuggestions.so').write_text((target / 'src/bash_autosuggestions.c').read_text())
sys.exit(1 if os.environ.get('BM_BUILD_FAIL') else 0)
''')
        git = shutil.which('git')
        self.tool('git', f'''import os, sys
if 'clone' in sys.argv: sys.exit('Unexpected network access')
os.execv({git!r}, [{git!r}] + sys.argv[1:])
''')

    def tool(self, name, script):
        path = self.tools / name
        path.write_text(f'#!{sys.executable}\n' + script)
        path.chmod(0o700)

    def run_command(self, argv):
        return subprocess.run(argv, env=self.environment, text=True, capture_output=True, timeout=60)

    def build(self):
        return self.run_command(['/bin/bash', '-c',
                                 'source "$1"; _bash_modern_build_autosuggestions "$2" "$3" /usr/include',
                                 'test', str(ROOT / 'lib/autosuggestions-build.sh'), str(self.target), str(PATCH)])

    def test_patch_rebuild_and_repeated_application(self):
        (self.target / 'bash-autosuggestions.so').write_text('old binary')
        for _ in range(2):
            result = self.build()
            self.assertEqual(result.returncode, 0, result.stderr)
            binary = (self.target / 'bash-autosuggestions.so').read_text()
            self.assertIn(r'fputs("\033[0m \b", out);', binary)
            self.assertEqual(binary.count('Complete any pending'), 1)
            self.assertEqual((self.target / '.bash-modern-display-patch').read_bytes(), PATCH.read_bytes())

    def test_unknown_source_is_not_stamped_or_loaded(self):
        (self.target / 'src/bash_autosuggestions.c').write_text('unrecognized source\n')
        (self.target / 'bash-autosuggestions.so').write_text('old binary')
        self.assertNotEqual(self.build().returncode, 0)
        self.assertFalse((self.target / 'bash-autosuggestions.so').exists())
        self.assertFalse((self.target / '.bash-modern-display-patch').exists())
        self.assertFalse((self.root / 'build-count').exists())

    def test_failed_or_missing_build_cannot_reuse_stamp(self):
        for failure in ('BM_BUILD_FAIL', 'BM_BUILD_MISSING'):
            with self.subTest(failure=failure):
                self.assertEqual(self.build().returncode, 0)
                self.environment[failure] = '1'
                self.assertNotEqual(self.build().returncode, 0)
                self.assertFalse((self.target / 'bash-autosuggestions.so').exists())
                self.assertFalse((self.target / '.bash-modern-display-patch').exists())
                self.assertFalse((self.target / '.bash-version').exists())
                del self.environment[failure]

    def test_renamed_plugin_stays_disabled(self):
        disabled = self.target / 'bash-autosuggestions.so.disabled'
        disabled.write_text('old disabled binary')
        self.assertEqual(self.build().returncode, 0)
        self.assertIn(r'fputs("\033[0m \b", out);', disabled.read_text())
        self.assertFalse((self.target / 'bash-autosuggestions.so').exists())

    def test_installer_migrates_same_version_once_without_downloading(self):
        home = self.root / 'home'
        home.mkdir()
        config = home / '.config/bash-modern'
        self.environment.update(HOME=str(home), BASH_MODERN_HOME=str(config),
                                BASH_MODERN_BASHRC=str(home / '.bashrc'),
                                BASH_MODERN_BACKUP_ROOT=str(home / 'backups'))
        install = [str(ROOT / 'install.sh')]
        result = self.run_command(install + ['--skip-downloads'])
        self.assertEqual(result.returncode, 0, result.stderr)
        target = config / 'vendor/bash-autosuggestions'
        shutil.copytree(self.target, target)
        (target / 'bash-autosuggestions.so').write_text('old binary')
        version = self.run_command(['/bin/bash', '-c', 'printf %s "$BASH_VERSION"']).stdout
        (target / '.bash-version').write_text(version + '\n')
        (config / 'user/autosuggestions.disabled').touch()
        (config / 'vendor/fzf/bin').mkdir(parents=True)
        for path in (config / 'vendor/fzf/bin/fzf', config / 'bin/zoxide'):
            path.write_text('#!/bin/sh\nexit 0\n')
            path.chmod(0o700)
        include = self.root / 'include'
        (include / 'bash').mkdir(parents=True)
        (include / 'bash/builtins.h').touch()
        self.tool('pkg-config', f'import sys\nif "--variable=includedir" in sys.argv: print({str(include)!r})\n')
        self.tool('cc', 'pass\n')

        result = self.run_command(install + ['--skip-downloads'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((target / 'bash-autosuggestions.so').read_text(), 'old binary')
        for _ in range(2):
            result = self.run_command(install)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((config / 'user/autosuggestions.disabled').exists())
            self.assertIn(r'fputs("\033[0m \b", out);', (target / 'bash-autosuggestions.so').read_text())
        self.assertEqual((self.root / 'build-count').read_text(), 'build\n')


if __name__ == '__main__':
    unittest.main()
