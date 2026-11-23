---
description: "Implementation tasks for local Meeting recording"
---

# Tasks — Meeting Recording

**Input** — [Plan](plan.md), [spec](spec.md), [research](research.md), [data model](data-model.md), and [UI contract](contracts/ui-contract.md)

Tasks marked `[P]` can run in parallel after their stated prerequisites. Repository paths below are relative to the root.

## Phase 1 — Setup

- [ ] T001 Configure the microphone usage description in `Resources/Info.plist` and verify microphone entitlement, signing, and permission prompts through the existing launcher in `scripts/build-app.sh` and `run`.
- [ ] T002 Prove ScreenCaptureKit audio-only output and AVFoundation microphone input can run simultaneously on the target Mac. Check permission and restart behavior, silence, source isolation, and conversion to a shared clock. Record findings and the OS version in `specs/003-meeting-record-button/research.md`.

## Phase 2 — Foundation

- [X] T003 Define persisted models in `Sources/MeetingRecord/Recording.swift` using the canonical fields in [data-model.md](data-model.md). Implement `Recording.id`, `Recording.meetingID`, `Recording.startedAt`, `Recording.endedAt`, `Recording.state`, `AudioSegment.recordingID`, `AudioSegment.source`, `AudioSegment.startOffset`, `AudioSegment.frameCount`, and `AudioSegment.relativePath` as defined there.
- [X] T004 [P] Add a non-destructive SQLite migration and transactional Recording and segment reads and writes in `Sources/MeetingRecord/MeetingStore.swift`. Link `Recording.meetingID` to `Meeting.id`, derive `Meeting.source` from its first usable Input, and apply the state, source, ordering, and empty-input rules from [data-model.md](data-model.md). Keep the existing database and debug data-root override.
- [X] T005 [P] Implement the proven dual-source capture, clock conversion, and throttled level reporting in `Sources/MeetingRecord/RecordingCapture.swift`. Use bounded buffering off the UI thread. Report permission denial, device or stream failure, and shutdown to the caller.
- [X] T006 Write independent PCM CAF checkpoints and reconcile published files with SQLite on launch in `Sources/MeetingRecord/RecordingStorage.swift`. Use `AudioSegment.source`, `AudioSegment.startOffset`, `AudioSegment.frameCount`, and `AudioSegment.relativePath` from [data-model.md](data-model.md). Drain and publish the final partial clips on normal stop, preserve usable clips as Interrupted after failure, and keep repeated reconciliation free of duplicates.

## Phase 3 — User Story 1 · Start and stop recording (P1)

**Independent check** — Start capture from a fresh Meeting, switch tabs and visit another Meeting, return through the sidebar, and stop. Verify both local tracks and a second distinct Recording on disk.

- [X] T007 [P] [US1] Implement the option E control in `Sources/MeetingRecord/RecordingControl.swift` using the [UI contract](contracts/ui-contract.md). Include icon-only Record and Stop, live white waves, keyboard focus, accessible names, and Reduce Motion behavior. Accept state and actions from the caller.
- [X] T008 [P] [US1] Implement the app-scoped recording lifecycle in `Sources/MeetingRecord/RecordingCoordinator.swift`. Connect capture and storage, allow one active session through finalization, handle duplicate requests and failures, and exit a failed start without a visible Input. Follow `Recording.state` and `Recording.endedAt` from [data-model.md](data-model.md).
- [X] T009 [US1] Connect the control and coordinator in `Sources/MeetingRecord/MeetingRecordApp.swift` and `Sources/MeetingRecord/ContentView.swift`. Keep the control fixed across tab switches and scrolling, disable Record in other Meetings, and expose the active Meeting via the far-right red indicator in `Sources/MeetingRecord/SidebarView.swift`. Selecting its row returns to the Stop control.

## Phase 4 — User Story 2 · Find source material (P2)

**Independent check** — Open a Meeting with two saved Recordings and a fresh Meeting. Verify ordering, the empty state, and Inputs first beside Transcription. This can be checked with seeded saved metadata or by recording twice.

- [X] T010 [P] [US2] Build the Inputs list and empty state in `Sources/MeetingRecord/InputsView.swift` using Recording metadata from T004, including the Interrupted state and ordering by `Recording.startedAt` and `Recording.id` from [data-model.md](data-model.md).
- [X] T011 [US2] Wire the Inputs and Transcription tabs in `Sources/MeetingRecord/ContentView.swift`. Default to Inputs, load its Meeting's saved Recordings after reconciliation, refresh after finalization, and show the Transcription empty state.

## Phase 5 — Cross-cutting validation

- [ ] T012 Run the existing Swift test suite and the native scenarios in `specs/003-meeting-record-button/quickstart.md`. Record results in `specs/003-meeting-record-button/validation.md`, including alignment and drift, force-quit recovery, write failure, offline capture, and accessibility. Record any checks blocked by the available Mac or permissions.

## Phase 6 — User Story 2 · Play a saved Recording (P2)

**Independent check** — Seed two saved Recordings, including overlapping Me and Other clips and gaps in the timeline. Play the first card, switch to the second, and verify that the first stops. Check manual Stop, natural completion, and leaving Inputs.

- [X] T013 [US2] Read the selected Recording's saved segment index in `Sources/MeetingRecord/MeetingStore.swift`. Return both sources in timeline order using `AudioSegment.recordingID`, `AudioSegment.source`, `AudioSegment.startOffset`, `AudioSegment.frameCount`, and `AudioSegment.relativePath` from [data-model.md](data-model.md). Resolve file paths through the existing recordings root.
- [X] T014 [US2] Implement local playback in `Sources/MeetingRecord/RecordingPlayback.swift`. Mix Me and Other on the shared timeline, preserve gaps and overlaps, and stream the existing CAF clips without creating a new file. Play the available track if an interrupted Recording has just one. Keep at most one active Recording, return to idle on Stop or completion, and surface playback errors without changing saved inputs.
- [X] T015 [US2] Render compact cards in `Sources/MeetingRecord/InputsView.swift`, with the name at left, Play or Stop at top right, and the recording date at bottom right. Keep the Interrupted label where applicable. Provide accessible button names and stop playback when leaving Inputs or changing Meetings.

## Phase 7 — Playback validation

- [ ] T016 Verify playback with saved fixtures, including two audible sources with known offsets and a one-track Interrupted Recording. Check that switching cards, Stop, completion, leaving Inputs, and unreadable audio all update the control correctly. Confirm that playback leaves stored files untouched and record results in `specs/003-meeting-record-button/validation.md`.

## Dependencies & Execution Order

`T001 → T002 → T003 → (T004 ∥ T005) → T006`. Once the foundation is ready, T007 (US1 control), T008 (US1 lifecycle), and T010 (US2 list) can proceed in parallel. T009 follows T007 and T008. T011 follows T009 and T010 because both integrations edit `ContentView.swift`. T012 follows both stories.

Playback follows `T013 → T014 → T015 → T016` and uses the completed storage and Inputs work. Seeded saved recordings allow playback implementation and verification while the live-capture checks in T001, T002, and T012 remain pending.

## Implementation Strategy

Validate the US1 capture and navigation flow against the saved files. Complete US2 with the Inputs list and playback cards, then verify both workflows.
