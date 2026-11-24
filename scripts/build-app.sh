#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
configuration=debug
if [[ $# -gt 0 ]]; then
  [[ $# -eq 1 && "$1" == --release ]] || { echo 'Usage: scripts/build-app.sh [--release]' >&2; exit 2; }
  configuration=release
fi
debug_info=dwarf
if [[ "$configuration" == release ]]; then
  debug_info=none
fi
bundle=.build/MeetingRecord.app
# Remove stale output before building so a failure cannot look like a fresh app.
rm -rf "$bundle"
xcrun swift build --disable-sandbox --cache-path .build/cache --manifest-cache local -c "$configuration" -debug-info-format "$debug_info"
bin_path=$(xcrun swift build --disable-sandbox --cache-path .build/cache --manifest-cache local -c "$configuration" -debug-info-format "$debug_info" --show-bin-path)
staging=$(mktemp -d .build/MeetingRecord-bundle.XXXXXX)
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/Contents/MacOS"
cp Resources/Info.plist "$staging/Contents/Info.plist"
cp "$bin_path/MeetingRecord" "$staging/Contents/MacOS/MeetingRecord"
mkdir -p "$staging/Contents/Frameworks"
cp -R "$bin_path/CTranscribe.framework" "$staging/Contents/Frameworks/"
install_name_tool -add_rpath @executable_path/../Frameworks "$staging/Contents/MacOS/MeetingRecord"
codesign --force --sign - "$staging/Contents/Frameworks/CTranscribe.framework"
mkdir -p "$staging/Contents/Resources"
iconset="$staging/AppIcon.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -z "$retina_size" "$retina_size" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$staging/Contents/Resources/AppIcon.icns"
rm -r "$iconset"
mkdir -p "$staging/Contents/Resources/CTranscribe-Licenses"
cp .build/artifacts/*/CTranscribe/TranscribeCpp.xcframework/LICENSE* \
  "$staging/Contents/Resources/CTranscribe-Licenses/"
for resources in "$bin_path"/*.bundle; do
  [[ -d "$resources" ]] || continue
  cp -R "$resources" "$staging/Contents/Resources/"
done
plutil -lint "$staging/Contents/Info.plist"
codesign --force --sign - --entitlements Resources/Recording.entitlements "$staging"
mv "$staging" "$bundle"
echo "Built $bundle ($configuration)"
