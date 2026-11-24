# Tasks: Meetings Home

**Input**: Design documents in `specs/005-meetings-home/`  
**Prerequisites**: [Plan](plan.md), [spec](spec.md), [research](research.md), [data model](data-model.md), and [UI contract](contracts/ui-contract.md)

`[P]` marks work that can run alongside the indicated task once its prerequisites are met. Validate each story with the corresponding scenario in [quickstart.md](quickstart.md).

## Phase 1 — Setup

- [X] T001 Run the existing Swift package suite from `Package.swift` and confirm `run` launches the current app. Prepare disposable local Meetings for the checks in `specs/005-meetings-home/quickstart.md`.

## Phase 2 — Foundation

- [X] T002 Set up Home loading in `Sources/MeetingRecord/ContentView.swift` using the existing local store. Centralize refresh requests so overlapping reads cannot publish stale results. Keep launch and sidebar Home navigation available offline.

## Phase 3 — US1 Find Recent Meetings (P1, MVP)

**Independent check** — Open Home with zero through four Meetings. Verify the empty state or up to three current names ordered by creation, including empty Meetings. Rename or record in the oldest Meeting and verify the creation order still holds.

- [X] T003 [P] [US1] Add a recent-Meetings read in `Sources/MeetingRecord/MeetingStore.swift` using the ordering and uniqueness rules for `Meeting.creation time` and `Meeting.ID` in [data-model.md](data-model.md). Return the current `Meeting.current name` defined there.
- [X] T004 [P] [US1] Build the recent list in `Sources/MeetingRecord/HomeView.swift` with one keyboard-accessible entry per Meeting, loading and empty states, and a retry when data is unavailable. Expose selection through a Meeting ID callback.
- [X] T005 [US1] Replace the Home placeholder in `Sources/MeetingRecord/ContentView.swift` with the recent list. Connect the store, retry, selection callback, and refresh on launch, Home entry, and committed create or rename.

## Phase 4 — US2 Open a Meeting at Its Latest Recording (P2)

**Independent check** — Open a recent Meeting with a scrollable Inputs list and an in-progress recording. The latest saved card is visible and highlighted. Playback requires Play. Open an empty Meeting and verify the regular Inputs empty state.

- [X] T006 [P] [US2] Add an optional initial reveal to `Sources/MeetingRecord/InputsView.swift`. After loading, scroll to and highlight the saved card chosen under `Recording.ID`, `Recording.start time`, `Recording.finalization state`, and `Recording.saved clips` in [data-model.md](data-model.md). Handle an empty or active-only list and preserve explicit Play.
- [X] T007 [US2] Route Home selections to Inputs in `Sources/MeetingRecord/ContentView.swift`, including when that Meeting was last viewed on another tab. Scope the reveal to each Home selection so ordinary sidebar navigation retains its existing behavior.

## Phase 5 — US3 See Recording and Transcription Totals (P3)

**Independent check** — Use saved sessions totaling 90 minutes, including overlapping tracks and recordings outside the recent list. Verify one completed transcription becomes two while Home stays open. Verify finalization and recovery add playable time automatically.

- [X] T008 [P] [US3] Extend the Home read in `Sources/MeetingRecord/MeetingStore.swift` to return recent Meetings, saved Recording IDs and the completed job count from a consistent snapshot. Apply `Recording.Meeting ID`, `Recording.finalization state`, `Transcript job.Recording ID`, and `Transcript job.status` from [data-model.md](data-model.md).
- [X] T009 [P] [US3] Reuse the playback timeline rules in `Sources/MeetingRecord/RecordingPlayback.swift` to read saved duration from media metadata off the main actor. Apply `Audio segment.Recording ID`, `Audio segment.source`, `Audio segment.timeline offset`, and `Audio segment.media duration` from [data-model.md](data-model.md) for legacy and recovered recordings as well.
- [X] T010 [US3] Show both values below the list in `Sources/MeetingRecord/HomeView.swift`. Wire capture finalization and recovery in `Sources/MeetingRecord/RecordingCoordinator.swift` and committed transcription completion in `Sources/MeetingRecord/TranscriptionCoordinator.swift` to the refresh in `Sources/MeetingRecord/ContentView.swift`. Cache successful durations per saved recording for the app session, evict removed IDs, and show unavailable values with retry on read failure.

