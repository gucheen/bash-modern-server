#!/usr/bin/env python3
"""Linux integration test using native Bash binaries before and after readline83-001."""

import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('autosuggestions', ROOT / 'lib/autosuggestions.py')
autosuggestions = importlib.util.module_from_spec(spec)
spec.loader.exec_module(autosuggestions)
PLUGIN_COMMIT = 'd663277e5cb37259f49f69fa7455cc21946f4d39'
FIXED_PLUGIN_COMMIT = '4db0812f9f5f1a6c2ab7a6603c85fc97ccb763e0'


def run(argv, cwd=None, timeout_ms=1800000):
    subprocess.run(list(map(str, argv)), cwd=cwd, timeout=timeout_ms / 1000, check=True)


def download(url, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=60) as response:
        destination.write_bytes(response.read())


def main():
    if not sys.platform.startswith('linux'):
        raise RuntimeError('Run on Linux with build-essential, libreadline-dev, pkg-config and python3.')
    work = Path(tempfile.mkdtemp(prefix='bash-readline-regression-'))
    print('Artifacts: ' + str(work), flush=True)
    archive = work / 'bash-5.3.tar.gz'
    download('https://ftp.gnu.org/gnu/bash/bash-5.3.tar.gz', archive)
    run(['tar', '-xzf', archive, '-C', work], timeout_ms=60000)
    source = work / 'bash-5.3'
    for number in range(1, 10):
        name = f'bash53-{number:03d}'
        patch = work / name
        download('https://ftp.gnu.org/gnu/bash/bash-5.3-patches/' + name, patch)
        run(['patch', '--batch', '-p0', '-i', patch], cwd=source, timeout_ms=60000)
    build = work / 'build'
    build.mkdir()
    prefix = work / 'headers'
    run([source / 'configure', '--prefix=' + str(prefix), '--without-bash-malloc'], cwd=build)
    run(['make', '-j4'], cwd=build)
    bad_bash = work / 'bash-unpatched'
    shutil.copy2(build / 'bash', bad_bash)
    readline_patch = work / 'readline83-001'
    download('https://ftp.gnu.org/gnu/readline/readline-8.3-patches/readline83-001', readline_patch)
    input_patch = work / 'input.patch'
    input_patch.write_text(readline_patch.read_text().split('*** ../readline-8.3/patchlevel', 1)[0])
    run(['patch', '--batch', '-p0', '-i', input_patch], cwd=source / 'lib/readline', timeout_ms=60000)
    run(['make', '-j4'], cwd=build)
    good_bash = work / 'bash-patched'
    shutil.copy2(build / 'bash', good_bash)
    run(['make', 'install-headers'], cwd=build)

    home = work / 'config'
    for directory in ('lib', 'bashrc.d'):
        shutil.copytree(ROOT / directory, home / directory)
    plugin = home / 'vendor/bash-autosuggestions'
    for name in ('Makefile', 'src/bash_autosuggestions.c', 'bash-autosuggestions.bash'):
        download(f'https://raw.githubusercontent.com/wallentx/bash-autosuggestions/{PLUGIN_COMMIT}/{name}',
                 plugin / name)
    run(['make', 'all', 'BASH_INCLUDE=' + str(prefix / 'include')], cwd=plugin)
    version = subprocess.check_output([str(bad_bash), '-c', 'printf %s "$BASH_VERSION"'], text=True, timeout=10)
    (plugin / '.bash-version').write_text(version + '\n')
    try:
        autosuggestions.probe(bad_bash, home, plugin / 'bash-autosuggestions.so', check_display=False)
    except autosuggestions.ProbeFailure:
        pass
    else:
        raise RuntimeError('Unpatched Bash unexpectedly passed the input-only check')
    autosuggestions.probe(good_bash, home, plugin / 'bash-autosuggestions.so', check_display=False)
    if autosuggestions.check(home, bad_bash, version) != 2:
        raise RuntimeError('Unpatched Bash was not rejected')
    if autosuggestions.status(home, bad_bash, version)[0] != 'incompatible':
        raise RuntimeError('Expected an input incompatibility, not an unavailable test environment')
    if 'interactive input timed out' not in autosuggestions.status(home, bad_bash, version)[1]:
        raise RuntimeError('Stalled input was misreported as a display incompatibility')
    if autosuggestions.check(home, good_bash, version) != 2:
        raise RuntimeError('Faulty suggestion rendering was not rejected')
    if 'right margin' not in autosuggestions.status(home, good_bash, version)[1]:
        raise RuntimeError('Expected a display incompatibility after fixing Readline input')

    for name in ('Makefile', 'src/bash_autosuggestions.c', 'bash-autosuggestions.bash'):
        download(f'https://raw.githubusercontent.com/gucheen/bash-autosuggestions/{FIXED_PLUGIN_COMMIT}/{name}',
                 plugin / name)
    run([good_bash, '-c', 'source "$1"; _bash_modern_build_autosuggestions "$2" "$3"',
         'build', ROOT / 'lib/autosuggestions-build.sh', plugin, prefix / 'include'])
    if autosuggestions.check(home, good_bash, version) != 0:
        raise RuntimeError('Corrected Bash and suggestion renderer did not pass')
    if autosuggestions.status(home, good_bash, version)[0] != 'passed':
        raise RuntimeError('Successful check was not cached')
    if autosuggestions.status(home, bad_bash, version)[0] != 'unverified':
        raise RuntimeError('A different Bash binary reused the successful cache')
    print('PASS: faulty input and display rejected, corrected pair accepted, binary cache invalidated.')


if __name__ == '__main__':
    main()
