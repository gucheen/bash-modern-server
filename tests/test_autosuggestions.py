#!/usr/bin/env python3

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('autosuggestions', ROOT / 'lib/autosuggestions.py')
autosuggestions = importlib.util.module_from_spec(spec)
spec.loader.exec_module(autosuggestions)
BASH = Path('/bin/bash')
VERSION = subprocess.check_output(
    [str(BASH), '--noprofile', '--norc', '-c', 'printf %s "$BASH_VERSION"'],
    timeout=10, text=True,
).strip()


class DisplayTests(unittest.TestCase):
    def test_right_margin_waits_for_next_character_before_wrapping(self):
        cursor = autosuggestions.ProbeCursor(columns=10)
        cursor.feed(b'\n\n1234567890\x1b[0m')
        self.assertEqual((cursor.x, cursor.y), (10, 2))
        cursor.feed(b'\x1b[3G')
        self.assertEqual((cursor.x, cursor.y), (2, 2))
        cursor.feed(b'123456789')
        self.assertEqual((cursor.x, cursor.y), (1, 3))

    def test_fragmented_suggestion_repaint_preserves_cursor(self):
        cursor = autosuggestions.ProbeCursor(columns=10)
        for chunk in (b'\n\nP> e', b'\x1b[38;', b'5;8mcho xxx',
                      b'\x1b[0m\x1b[', b'1A\x1b[5G'):
            cursor.feed(chunk)
        self.assertEqual((cursor.x, cursor.y), (4, 2))

    def test_exact_width_suggestion_repaint_moves_above_prompt(self):
        cursor = autosuggestions.ProbeCursor(columns=10)
        cursor.feed(b'\n\nP> e\x1b[38;5;8mcho xx\x1b[0m\x1b[1A\x1b[5G')
        self.assertEqual((cursor.x, cursor.y), (4, 1))


class CompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='autosuggestions-test-')
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name) / 'config'
        for directory in ('lib', 'bin', 'bashrc.d', 'user', 'vendor/bash-autosuggestions'):
            (self.home / directory).mkdir(parents=True)
        for name in ('lib/autosuggestions.py', 'lib/autosuggestions.sh', 'bin/bash-modern',
                     'bashrc.d/10-shell-options.sh', 'bashrc.d/30-integrations.sh',
                     'bashrc.d/40-abbreviations.sh'):
            shutil.copy2(ROOT / name, self.home / name)
        self.plugin = autosuggestions.plugin_path(self.home)
        self.plugin.write_bytes(b'fixture, never loaded as native code')
        (self.plugin.parent / '.bash-version').write_text(VERSION + '\n')
        self.loader = self.plugin.parent / 'bash-autosuggestions.bash'
        self.loader.write_text('printf LOADER_RAN\n')
        self.off = self.home / 'user/autosuggestions.disabled'

    def passed_cache(self, dependencies=None):
        autosuggestions.save_cache(self.home, {
            'status': 'passed', 'detail': 'ok (interactive input verified)',
            'fingerprint': autosuggestions.fingerprint(self.home, BASH, VERSION, self.plugin),
            'dependencies': dependencies or [],
        })

    def state(self):
        return autosuggestions.status(self.home, BASH, VERSION)[0]

    def test_missing_and_malformed_cache_fail_closed(self):
        self.assertEqual(self.state(), 'unverified')
        autosuggestions.cache_path(self.home).write_text('{bad cache')
        self.assertEqual(self.state(), 'unverified')
        self.plugin.unlink()
        self.assertEqual(self.state(), 'missing')

    def test_bash_replacement_with_same_version_invalidates_cache(self):
        executable = Path(self.temporary.name) / 'bash'
        executable.write_bytes(b'first executable')
        record = {'status': 'passed', 'detail': 'ok', 'dependencies': [],
                  'fingerprint': autosuggestions.fingerprint(self.home, executable, VERSION, self.plugin)}
        autosuggestions.save_cache(self.home, record)
        self.assertEqual(autosuggestions.status(self.home, executable, VERSION)[0], 'passed')
        executable.write_bytes(b'other executable')
        self.assertEqual(autosuggestions.status(self.home, executable, VERSION)[0], 'unverified')

    def test_plugin_loader_probe_and_bindings_changes_invalidate_cache(self):
        for path in (self.plugin, self.loader, self.home / 'lib/autosuggestions.py',
                     self.home / 'bashrc.d/40-abbreviations.sh'):
            with self.subTest(path=path):
                self.passed_cache()
                self.assertEqual(self.state(), 'passed')
                path.write_bytes(path.read_bytes() + b'\n')
                self.assertEqual(self.state(), 'unverified')

    def test_runtime_library_changes_invalidate_cache(self):
        library = Path(self.temporary.name) / 'library.so'
        library.write_bytes(b'original')
        self.passed_cache([autosuggestions.file_identity(library)])
        self.assertEqual(self.state(), 'passed')
        library.write_bytes(b'updated')
        self.assertEqual(self.state(), 'unverified')

    def test_valid_cache_does_not_hash_files_or_probe(self):
        self.passed_cache()
        with patch.object(autosuggestions, 'file_identity', side_effect=AssertionError('unexpected hash')), \
                patch.object(autosuggestions, 'probe') as probe:
            self.assertTrue(autosuggestions.allow(self.home, BASH, VERSION))
            probe.assert_not_called()

    def stale_linker_cache(self, dependencies=None):
        self.passed_cache(dependencies)
        path = autosuggestions.cache_path(self.home)
        import json
        record = json.loads(path.read_text())
        record['fingerprint']['linker'] = {'old-cache': None}
        autosuggestions.save_cache(self.home, record)

    def test_linker_change_with_same_dependencies_only_refreshes_cache(self):
        self.stale_linker_cache()
        with patch.object(autosuggestions, 'probe', return_value=[]) as probe, \
                patch.object(autosuggestions, '_check') as check:
            self.assertTrue(autosuggestions.allow(self.home, BASH, VERSION))
            self.assertEqual(probe.call_count, 2)
            self.assertTrue(all(call.kwargs['dependencies_only'] for call in probe.call_args_list))
            check.assert_not_called()
        self.assertEqual(self.state(), 'passed')

    def test_linker_resolving_new_library_requires_full_check(self):
        self.stale_linker_cache()
        library = Path(self.temporary.name) / 'new-library.so'
        library.write_bytes(b'new')
        def inspect(*args, **kwargs):
            kwargs['dependencies'].append(autosuggestions.file_identity(library))
        with patch.object(autosuggestions, 'probe', side_effect=inspect), \
                patch.object(autosuggestions, '_check', return_value=2) as check:
            self.assertFalse(autosuggestions.allow(self.home, BASH, VERSION))
            check.assert_called_once()

    def test_changed_component_is_automatically_checked(self):
        self.passed_cache()
        self.plugin.write_bytes(b'changed')
        with patch.object(autosuggestions, 'probe', return_value=[]) as probe:
            self.assertTrue(autosuggestions.allow(self.home, BASH, VERSION))
            self.assertEqual(probe.call_count, 3)
        self.assertEqual(self.state(), 'passed')

    def test_failed_auto_check_is_not_repeated_until_environment_changes(self):
        self.passed_cache()
        self.plugin.write_bytes(b'changed')
        with patch.object(autosuggestions, 'probe', side_effect=OSError('no PTY')) as probe:
            self.assertFalse(autosuggestions.allow(self.home, BASH, VERSION))
            self.assertFalse(autosuggestions.allow(self.home, BASH, VERSION))
            self.assertEqual(probe.call_count, 1)

    def test_auto_check_honors_user_off_and_custom_linker(self):
        self.stale_linker_cache()
        with patch.object(autosuggestions, 'probe') as probe:
            self.off.touch()
            self.assertFalse(autosuggestions.allow(self.home, BASH, VERSION))
            self.off.unlink()
            with patch.dict(os.environ, {'LD_LIBRARY_PATH': '/custom'}):
                self.assertFalse(autosuggestions.allow(self.home, BASH, VERSION))
            probe.assert_not_called()

    def test_custom_linker_environment_is_unverified(self):
        self.passed_cache()
        with patch.dict(os.environ, {'LD_LIBRARY_PATH': '/custom/libraries'}):
            self.assertEqual(self.state(), 'unverified')
            with patch.object(autosuggestions, 'probe') as probe:
                self.assertEqual(autosuggestions.check(self.home, BASH, VERSION), 2)
                probe.assert_not_called()

    def test_unavailable_dependency_inspection_is_not_a_plugin_incompatibility(self):
        with patch.object(autosuggestions, 'probe', side_effect=OSError('no /proc')):
            self.assertEqual(autosuggestions.check(self.home, BASH, VERSION), 2)
        self.assertEqual(self.state(), 'unverified')

    def test_off_overrides_pass_and_version_mismatch(self):
        self.passed_cache()
        self.off.touch()
        self.assertEqual(self.state(), 'off')
        self.off.unlink()
        (self.plugin.parent / '.bash-version').write_text('another version')
        self.assertEqual(self.state(), 'mismatch')

    def test_loader_only_sources_verified_plugin(self):
        environment = dict(os.environ, BASH_MODERN_HOME=str(self.home))
        def load():
            return subprocess.check_output(
                [str(BASH), '--noprofile', '--norc', '-c',
                 'source "$BASH_MODERN_HOME/bashrc.d/30-integrations.sh"'],
                env=environment, timeout=15, text=True,
            )
        self.assertNotIn('LOADER_RAN', load())
        self.passed_cache()
        self.assertIn('LOADER_RAN', load())
        self.off.touch()
        self.assertNotIn('LOADER_RAN', load())

    def test_failed_candidate_is_incompatible_but_baseline_failure_is_unverified(self):
        with patch.object(autosuggestions, 'probe', side_effect=[[], autosuggestions.ProbeFailure('timeout')]):
            self.assertEqual(autosuggestions.check(self.home, BASH, VERSION), 2)
        self.assertEqual(self.state(), 'incompatible')
        with patch.object(autosuggestions, 'probe', side_effect=autosuggestions.ProbeFailure('no PTY')):
            self.assertEqual(autosuggestions.check(self.home, BASH, VERSION), 2)
        self.assertEqual(self.state(), 'unverified')

    def test_check_preserves_off_and_on_requires_success(self):
        self.off.touch()
        with patch.object(autosuggestions, 'probe', return_value=[]):
            self.assertEqual(autosuggestions.check(self.home, BASH, VERSION), 0)
        self.assertEqual(self.state(), 'off')
        with patch.object(autosuggestions, 'probe', side_effect=[[], autosuggestions.ProbeFailure('timeout')]):
            self.assertEqual(autosuggestions.check(self.home, BASH, VERSION, enable=True), 2)
        self.assertTrue(self.off.exists())
        with patch.object(autosuggestions, 'probe', return_value=[]):
            self.assertEqual(autosuggestions.check(self.home, BASH, VERSION, enable=True), 0)
        self.assertEqual(self.state(), 'passed')

    def test_on_restores_renamed_plugin_only_after_success(self):
        disabled = self.plugin.with_name(self.plugin.name + '.disabled')
        self.plugin.rename(disabled)
        with patch.object(autosuggestions, 'probe', side_effect=[[], autosuggestions.ProbeFailure('timeout')]):
            self.assertEqual(autosuggestions.check(self.home, BASH, VERSION, enable=True), 2)
        self.assertTrue(disabled.exists())
        self.assertFalse(self.plugin.exists())
        with patch.object(autosuggestions, 'probe', return_value=[]):
            self.assertEqual(autosuggestions.check(self.home, BASH, VERSION, enable=True), 0)
        self.assertEqual(self.state(), 'passed')
        self.assertFalse(disabled.exists())

    def test_changed_during_check_cannot_be_enabled(self):
        def change(*args, **kwargs):
            self.plugin.write_bytes(self.plugin.read_bytes() + b'changed')
            return []
        with patch.object(autosuggestions, 'probe', side_effect=change):
            self.assertEqual(autosuggestions.check(self.home, BASH, VERSION, enable=True), 2)
        self.assertEqual(self.state(), 'unverified')

    def test_off_works_without_python(self):
        tools = Path(self.temporary.name) / 'tools'
        tools.mkdir()
        for tool in ('dirname', 'mkdir', 'touch'):
            (tools / tool).symlink_to(shutil.which(tool))
        environment = dict(os.environ, PATH=str(tools), BASH_MODERN_HOME=str(self.home))
        subprocess.run([str(BASH), str(self.home / 'bin/bash-modern'), 'autosuggestions', 'off'],
                       env=environment, check=True, timeout=10, stdout=subprocess.DEVNULL)
        self.assertTrue(self.off.exists())

    def test_real_bash_input(self):
        autosuggestions.probe(BASH, self.home, inspect_dependencies=sys.platform.startswith('linux'))

    def test_display_corruption_is_rejected_before_enter(self):
        fake = Path(self.temporary.name) / 'bad-display'
        fake.write_text(f'''#!{sys.executable}
import os, tty
tty.setraw(0)
os.write(1, b'\\r\\n' * 4 + b'BASH_MODERN_PROBE> ')
os.read(0, 1)
os.write(1, b'#\\x1b[20G\\x1b[38;5;8m' + b'x' * 101 + b'\\x1b[0m\\x1b[1A\\x1b[20G')
while os.read(0, 1): pass
''')
        fake.chmod(0o700)
        with self.assertRaisesRegex(autosuggestions.ProbeFailure, 'right margin'):
            autosuggestions.probe(fake, self.home, inspect_dependencies=False)

    def test_terminal_teardown_before_output(self):
        fake = Path(self.temporary.name) / 'terminal-replay'
        fake.write_text(f'''#!{sys.executable}
import os, tty
tty.setraw(0)
os.write(1, b'\\x1b[?2004hBASH_MODERN_PROBE> ')
for expected, marker in [(b"printf '%s%s\\\\n' BM_ SPACE", b'BM_SPACE'), (b"printf '%s%s\\\\n' BM_ EDIQ\\x7fT", b'BM_EDIT'), (b'\\x1b[A', b'BM_EDIT')]:
    command = b''
    while True:
        key = os.read(0, 1)
        if key == b'\\r': break
        command += key
    if command != expected: os._exit(1)
    os.write(1, command + b'\\r\\n\\x1b[?2004l\\r' + marker + b'\\r\\n\\x1b[?2004hBASH_MODERN_PROBE> ')
while os.read(0, 1): pass
''')
        fake.chmod(0o700)
        autosuggestions.probe(fake, self.home, inspect_dependencies=False, check_display=False)

    def test_stuck_input_has_bounded_timeout(self):
        fake = Path(self.temporary.name) / 'stuck-input'
        fake.write_text(f'''#!{sys.executable}
import os, time
os.write(1, b'BASH_MODERN_PROBE> ')
time.sleep(60)
''')
        fake.chmod(0o700)
        start = time.monotonic()
        with self.assertRaises(autosuggestions.ProbeFailure):
            autosuggestions.probe(fake, self.home, timeout_ms=500, inspect_dependencies=False)
        self.assertLess(time.monotonic() - start, 3)


if __name__ == '__main__':
    unittest.main()
