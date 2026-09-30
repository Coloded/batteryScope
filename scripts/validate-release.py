#!/usr/bin/env python3
"""Verify release bytes, Ed25519 signature, universal bundle, and source manifest."""
import argparse
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
NS = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}

def require(condition, message):
    if not condition:
        raise ValueError(message)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def validate(appcast):
    info = plistlib.loads((ROOT / "Info.plist").read_bytes())
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    stable = ROOT / "dist/BatteryScope-stable.dmg"
    versioned = ROOT / f"dist/BatteryScope-{version}-universal.dmg"
    require(sha(stable) == sha(versioned), "Stable/versioned DMGs differ")
    items = ET.parse(appcast).getroot().findall("./channel/item")
    require(len(items) == 1, "Expected one release item")
    item = items[0]
    require(item.findtext("sparkle:version", namespaces=NS) == build, "Build differs")
    require(item.findtext("sparkle:shortVersionString", namespaces=NS) == version, "Version differs")
    require(item.findtext("sparkle:minimumSystemVersion", namespaces=NS) == info["LSMinimumSystemVersion"], "Minimum OS differs")
    enclosure = item.find("enclosure")
    require(enclosure is not None, "Missing enclosure")
    require(enclosure.get("url") == f"https://github.com/Coloded/batteryScope/releases/download/v{version}/BatteryScope-stable.dmg", "Unexpected download URL")
    require(int(enclosure.get("length", "-1")) == stable.stat().st_size, "Archive length differs")
    signature = enclosure.get(f'{{{NS["sparkle"]}}}edSignature', "")
    require(len(base64.b64decode(signature, validate=True)) == 64, "Invalid signature encoding")
    require(len(base64.b64decode(info["SUPublicEDKey"], validate=True)) == 32, "Invalid public key")
    with tempfile.TemporaryDirectory(prefix="batteryscope-validate-") as temporary:
        tmp = Path(temporary)
        verifier = tmp / "verify.swift"
        verifier.write_text('''import Foundation
import CryptoKit
let args = CommandLine.arguments
let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: args[1])!)
let signature = Data(base64Encoded: args[2])!
let payload = try Data(contentsOf: URL(fileURLWithPath: args[3]), options: .mappedIfSafe)
guard key.isValidSignature(signature, for: payload) else { fputs("Invalid Ed25519 signature\\n", stderr); exit(1) }
''')
        subprocess.run(["swiftc", "-module-cache-path", str(tmp / "modules"), str(verifier), "-o", str(tmp / "verify")], check=True)
        command = [str(tmp / "verify"), info["SUPublicEDKey"], signature]
        subprocess.run(command + [str(stable)], check=True)
        tampered = tmp / "tampered.dmg"
        contents = bytearray(stable.read_bytes()); contents[len(contents)//2] ^= 1
        tampered.write_bytes(contents)
        require(subprocess.run(command + [str(tampered)], capture_output=True).returncode != 0, "Tampered archive accepted")
        mount = tmp / "mount"; mount.mkdir()
        subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(stable)], check=True, stdout=subprocess.DEVNULL)
        try:
            app = mount / "BatteryScope.app"
            subprocess.run(["python3", str(ROOT / "scripts/check-private-data.py"), "--app", str(app)], check=True)
            subprocess.run(["python3", str(ROOT / "scripts/validate-mobile.py"), str(app)], check=True)
            embedded = plistlib.loads((app / "Contents/Info.plist").read_bytes())
            for key in ["CFBundleIdentifier", "CFBundleVersion", "CFBundleShortVersionString", "LSMinimumSystemVersion", "SUFeedURL", "SUPublicEDKey", "SUVerifyUpdateBeforeExtraction"]:
                require(embedded[key] == info[key], f"Bundle metadata differs: {key}")
            subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
            for binary in [app / "Contents/MacOS/BatteryScope", app / "Contents/Frameworks/Sparkle.framework/Versions/Current/Sparkle"]:
                require({"arm64", "x86_64"} <= set(subprocess.check_output(["lipo", str(binary), "-archs"], text=True).split()), "Missing architecture: " + str(binary))
            spec = importlib.util.spec_from_file_location("manifest", ROOT / "scripts/build-manifest.py")
            module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
            require(json.loads((app / "Contents/Resources/BuildManifest.json").read_text()) == module.inputs(), "Bundle was built from different source")
        finally:
            subprocess.run(["hdiutil", "detach", str(mount)], check=True, stdout=subprocess.DEVNULL)
    print(f"Validated BatteryScope {version} ({build}): source, universal binary, code signature, Ed25519, rejection of tampering")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--appcast", type=Path, default=ROOT / "updates/appcast.xml")
    validate(parser.parse_args().appcast)
