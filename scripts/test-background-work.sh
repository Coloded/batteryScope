#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sparkle_root="$(zsh scripts/fetch-sparkle.sh --check-only)"
export BATTERYSCOPE_TEST_SPARKLE="$sparkle_root"
python3 - <<'PY'
import os, pathlib, subprocess
root=pathlib.Path.cwd()
files=sorted(str(p) for p in (root/'Sources').rglob('*.swift') if not p.name.startswith('._') and p.name != 'BatteryScopeApp.swift')
output=pathlib.Path(os.environ.get('TMPDIR','/tmp'))/'batteryscope-background-tests'
sparkle=os.environ['BATTERYSCOPE_TEST_SPARKLE']
subprocess.run(['swiftc','-parse-as-library','-F',sparkle,'-framework','Sparkle','-Xlinker','-rpath','-Xlinker',sparkle,*files,'Tests/BackgroundWorkTests.swift','-o',str(output)],check=True)
subprocess.run([str(output)],check=True)
PY
