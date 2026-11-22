#!/bin/bash
set -euo pipefail
project_dir=$(cd "$(dirname "$0")/../.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/scripts" "$fixture/Resources" "$fixture/bin" "$fixture/output" "$fixture/.build"
cp "$project_dir/scripts/build-app.sh" "$fixture/scripts/"
cp "$project_dir/run" "$fixture/"
cp "$project_dir/Resources/Info.plist" "$fixture/Resources/"
printf '#!/bin/bash\nexit 0\n' > "$fixture/output/MeetingRecord"
chmod +x "$fixture/output/MeetingRecord"
export BUILD_SCRIPT_FIXTURE="$fixture"
cat > "$fixture/bin/xcrun" <<'STUB'
#!/bin/bash
set -eu
printf '%s\n' "$*" >> "$BUILD_SCRIPT_FIXTURE/calls"
if [[ " $* " == *' --show-bin-path '* ]]; then
  echo "$BUILD_SCRIPT_FIXTURE/output"
fi
STUB
cat > "$fixture/bin/open" <<'STUB'
#!/bin/bash
set -eu
[[ "$1" == .build/MeetingRecord.app ]]
[[ -x "$1/Contents/MacOS/MeetingRecord" ]]
printf 'opened\n' >> "$BUILD_SCRIPT_FIXTURE/calls"
STUB
chmod +x "$fixture/bin/xcrun" "$fixture/bin/open"
export PATH="$fixture/bin:$PATH"
/bin/bash "$fixture/run"
/bin/bash "$fixture/scripts/build-app.sh" --release
calls=$(cat "$fixture/calls")
[[ "$calls" == *opened* ]]
[[ "$calls" == *'-c debug -debug-info-format dwarf'* ]]
[[ "$calls" == *'-c release -debug-info-format none'* ]]
echo 'PASS: Bash debug/release build arguments and one-command launcher'
