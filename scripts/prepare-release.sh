#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" != --skip-build ]; then bash scripts/build.sh; fi
app="${TMPDIR:-/tmp}/batteryscope-build/BatteryScope.app"
python3 scripts/check-private-data.py --app "$app"
version="$(plutil -extract CFBundleShortVersionString raw Info.plist)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/batteryscope-release.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/image" "$stage/archives" dist updates
COPYFILE_DISABLE=1 ditto --norsrc --noextattr "$app" "$stage/image/BatteryScope.app"
ln -s /Applications "$stage/image/Applications"
hdiutil create -volname BatteryScope -srcfolder "$stage/image" -format UDZO -ov "$stage/BatteryScope-stable.dmg"
cp "$stage/BatteryScope-stable.dmg" "$stage/archives/BatteryScope-stable.dmg"
cp updates/release-notes.md "$stage/archives/BatteryScope-stable.md"
signing_tool="$(bash scripts/prepare-signing-tool.sh)"
"$signing_tool" --account BatteryScope \
  --download-url-prefix "https://github.com/Coloded/batteryScope/releases/download/v${version}/" \
  --link https://github.com/Coloded/batteryScope --embed-release-notes \
  --maximum-versions 1 --maximum-deltas 0 -o "$stage/appcast.xml" "$stage/archives"
cp "$stage/BatteryScope-stable.dmg" "dist/BatteryScope-${version}-universal.dmg"
cp "$stage/BatteryScope-stable.dmg" dist/BatteryScope-stable.dmg
cp "$stage/appcast.xml" updates/appcast.xml
python3 scripts/validate-release.py
