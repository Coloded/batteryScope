#!/bin/bash
# Keep the Keychain-trusted executable at a persistent, versioned path.
# Never export the private key or grant access to arbitrary applications.
set -euo pipefail
cd "$(dirname "$0")/.."
sparkle_root="$(zsh scripts/fetch-sparkle.sh)"
python3 - "$sparkle_root" <<'PY'
import os, pathlib, subprocess, sys, tarfile, tempfile
source = pathlib.Path(sys.argv[1])
archive = pathlib.Path(str(source) + '.tar.xz')
root = pathlib.Path.home() / 'Library/Application Support/BatteryScopeSigning'
root.mkdir(parents=True, exist_ok=True, mode=0o700)
directory = root / source.name
directory.mkdir(exist_ok=True, mode=0o700)
target = directory / 'generate_appcast'
# fetch-sparkle has verified this archive against the pinned upstream SHA-256.
with tarfile.open(archive) as package:
    matches = [m for m in package.getmembers() if m.name.lstrip('./') == 'bin/generate_appcast' and m.isfile()]
    if len(matches) != 1: raise SystemExit('Missing verified signing executable')
    content = package.extractfile(matches[0]).read()
if target.is_symlink(): raise SystemExit('Refusing a symlink for signing executable')
if not target.exists() or target.read_bytes() != content:
    fd, temporary = tempfile.mkstemp(dir=directory)
    try:
        with os.fdopen(fd, 'wb') as output: output.write(content)
        os.chmod(temporary, 0o700)
        subprocess.run(['codesign', '--verify', '--strict', temporary], check=True)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)
print(target)
PY
