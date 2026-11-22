# Validation: Create, Rename, and Navigate Meetings

## Status

Implementation completed on 2026-11-22. The main debug bundle is built and opens successfully. Native creation, inline renaming, persistence, ordering, and the single Transcription workspace were exercised. The review limitations below are explicitly retained; they are not reported as passed runtime checks.

## Environment

Apple M4 Max, 36 GB RAM, macOS 27.2.1 (26B131), arm64. Swift 6 package with macOS 14 deployment target; Xcode selected through `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. The target declaration is not evidence of an actual macOS 14 runtime test.

The baseline and final existing XCTest suites both passed: 8 tests, 0 failures. Existing test fixtures were adapted for v2; the unsupported future version is now v3. Existing malformed-schema, invalid-record, rollback, Unicode, duplicate-name, reopen, and directory-error checks remain present.

Commands executed from the repository root:

```sh
bash scripts/build-app.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --disable-sandbox --cache-path .build/cache --manifest-cache local
```

The final bundle build and Info.plist validation passed. `git diff --check` passed. Ignore patterns already cover Swift output. No before_implement or after_implement hooks are configured. The requirements checklist passed 16/16 and was left unchanged.

## Storage verification

A temporary `.build/validate-meetings.swift` assertion runner was compiled with the actual Meeting.swift and MeetingStore.swift; it did not introduce a new XCTest suite. It passed the following checks:

- Valid legacy v1 rows migrate to v2, retaining UUIDs, names, creation times, row count, and stable equal-time ordering; updatedAt is backfilled from createdAt.
- New creation and reopening preserve identity and multilingual names. Repeating the same creation UUID returns the original record without overwriting or duplicating it.
- Renaming supports apostrophes and Unicode, trims surrounding whitespace, preserves createdAt, advances updatedAt, and reorders by identity. A normalized no-op returns the unchanged record.
- Blank/NUL input and missing identities are rejected. Invalid historical rows, malformed v1 schema, failed initialization, and unknown future v3 leave existing data intact; the latter checks are also covered by the existing XCTest suite.
- Stored timestamps later than current wall-clock time still permit new creations and real renames to move first. Persisted and in-memory comparators agree.
- A rejecting UPDATE trigger rolls back without changing the saved list. An external BEGIN IMMEDIATE lock rejects creation; retry after rollback creates exactly one record.
- One hundred additional creations and a reopen/load preserve the complete correctly ordered list. The storage-only 100-create batch took approximately 0.091 seconds; this is not UI latency.

Native fixtures were placed only in generated temporary meeting-record-ui-* and meeting-record-final-* directories through DEBUG MEETING_RECORD_DATA_DIR. No demonstration rows were inserted into the personal database. Some wrapper launches without DEBUG/override opened the normal empty store; no fixture or rename actions were performed there.

## Native acceptance review

| Area | Observed result |
| --- | --- |
| Create | Plus beside Meetings creates one saved named row, reveals/selects it, and opens its main content. Creation was exercised from Home, Settings, and an open Meeting. |
| Persistence | Relaunch with the same isolated directory retains saved names and order, with Home initially selected. |
| Mutation failure | Holding an external SQLite write transaction caused creation to show SQLite 5 without adding a phantom row or losing the active destination. Releasing the lock and retrying added one Meeting. |
| Rename entry | Actual double-click gestures opened inline fields from sidebar and main title. The field gained focus with its text selected. |
| Rename save | Enter saved a trimmed multilingual name (`Revisão d'água 日本語`); both displayed names agreed and the Meeting moved first. Leaving the main-title field via Home saved before navigation. |
| Invalid draft/cancel | Blank input displayed the required error and prevented navigation; Escape restored the saved display and abandoned the pending action. |
| Rename recovery | A temporary rejecting UPDATE trigger showed SQLite 19, retained the draft and old saved title/order, and exposed Try Again/Cancel. Correcting the name then saved, moved that UUID first, and restored focus. |
| Keyboard | Arrow navigation, native row activation, and Shift-Command-R opened rename. A focused-value native Meeting → Rename Meeting command replaced the unreliable raw key handler. Pointer/AX selection now sets row focus as well. |
| Recency | Loading, creation, changed rename, and reopening agree on updatedAt descending with UUID ties; viewing alone has no timestamp mutation path. Controlled future-time and no-op cases passed the store runner. |
| Transcription | Exactly one selected labeled workspace appears beneath the Meeting title, with visible text.alignleft icon and “No transcription yet.” No capture/import or future tabs appear. |
| Scale | With more than 100 stored Meetings, Add Meeting through the native tool plus observation of its selected first row took 588 ms, including tool/observation overhead. |
| Layout | The fixed navigation/heading, scrolling list, truncated long names with full-name help, title, tab icon/label, and empty state were visually inspected. |
| Appearance/minimum | Production views were also compiled into temporary native review wrappers under .build. A fresh wrapper identity with 720×480 content and forced dark appearance showed usable separate areas, readable text, visible focus, and the tab icon; light appearance was inspected separately. No wrapper or appearance override is shipped in the product. |
| Accessibility semantics | AX inspection exposed Add Meeting, Meeting name, selected destinations/tab, full row names, and Rename actions. The sidebar error remained visible and accessible after focus restoration. |
| Permissions | The exercised create/rename/navigation flows did not prompt for audio permissions, models, accounts, or downloads. |

## Corrections driven by native review

- The native TabView presentation hid the requested icon. The documented labeled-header fallback now renders icon and text explicitly, with selected accessibility state.
- Inline focus is requested after field presentation, and selection remains associated with UUID through sorting.
- Rename errors were being cleared by a redundant TextField binding write when focus returned. The binding now clears an error only when the draft actually changes; the final rejecting-trigger scenario confirmed visible error and successful recovery.

## Limits of the evidence

- Spoken VoiceOver output and a full VoiceOver-only navigation session were not exercised; accessibility evidence is from the native AX tree and keyboard interaction.
- An actual macOS 14 machine was not available for runtime verification.
- Network access was not disabled at the OS level. Local operation is supported by the exercised SQLite flows and absence of network/account/model dependencies, rather than a disconnected-machine run.
- The production bundle was left open on Home using its normal data location; isolated fixtures remain outside that location.
- No release signing, notarization, installation, or full recording/transcription functionality is included in this feature.
