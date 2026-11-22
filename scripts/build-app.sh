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
plutil -lint "$staging/Contents/Info.plist"
mv "$staging" "$bundle"
echo "Built $bundle ($configuration)"
