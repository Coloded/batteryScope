#!/usr/bin/env python3
"""Reject personal runtime files in tracked source or a staged application bundle."""
import argparse
from pathlib import Path
import subprocess
import sys


def personal_path(path):
    path = Path(path)
    name = path.name.lower()
    return (name.endswith(('.sqlite', '.db')) or '.sqlite-' in name or '.db-' in name
            or name == 'history.json'
            or name.startswith(('batteryscope-history', 'batteryscope-report', 'batteryscope-specifications'))
            or any(part.lower() in ('private-data', 'exports') or part.startswith('BatteryScope-History-v') for part in path.parts))


def check_bundle(root):
    problems = []
    permitted_resources = {'AppIcon.icns', 'Sparkle-LICENSE.txt', 'BuildManifest.json', 'MobileDevice-Licenses.txt'}
    for path in root.rglob('*'):
        if path.is_symlink() or not path.is_file():
            continue
        relative = path.relative_to(root)
        if personal_path(relative):
            problems.append(str(relative))
        if relative.parts[:2] == ('Contents', 'Resources') and str(relative.relative_to('Contents/Resources')) not in permitted_resources:
            problems.append('Unexpected resource: ' + str(relative))
        with path.open('rb') as stream:
            if stream.read(16) == b'SQLite format 3\x00':
                problems.append('Embedded database: ' + str(relative))
    return problems


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
    problems = [path for path in tracked if path and personal_path(path)]
    if args.app:
        if not (args.app / 'Contents/Info.plist').is_file():
            parser.error('--app must identify an existing application bundle')
        problems.extend(check_bundle(args.app))
    if problems:
        print('Private-data packaging check failed:\n' + '\n'.join(problems), file=sys.stderr)
        return 1
    print('PASS: no runtime-data paths tracked; bundle checked' if args.app else 'PASS: no runtime-data paths tracked')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
