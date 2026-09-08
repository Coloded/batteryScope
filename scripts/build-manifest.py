#!/usr/bin/env python3
"""Record hashes of inputs; release validator detects stale prebuilt artifacts."""
import hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent

def inputs():
    paths=[ROOT/'Info.plist',ROOT/'Package.swift',ROOT/'Assets/AppIcon.icns']
    paths+=sorted((ROOT/'Sources').rglob('*.swift'))
    paths+=sorted(p for p in (ROOT/'scripts').iterdir() if p.suffix in ('.sh','.py') and not p.name.startswith('._'))
    return {str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths if not p.name.startswith('._')}
if __name__=='__main__':
    Path(sys.argv[1]).write_text(json.dumps(inputs(),sort_keys=True,indent=2)+'\n')
