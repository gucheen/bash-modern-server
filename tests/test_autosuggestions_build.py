#!/usr/bin/env python3

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE_URL = 'https://github.com/gucheen/bash-autosuggestions.git'
SOURCE = 'fork source\n'


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
        self.tool('git', f'''import os, shutil, subprocess, sys
from pathlib import Path
if 'clone' in sys.argv:
    assert sys.argv[1:4] == ['clone', '--depth', '1'], sys.argv
    assert sys.argv[-2] == {SOURCE_URL!r}, sys.argv
    count = Path({str(self.root / 'clone-count')!r})
    count.write_text(count.read_text() + 'clone\\n' if count.exists() else 'clone\\n')
    if os.environ.get('BM_CLONE_FAIL'): sys.exit(1)
    target = sys.argv[-1]
    shutil.copytree({str(self.target)!r}, target)
    subprocess.run([{git!r}, '-C', target, 'init', '-q'], check=True, timeout=60)
    subprocess.run([{git!r}, '-C', target, 'remote', 'add', 'origin', {SOURCE_URL!r}], check=True, timeout=60)
    sys.exit(0)
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
                                 'source "$1"; _bash_modern_build_autosuggestions "$2" /usr/include',
                                 'test', str(ROOT / 'lib/autosuggestions-build.sh'), str(self.target)])

    def test_rebuild_replaces_old_binary_and_records_version(self):
        (self.target / 'bash-autosuggestions.so').write_text('old binary')
        for _ in range(2):
            result = self.build()
            self.assertEqual(result.returncode, 0, result.stderr)
            binary = (self.target / 'bash-autosuggestions.so').read_text()
            self.assertEqual(binary, SOURCE)
            version = self.run_command(['/bin/bash', '-c', 'printf %s "$BASH_VERSION"']).stdout
            self.assertEqual((self.target / '.bash-version').read_text(), version + '\n')

    def test_failed_or_missing_build_cannot_reuse_stamp(self):
        for failure in ('BM_BUILD_FAIL', 'BM_BUILD_MISSING'):
            with self.subTest(failure=failure):
                self.assertEqual(self.build().returncode, 0)
                self.environment[failure] = '1'
                self.assertNotEqual(self.build().returncode, 0)
                self.assertFalse((self.target / 'bash-autosuggestions.so').exists())
                self.assertFalse((self.target / '.bash-version').exists())
                del self.environment[failure]

    def test_renamed_plugin_stays_disabled(self):
        disabled = self.target / 'bash-autosuggestions.so.disabled'
        disabled.write_text('old disabled binary')
        self.assertEqual(self.build().returncode, 0)
        self.assertEqual(disabled.read_text(), SOURCE)
        self.assertFalse((self.target / 'bash-autosuggestions.so').exists())

    def prepare_install(self, origin=None, renamed=False):
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
        binary = 'bash-autosuggestions.so.disabled' if renamed else 'bash-autosuggestions.so'
        (target / binary).write_text('old binary')
        (target / 'src/bash_autosuggestions.c').write_text('old source\n')
        (target / '.bash-modern-display-patch').write_text('old patch\n')
        if origin:
            self.assertEqual(self.run_command(['git', '-C', str(target), 'init', '-q']).returncode, 0)
            self.assertEqual(self.run_command(['git', '-C', str(target), 'remote', 'add', 'origin', origin]).returncode, 0)
        version = self.run_command(['/bin/bash', '-c', 'printf %s "$BASH_VERSION"']).stdout
        (target / '.bash-version').write_text(version + '\n')
        if not renamed:
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
        return install, config, target

    def test_installer_migrates_upstream_once_and_preserves_disabled(self):
        install, config, target = self.prepare_install('https://github.com/wallentx/bash-autosuggestions.git')
        result = self.run_command(install + ['--skip-downloads'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((target / 'bash-autosuggestions.so').read_text(), 'old binary')
        for _ in range(2):
            result = self.run_command(install)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((config / 'user/autosuggestions.disabled').exists())
            self.assertEqual((target / 'bash-autosuggestions.so').read_text(), SOURCE)
            self.assertFalse((target / '.bash-modern-display-patch').exists())
        self.assertEqual((self.root / 'build-count').read_text(), 'build\n')
        self.assertEqual((self.root / 'clone-count').read_text(), 'clone\n')

    def test_installer_replaces_source_without_origin_and_preserves_renamed_preference(self):
        install, config, target = self.prepare_install(renamed=True)
        for _ in range(2):
            result = self.run_command(install)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((config / 'user/autosuggestions.disabled').exists())
            self.assertEqual((target / 'bash-autosuggestions.so').read_text(), SOURCE)
        self.assertEqual((self.root / 'clone-count').read_text(), 'clone\n')
        self.assertEqual((self.root / 'build-count').read_text(), 'build\n')

    def test_installer_reuses_fork_and_rebuilds_for_changed_bash(self):
        install, _, target = self.prepare_install(SOURCE_URL)
        result = self.run_command(install)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((target / 'bash-autosuggestions.so').read_text(), 'old binary')
        self.assertFalse((target / '.bash-modern-display-patch').exists())
        self.assertFalse((self.root / 'build-count').exists())
        (target / '.bash-version').write_text('different Bash\n')
        result = self.run_command(install)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((target / 'bash-autosuggestions.so').read_text(), 'old source\n')
        self.assertEqual((self.root / 'build-count').read_text(), 'build\n')
        self.assertFalse((self.root / 'clone-count').exists())

    def test_installer_failed_migration_does_not_keep_old_binary(self):
        install, config, target = self.prepare_install(renamed=True)
        for failure in ('BM_CLONE_FAIL', 'BM_BUILD_FAIL'):
            with self.subTest(failure=failure):
                self.environment[failure] = '1'
                result = self.run_command(install)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertFalse((target / 'bash-autosuggestions.so').exists())
                self.assertFalse((target / '.bash-version').exists())
                self.assertTrue((config / 'user/autosuggestions.disabled').exists())
                del self.environment[failure]


if __name__ == '__main__':
    unittest.main()
