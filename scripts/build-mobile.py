#!/usr/bin/env python3
"""Build pinned mobile utilities for macOS 13, relocate and embed both architectures."""
import hashlib,json,os,shutil,subprocess,sys,tarfile,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
CACHE=Path(os.environ.get('BATTERYSCOPE_MOBILE_CACHE','/tmp/batteryscope-mobile'))
SOURCES=Path(os.environ.get('BATTERYSCOPE_MOBILE_SOURCES','/tmp/batteryscope-mobile-sources'))
LOCK=json.loads((ROOT/'ThirdParty/mobile-lock.json').read_text())
TOOLS=['idevice_id','ideviceinfo','idevicediagnostics']

def run(args,cwd,env,log):
    with log.open('ab') as f:
        result=subprocess.run([str(x) for x in args],cwd=cwd,env=env,stdout=f,stderr=subprocess.STDOUT)
    if result.returncode:
        print(log.read_text(errors='replace')[-9000:],file=sys.stderr)
        raise RuntimeError('Failed: '+' '.join(map(str,args)))

def build():
    SOURCES.mkdir(parents=True,exist_ok=True);CACHE.mkdir(parents=True,exist_ok=True)
    for item in LOCK:
        archive=SOURCES/item['url'].rsplit('/',1)[1]
        if not archive.exists(): urllib.request.urlretrieve(item['url'],archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest()!=item['sha256']: raise ValueError('Checksum: '+item['name'])
    # Full corresponding upstream sources travel with every binary release.
    with tarfile.open(ROOT/'dist/BatteryScope-mobile-sources.tar','w') as package:
        for item in LOCK: package.add(SOURCES/item['url'].rsplit('/',1)[1],arcname=item['url'].rsplit('/',1)[1])
        package.add(ROOT/'ThirdParty/mobile-lock.json',arcname='mobile-lock.json')
        package.add(Path(__file__),arcname='build-mobile.py')
    sdk=subprocess.check_output(['xcrun','--show-sdk-path'],text=True).strip()
    fingerprint=hashlib.sha256(Path(__file__).read_bytes()+(ROOT/'ThirdParty/mobile-lock.json').read_bytes()).hexdigest()
    for arch in ['arm64','x86_64']:
        base=CACHE/arch;prefix=base/'prefix';base.mkdir(exist_ok=True)
        stamp=base/'complete'
        if stamp.exists() and stamp.read_text()==fingerprint: continue
        env=dict(os.environ,PATH='/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin',
                 CC='/usr/bin/clang',CXX='/usr/bin/clang++',MACOSX_DEPLOYMENT_TARGET='13.0',
                 CFLAGS=f'-O2 -arch {arch} -mmacosx-version-min=13.0 -isysroot {sdk}',
                 CXXFLAGS=f'-O2 -arch {arch} -mmacosx-version-min=13.0 -isysroot {sdk}',
                 LDFLAGS=f'-arch {arch} -mmacosx-version-min=13.0 -Wl,-headerpad_max_install_names',
                 PKG_CONFIG_PATH=str(prefix/'lib/pkgconfig'),PKG_CONFIG_LIBDIR=str(prefix/'lib/pkgconfig'),
                 libcurl_CFLAGS=f'-isysroot {sdk}',libcurl_LIBS='-lcurl')
        for item in LOCK:
            print('Building',arch,item['name'],flush=True)
            work=base/item['directory']
            if work.exists(): shutil.rmtree(work)
            with tarfile.open(SOURCES/item['url'].rsplit('/',1)[1]) as t:t.extractall(base,filter='data')
            log=base/(item['name'].replace('@','-')+'.log')
            if item['name'].startswith('openssl'):
                target='darwin64-arm64-cc' if arch=='arm64' else 'darwin64-x86_64-cc'
                run(['perl','Configure',target,'shared','no-tests','no-apps','no-module',f'--prefix={prefix}',f'--openssldir={prefix}/ssl'],work,env,log)
                run(['make','-j8','build_sw'],work,env,log);run(['make','install_sw'],work,env,log)
            else:
                options=['./configure',f'--prefix={prefix}',f'--host={arch}-apple-darwin','--build=arm64-apple-darwin','--disable-static','--enable-shared']
                if item['name'] in ['libplist','libimobiledevice']:options+=['--without-cython']
                if item['name']=='libplist': options+=['--without-tests']
                if item['name']=='libimobiledevice': options+=['--without-readline']
                run(options,work,env,log);run(['make','-j8'],work,env,log);run(['make','install'],work,env,log)
        stamp.write_text(fingerprint)

def dependencies(path):
    return [line.strip().split(' (')[0] for line in subprocess.check_output(['otool','-L',str(path)],text=True).splitlines()[1:]]

def embed(app):
    destination=app/'Contents/Helpers/MobileDevice'
    if destination.exists(): shutil.rmtree(destination)
    destination.mkdir(parents=True)
    libs=set()
    prefix=CACHE/'arm64/prefix'
    queue=[prefix/'bin'/name for name in TOOLS]
    while queue:
        p=queue.pop()
        for dep in dependencies(p):
            if dep.startswith(str(prefix)) and Path(dep).name not in libs:
                libs.add(Path(dep).name);queue.append(Path(dep))
            elif not dep.startswith((str(prefix),'/usr/lib/','/System/Library/')):raise ValueError('Nonportable dependency: '+dep)
    names=TOOLS+sorted(libs)
    for name in names:
        sub='bin' if name in TOOLS else 'lib'
        output=destination/name
        subprocess.run(['lipo','-create',str(CACHE/'arm64/prefix'/sub/name),str(CACHE/'x86_64/prefix'/sub/name),'-output',str(output)],check=True)
        for arch in ['arm64','x86_64']:
            for dep in dependencies(CACHE/arch/'prefix'/sub/name):
                if dep.startswith(str(CACHE/arch/'prefix')):
                    subprocess.run(['install_name_tool','-change',dep,'@loader_path/'+Path(dep).name,str(output)],check=True,capture_output=True)
        if name in libs:subprocess.run(['install_name_tool','-id','@loader_path/'+name,str(output)],check=True,capture_output=True)
        subprocess.run(['codesign','--force','--sign','-',str(output)],check=True,capture_output=True)
    licenses=app/'Contents/Resources/MobileDevice-Licenses.txt'
    text=['BatteryScope mobile helpers: unmodified upstream source releases.\nSource archives and build script: https://github.com/Coloded/batteryScope/releases/download/v0.7.1/BatteryScope-mobile-sources.tar\nDynamic libraries are separately replaceable. No hardened library validation is enabled.\n']
    for item in LOCK:
        source=CACHE/'arm64'/item['directory']
        text.append('\n=== '+item['name']+' '+item['version']+' ===\n'+item['url']+'\n')
        for name in ['COPYING','COPYING.LESSER','LICENSE','LICENSE.txt']:
            if (source/name).exists():text.append((source/name).read_text(errors='replace'))
    licenses.write_text('\n'.join(text))
    print('Embedded universal mobile helpers:',len(names),'Mach-O files',flush=True)

if __name__=='__main__':
    build()
    if len(sys.argv)>1:embed(Path(sys.argv[1]))
