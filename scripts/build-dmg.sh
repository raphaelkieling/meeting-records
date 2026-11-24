#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

mode="${1:-}"
[[ $# -le 1 && ( -z "$mode" || "$mode" == "--ci" ) ]] || { echo 'Usage: scripts/build-dmg.sh [--ci]' >&2; exit 2; }

scripts/build-app.sh --release

work_dir=$(mktemp -d "$PWD/.build/dmg.XXXXXX")
mount_dir="$work_dir/volume"
mounted=false
cleanup() {
  if "$mounted"; then
    hdiutil detach "$mount_dir" -force -quiet || return
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT

mkdir -p "$work_dir/staging/.background" "$mount_dir"
ditto .build/MeetingRecord.app "$work_dir/staging/Meeting Record.app"
ln -s /Applications "$work_dir/staging/Applications"
cp Resources/DMGBackground.png "$work_dir/staging/.background/install.png"

if [[ "$mode" == "--ci" ]]; then
  hdiutil create -quiet -fs HFS+ -format UDZO -volname "Meeting Record" \
    -srcfolder "$work_dir/staging" "$work_dir/MeetingRecord.dmg"
  mv -f "$work_dir/MeetingRecord.dmg" .build/MeetingRecord.dmg
  echo "Built .build/MeetingRecord.dmg (CI layout)"
  exit 0
fi

hdiutil create -quiet -fs HFS+ -format UDRW -volname "Meeting Record" \
  -srcfolder "$work_dir/staging" "$work_dir/layout.dmg"
hdiutil attach -quiet -nobrowse -mountpoint "$mount_dir" "$work_dir/layout.dmg"
mounted=true

osascript - "$mount_dir" <<'APPLESCRIPT'
on run argv
  set mountPath to item 1 of argv
  set volumeRoot to POSIX file mountPath as alias
  set backgroundFile to POSIX file (mountPath & "/.background/install.png") as alias
  tell application id "com.apple.finder"
    open volumeRoot
    set volumeWindow to front Finder window
    if (target of volumeWindow as alias) is not volumeRoot then error "Finder did not open the disk image."
    tell volumeWindow
      set current view to icon view
      set toolbar visible to false
      set statusbar visible to false
      set pathbar visible to false
      set bounds to {200, 160, 800, 535}
      set viewOptions to its icon view options
      set arrangement of viewOptions to not arranged
      set icon size of viewOptions to 104
      set text size of viewOptions to 13
      set background picture of viewOptions to backgroundFile
    end tell
    set volumeFolder to target of volumeWindow
    set position of item "Meeting Record.app" of volumeFolder to {175, 174}
    set position of item "Applications" of volumeFolder to {425, 174}
    close volumeWindow
    update volumeFolder
  end tell
end run
APPLESCRIPT

# Finder writes the window layout asynchronously.
for attempt in {1..10}; do
  [[ -s "$mount_dir/.DS_Store" ]] && break
  sleep 1
done
[[ -s "$mount_dir/.DS_Store" ]] || { echo "Finder did not save the disk image layout." >&2; exit 1; }

hdiutil detach -quiet "$mount_dir"
mounted=false
hdiutil convert -quiet -format UDZO "$work_dir/layout.dmg" -o "$work_dir/MeetingRecord.dmg"
mv -f "$work_dir/MeetingRecord.dmg" .build/MeetingRecord.dmg
echo "Built .build/MeetingRecord.dmg"
