#!/usr/bin/env python3
"""Fail releases with missing, non-universal or externally linked mobile helpers."""
from pathlib import Path
import json,subprocess,sys,tarfile,hashlib
ROOT=Path(__file__).resolve().parent.parent

def validate(app):
    helpers=app/'Contents/Helpers/MobileDevice'
    for name in ['idevice_id','ideviceinfo','idevicediagnostics']:
        if not (helpers/name).is_file():raise ValueError('Missing helper: '+name)
    for binary in helpers.iterdir():
        architectures = set(subprocess.check_output(['lipo', str(binary), '-archs'], text=True).split())
        if not {'arm64', 'x86_64'} <= architectures: raise ValueError('Missing architecture: ' + str(binary))
        subprocess.run(['codesign','--verify','--strict',str(binary)],check=True,capture_output=True)
        for line in subprocess.check_output(['otool','-L',str(binary)],text=True).splitlines():
            if not line.startswith('\t'):continue
            dep=line.strip().split(' (')[0]
            if dep.startswith('@loader_path/'):
                if not (helpers/dep.removeprefix('@loader_path/')).is_file():raise ValueError('Missing library: '+dep)
            elif not dep.startswith(('/usr/lib/','/System/Library/')):raise ValueError('External dependency: '+dep)
        lines=subprocess.check_output(['otool','-l',str(binary)],text=True).splitlines()
        for line in lines:
            if line.strip().startswith('minos '):
                version=tuple(map(int,line.split()[1].split('.')))
                if version>(13,0,0):raise ValueError('Requires newer macOS: '+str(binary))
    if not (app/'Contents/Resources/MobileDevice-Licenses.txt').is_file():raise ValueError('Missing licenses')
    with tarfile.open(ROOT/'dist/BatteryScope-mobile-sources.tar') as archive:
        for item in json.loads((ROOT/'ThirdParty/mobile-lock.json').read_text()):
            file=archive.extractfile(item['url'].rsplit('/',1)[1])
            if file is None or hashlib.sha256(file.read()).hexdigest()!=item['sha256']:raise ValueError('Source checksum mismatch')
        if archive.extractfile('build-mobile.py').read()!=(ROOT/'scripts/build-mobile.py').read_bytes():raise ValueError('Source build script mismatch')
    print('Validated bundled mobile helpers: universal, macOS 13, relocatable, signed, corresponding sources')

if __name__=='__main__':validate(Path(sys.argv[1]))
