"""Linux integration test: real 1 GiB allocation/mkswap; mocked swapon only.

All paths point into a temporary directory; host fstab and swap are untouched.
Run as root: python3 tests/test_setup_swap.py
"""
import os
import pathlib
import subprocess
import tempfile

assert os.geteuid() == 0, 'Run in a disposable Linux environment as root.'
source = (pathlib.Path(__file__).resolve().parents[1] / 'setup_swap.sh').read_text()
with tempfile.TemporaryDirectory(prefix='cm0-swap-test-') as directory:
    root = pathlib.Path(directory)
    swap = root / 'swapfile'
    fstab = root / 'fstab'
    fstab.write_text('# preserved root configuration\n/dev/root / ext4 defaults 0 1\n')
    script = root / 'setup.sh'
    script.write_text(source.replace('SWAP_FILE="/swapfile"', f'SWAP_FILE="{swap}"')
                     .replace('FSTAB="/etc/fstab"', f'FSTAB="{fstab}"'))
    commands = root / 'bin'
    commands.mkdir()
    fake_swapon = commands / 'swapon'
    fake_swapon.write_text('''#!/bin/bash
set -eu
if [[ $1 == --show=NAME ]]; then
    [[ ! -f "$TEST_ROOT/active" ]] || cat "$TEST_ROOT/active"
elif [[ ${FAIL_SWAPON:-0} == 1 ]]; then
    exit 1
else
    echo "$1" > "$TEST_ROOT/active"
    echo activated >> "$TEST_ROOT/calls"
fi
''')
    fake_swapon.chmod(0o755)
    env = dict(os.environ, PATH=str(commands)+':'+os.environ['PATH'], TEST_ROOT=str(root))

    def run(success, **overrides):
        result = subprocess.run(['bash', str(script)], env=dict(env, **overrides),
                                text=True, capture_output=True)
        assert (result.returncode == 0) == success, result.stdout + result.stderr
        return result.stdout + result.stderr

    run(False, FAIL_SWAPON='1')
    assert swap.stat().st_size == 1073741824
    assert swap.stat().st_mode & 0o777 == 0o600
    assert subprocess.check_output(['blkid', '-p', '-s', 'TYPE', '-o', 'value', str(swap)], text=True).strip() == 'swap'
    assert str(swap) not in fstab.read_text(), 'Do not persist failed activation'
    identity = (swap.stat().st_ino, swap.stat().st_mtime_ns)
    run(True)
    run(True)
    assert identity == (swap.stat().st_ino, swap.stat().st_mtime_ns), 'Must reuse valid file'
    assert fstab.read_text().count(str(swap)) == 1, 'No duplicate fstab entries'
    assert (root / 'calls').read_text().splitlines() == ['activated']
    assert (root / 'fstab.before-cm0-swap').read_text().startswith('# preserved root')

    saved = root / 'saved-swap'
    swap.rename(saved)
    swap.write_text('existing user data')
    run(False)
    assert swap.read_text() == 'existing user data'
    swap.unlink()
    swap.symlink_to(saved)
    run(False)
    swap.unlink()
    with swap.open('wb') as file:
        file.truncate(1073741824)
    run(False)  # Correct size alone does not identify a swap file.
    swap.unlink()

    fake_df = commands / 'df'
    fake_df.write_text('#!/bin/sh\nprintf "Filesystem 1024-blocks Used Available Capacity Mounted\\nroot 2000000 1999999 1 99%% /\\n"\n')
    fake_df.chmod(0o755)
    assert 'free disk space' in run(False)
    assert not swap.exists()
    fake_df.unlink()

    fake_dd = commands / 'dd'
    fake_dd.write_text('#!/bin/bash\nfor arg; do case "$arg" in of=*) echo partial > "${arg#of=}";; esac; done\nexit 1\n')
    fake_dd.chmod(0o755)
    run(False)
    assert not list(root.glob('swapfile.cm0-*')), 'Partial allocation must be removed'
    assert not swap.exists()
    saved.rename(swap)
    fstab.write_text(f'{swap} none swap noauto 0 0\n')
    assert 'Conflicting' in run(False)
    print('PASS: 1 GiB allocation, format, permissions, activation retry, persistence,')
    print('      idempotency, existing-file protection, free space and failure cleanup.')
