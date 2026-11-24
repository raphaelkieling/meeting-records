# Meeting Record

Local macOS app built with SwiftUI and SQLite. Requires Apple Silicon, macOS 14+, and Xcode with Swift 6.

Build and open the app:

```sh
./run
```

To change the app icon, replace [Resources/AppIcon.png](Resources/AppIcon.png) with a square PNG (at least 1024 × 1024 pixels) and run `./run` again. The build generates the macOS icon, and Settings uses the icon from the app bundle.

Run `./scripts/build-dmg.sh` from a logged-in macOS desktop session to build `.build/MeetingRecord.dmg`. Open the disk image and drag **Meeting Record** into **Applications**. The disk image uses the local build signature. Its Finder background is in [Resources/DMGBackground.png](Resources/DMGBackground.png).

Home and Settings stay above the scrollable Meetings list. Use arrow keys to move focus and Return or Space to select.

Meetings are stored in `~/Library/Application Support/MeetingRecord/meetings.sqlite`. The app currently supports navigation and reading existing meetings.

[Manual testing guide](specs/001-app-shell/quickstart.md)
