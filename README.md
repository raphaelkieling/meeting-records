# Meeting Record

Local macOS app built with SwiftUI and SQLite. Requires Apple Silicon, macOS 14+, and Xcode with Swift 6.

Build and open the app:

```sh
./run
```

Home and Settings stay above the scrollable Meetings list. Use arrow keys to move focus and Return or Space to select.

Meetings are stored in `~/Library/Application Support/MeetingRecord/meetings.sqlite`. The app currently supports navigation and reading existing meetings.

[Manual testing guide](specs/001-app-shell/quickstart.md)
