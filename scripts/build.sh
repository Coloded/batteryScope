#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir="${TMPDIR:-/tmp}/batteryscope-build"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/batteryscope-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/batteryscope-swift-cache"
sparkle_root="$(zsh scripts/fetch-sparkle.sh)"
for arch in arm64 x86_64; do
  swift build --disable-sandbox -c release --arch "$arch" --scratch-path "$build_dir/$arch" \
    -Xswiftc -F -Xswiftc "$sparkle_root" \
    -Xlinker "-F$sparkle_root" -Xlinker -framework -Xlinker Sparkle \
    -Xlinker -rpath -Xlinker '@executable_path/../Frameworks'
done
app="$build_dir/BatteryScope.app"
# Stage on a macOS filesystem: framework symlinks must survive packaging.
if [ -d "$app" ]; then mv "$app" "$build_dir/previous-app-$(date +%s)-$$"; fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
lipo -create "$build_dir/arm64/arm64-apple-macosx/release/BatteryScope" "$build_dir/x86_64/x86_64-apple-macosx/release/BatteryScope" -output "$app/Contents/MacOS/BatteryScope"
cp Info.plist "$app/Contents/Info.plist"
if [ ! -f Assets/AppIcon.icns ] || [ Assets/AppIcon.png -nt Assets/AppIcon.icns ]; then bash scripts/icon.sh; fi
cp Assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
COPYFILE_DISABLE=1 ditto --norsrc --noextattr "$sparkle_root/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp "$sparkle_root/LICENSE" "$app/Contents/Resources/Sparkle-LICENSE.txt"
python3 scripts/build-manifest.py "$app/Contents/Resources/BuildManifest.json"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
lipo "$app/Contents/MacOS/BatteryScope" -verify_arch arm64 x86_64
echo "Собрано: $app"