## Phase 6 — US4 Delete a Meeting from the Sidebar (P3)

**Independent check** — Cancel deletion of a disposable Meeting and verify its contents still open. Confirm deletion, then verify navigation, list and totals, and removal of all attached content after relaunch. Check that capture blocks deletion of its own Meeting.

- [X] T011 [US4] In `Sources/MeetingRecord/MeetingStore.swift`, add the migration and one delete transaction keyed by `Meeting.ID` and `Pending Meeting file deletion.Meeting ID` from [data-model.md](data-model.md). Check for an open Recording inside the transaction, delete the target's recording rows and Meeting, use the existing cascades, and persist the cleanup record in the same commit.
- [X] T012 [P] [US4] Skip stale transcription claims and late results in `Sources/MeetingRecord/MeetingStore.swift` and `Sources/MeetingRecord/TranscriptionCoordinator.swift`. Guard work against the existing `Transcript job.Recording ID` relationship in [data-model.md](data-model.md) inside the applicable transaction so the queue can continue with other Meetings.
- [X] T013 [P] [US4] Coordinate deletion against the target's capture state and block new capture for that target during submission in `Sources/MeetingRecord/RecordingCoordinator.swift`. In `Sources/MeetingRecord/RecordingStorage.swift`, remove only the managed directory for the pending Meeting UUID after commit, then clear the cleanup record via the store. Resume pending cleanup at startup and support retry after failure.
- [X] T014 [US4] Add **Delete Meeting…** to the row menu in `Sources/MeetingRecord/SidebarView.swift`. In `Sources/MeetingRecord/ContentView.swift`, confirm with the Meeting name and the permanent effect, recheck eligibility, and preserve selection on cancel or database failure. After commit, refresh the sidebar and Home, switch to Home if the selected Meeting was removed, and expose pending file cleanup and retry if needed.

## Phase 7 — Validation

- [ ] T015 Run the full suite from `Package.swift` and the scenarios in `specs/005-meetings-home/quickstart.md` using disposable data. Use the existing temporary-library fixtures in `Tests/MeetingRecordTests/MeetingStoreTests.swift` and `Tests/MeetingRecordTests/RecordingStorageTests.swift` to verify rollback, interrupted cleanup and late transcription. Record the Mac, outcomes and any gaps in `specs/005-meetings-home/quickstart.md`.

## Dependencies & Execution Order

- T001 → T002 → US1. T003 and T004 can run together. T005 joins both.
- US2 needs US1 for end-to-end validation. T006 can start alongside the US1 work. T007 joins T005 and T006.
- US3 builds on the Home shell from US1 and does not require US2 behavior. T008 and T009 can run together after US1. T010 integrates them. Integrate after T007 to avoid concurrent edits to ContentView.
- US4 storage starts after T008 frees the store file. After T011, T012 and T013 can run together once T010 has landed, using the cleanup store operations from T011. T014 joins the deletion work and the finished Home refresh so both totals can be checked.
- T015 follows all four stories.

## Parallel Examples

| Story | Independent work |
| --- | --- |
| US1 | T003 recent query and T004 list view after T002 |
| US2 | T006 Inputs reveal alongside T003 or T004 |
| US3 | T008 snapshot query and T009 playback timing |
| US4 | T012 stale transcription handling and T013 directory cleanup after T010 and T011 |

## Implementation Strategy

Validate US1 as the MVP on its own. Then add the one-click Inputs reveal, automatic totals, and confirmed deletion. Use the final native checks to verify that deleting a Meeting changes both totals and removes the files across relaunch.
