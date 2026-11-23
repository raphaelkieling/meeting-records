# Quickstart: Create, Rename, and Navigate Meetings

Implementation is available. Actual commands, observed results, and limitations are recorded in [validation.md](validation.md); the scenarios below can be repeated against isolated data.

## Prerequisites and build

Use an Apple Silicon Mac, macOS 14+, Swift 6, the macOS SDK, and SQLite CLI. From the repository root, use the same Xcode environment as the existing build guide:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
xcrun swift test --disable-sandbox --cache-path .build/cache --manifest-cache local
bash scripts/build-app.sh
meeting_record_validation_dir=$(mktemp -d /tmp/meeting-record-validation.XXXXXX)
MEETING_RECORD_DATA_DIR="$meeting_record_validation_dir" .build/MeetingRecord.app/Contents/MacOS/MeetingRecord
```

Use only this temporary database for fixtures and failure injection. Close and quit the running app before relaunching. Never seed or alter the personal Application Support database.

## Create and restart

1. Confirm Home is selected, Meetings is empty, and the plus is visible beside the heading.
2. Activate Add Meeting once. Verify one random English name, one selected first row, matching main title, and one selected Transcription tab with icon and "No transcription yet."
3. Create additional Meetings from Home, Settings, and another Meeting. Each deliberate activation adds exactly one saved UUID and opens it. Pending creation prevents overlapping requests.
4. Restart with the same isolated directory. Verify identities, names, and order persist and Home is initially selected. Repeat offline with no audio permissions; no requests or downloads occur.

## Rename and recency

1. Right-click the oldest sidebar row, choose Rename, enter a Unicode name containing an apostrophe, and press Enter. Both visible names update, that UUID moves first, and selection stays with it.
2. Rename from the main title; click outside to save. Verify the same result and persistence after restart.
3. Cancel an edit with Escape; commit an unchanged trimmed name; attempt a whitespace-only name. Verify no timestamp/order changes, and the invalid draft remains with a clear error.
4. While editing, navigate to Home, create a Meeting, or begin another rename. Valid changes save before continuing exactly once; invalid or failed saves retain editor/destination. Cancel abandons the pending action.
5. Verify single-click selection does not open editing. Merely selecting or reading Meetings never changes order. During edits, arrow keys move the text cursor rather than navigating rows.
6. Use Rename from each context menu and Shift-Command-R with keyboard focus. Verify visible focus, VoiceOver labels/errors, and focus preservation after reorder.

## Legacy migration

Before running the new app, create a separate legacy fixture:

```sh
meeting_record_legacy_dir=$(mktemp -d /tmp/meeting-record-legacy.XXXXXX)
sqlite3 "$meeting_record_legacy_dir/meetings.sqlite" <<'SQL'
CREATE TABLE meetings(id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL CHECK(length(trim(name)) > 0), createdAt REAL NOT NULL);
INSERT INTO meetings VALUES ('00000000-0000-0000-0000-000000000001', 'Legacy one', 100);
INSERT INTO meetings VALUES ('00000000-0000-0000-0000-000000000002', 'Legacy two', 100);
PRAGMA user_version=1;
SQL
MEETING_RECORD_DATA_DIR="$meeting_record_legacy_dir" .build/MeetingRecord.app/Contents/MacOS/MeetingRecord
```

Expected: both names/UUIDs/creation times survive, updatedAt equals historical createdAt, version becomes 2, and ties resolve by UUID ascending. Rename Legacy two and restart: it remains first. Existing store tests must additionally cover migration rollback on invalid data/schema, repeated migration/load, and unknown future version 3 without modification.

## Persistence tests and failures

The existing XCTest suite covers schema/read safety and compatible v2 fixtures. For mutation and migration cases, the implementation review used a temporary assertion runner against the actual model/store, without adding a new test suite; see validation.md. Reproduce user-facing cases below and the migration fixture above with isolated data. For backward-clock behavior, seed a finite updatedAt later than current wall-clock time, then create or rename through the app rather than changing the system clock.

With the isolated app running, a second terminal can hold a write lock:

```sh
sqlite3 "$meeting_record_validation_dir/meetings.sqlite"
```

At its SQLite prompt, run `BEGIN IMMEDIATE;`. Attempt create/rename in the app: failure must preserve saved list, order, selection, and rename draft. Run `ROLLBACK;` at that prompt, then retry. Exactly one logical creation or rename succeeds. Also verify invalid/open-failure recovery through the existing debug-directory setup. Do not introduce a hidden UI fault-injection mode.

## Scale and visual review

Create or seed 100 Meetings in the isolated v2 database using named columns id, name, createdAt, updatedAt. Include long names and equal times. Measure Add Meeting to selected visible first row: target at most one second. Check scrolling, fixed headings, truncation/full-name discovery, title editing, tab text/icon, and empty state at 720×480 and normal size in both appearances. Do not claim tab icon visibility solely from source code.

Record environment, commands, actual test results, timing, native screenshots, and keyboard/VoiceOver observations in validation.md during implementation. Distinguish macOS deployment target from OS versions actually tested. See [UI contract](contracts/ui-contract.md) and [data model](data-model.md) for expected behavior.

## Repeatable rename-failure fixture

With the app closed, install this trigger only in the isolated v2 validation database:

```sh
sqlite3 "$meeting_record_validation_dir/meetings.sqlite" "CREATE TRIGGER reject_validation_name BEFORE UPDATE ON meetings WHEN NEW.name='Blocked rename' BEGIN SELECT RAISE(ABORT, 'validation write failure'); END;"
```

Reopen with the isolated directory, rename an existing Meeting to `Blocked rename`, and press Enter. Expected: visible error, retained draft, and unchanged saved title/order. Change the draft to another name and save: expected success and selected first row. This fixture affects only the rejected name and requires no hidden UI mode.
