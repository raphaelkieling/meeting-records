# Tasks: Microphone Transcription Sensitivity

**Input**: Design documents from `specs/006-transcription-sensitivity/`  
**Prerequisites**: [Plan](plan.md), [spec](spec.md), [research](research.md), [data model](data-model.md), [contract](contracts/settings-contract.md)

Tests are included because the user requested implementation and sensitivity filtering can silently lose speech.

## Phase 1: Setup

- [X] T001 Run the existing suite with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test` and review the audio fixtures in `Tests/MeetingRecordTests/RecordingStorageTests.swift` and `Tests/MeetingRecordTests/RecordingPlaybackTests.swift`.

## Phase 2: Foundational

- [X] T002 Define a bounded, locally persisted microphone threshold with a legacy-compatible default in `Sources/MeetingRecord/TranscriptionCoordinator.swift`. Keep the setting value, live microphone level and per-window filter input on one normalized scale, as specified in `specs/006-transcription-sensitivity/data-model.md`.

## Phase 3: User Story 1 — Set Microphone Sensitivity (P1, MVP)

**Goal**: Tune which Me audio is transcribed without changing or deleting the saved recording.

**Independent Test**: Adjust the threshold in Settings while speaking and pausing. Confirm the live meter and threshold marker. Record speech above and below threshold. Verify only qualifying mic intervals produce text while the entire saved recording remains playable. Confirm Other is unchanged.

- [X] T003 [P] [US1] Add deterministic normalized RMS calculation over captured microphone samples in `Sources/MeetingRecord/RecordingStorage.swift`. Cite `Input level.normalized RMS level` from [data-model.md](data-model.md). Keep the existing peak value available for the recording UI.
- [X] T004 [P] [US1] Build a Settings sensitivity slider with current microphone level, threshold marker, accessible value label, and brief explanation in `Sources/MeetingRecord/TranscriptionView.swift`. Apply `Microphone sensitivity.normalized threshold` and `Microphone input level.normalized RMS level` from [data-model.md](data-model.md).
- [X] T005 [US1] Publish and display the current microphone level from `Sources/MeetingRecord/RecordingCoordinator.swift` through `Sources/MeetingRecord/ContentView.swift` into the Settings view in `Sources/MeetingRecord/TranscriptionView.swift`. Persist slider changes through `Sources/MeetingRecord/TranscriptionCoordinator.swift`.
- [X] T006 [US1] Add threshold interval selection and short context margins for Me windows in `Sources/MeetingRecord/TranscriptionEngine.swift`. Apply `Transcription window.source`, `Transcription window.timeline offset`, and `Transcription window.selected audio intervals` from [data-model.md](data-model.md). Return empty text while advancing progress when no interval qualifies. Keep Other on its existing transcription path and preserve full source CAF files.
- [X] T007 [US1] Add tests in `Tests/MeetingRecordTests/TranscriptionEngineTests.swift` (create this focused test file) for steady signal above threshold, steady signal below threshold, a quiet word at a crossing, a brief pause, empty audio and unchanged Other-track processing.

## Phase 4: User Story 2 — Transcribe in Longer Windows (P2)

**Goal**: Provide about ten seconds of source context to Whisper during live transcription and process every final partial window.

**Independent Test**: Record at least 25 seconds of continuous speech and short pauses, then stop between checkpoints. Verify live results arrive in approximately ten-second work units, the final audio is transcribed, timestamps remain continuous, and recovery drains saved audio.

- [X] T008 [US2] Increase per-source checkpoint publication from five to ten seconds in `Sources/MeetingRecord/RecordingStorage.swift`, preserving file sync, database registration and recovery of previously saved checkpoints.
- [X] T009 [US2] Batch adjacent unprocessed checkpoints for the same source into an approximately ten-second work item in `Sources/MeetingRecord/MeetingStore.swift`. Preserve `Transcription window.recording ID`, `Transcription window.source`, `Transcription window.first offset`, and `Transcription window.last offset` from [data-model.md](data-model.md). Do not combine Me and Other.
- [X] T010 [US2] Update claim, result saving and progress advancement to cover every checkpoint in a batched window in `Sources/MeetingRecord/MeetingStore.swift` and `Sources/MeetingRecord/TranscriptionCoordinator.swift`. Apply `Transcript progress.recording ID`, `Transcript progress.source`, `Transcript progress.checkpoint key`, and `Transcript progress.processed-through offset` from [data-model.md](data-model.md). Ensure duplicate retries cannot skip or duplicate saved passages.
- [X] T011 [US2] Verify the stop and recovery paths wake and drain all remaining partial work in `Sources/MeetingRecord/RecordingCoordinator.swift`, `Sources/MeetingRecord/RecordingStorage.swift`, and `Sources/MeetingRecord/TranscriptionCoordinator.swift`.
- [X] T012 [P] [US2] Add tests in `Tests/MeetingRecordTests/RecordingStorageTests.swift` and `Tests/MeetingRecordTests/MeetingStoreTests.swift` for ten-second checkpointing, two-checkpoint batching, legacy five-second checkpoint compatibility, offset mapping, stop with a partial last window, interrupted recovery, and independent source progress.

## Phase 5: User Story 3 — Keep Navigation Outlines Visible (P2)

**Goal**: Keep the sidebar’s first-row focus ring inside its bounds and remove the unwanted focus border from Home entries without losing keyboard activation.

**Independent Test**: Tab through Home and the sidebar. Confirm Home entries have no blue ring, pressing Enter or Space still opens one, and the first focused sidebar Meeting shows all four edges of its focus ring.

- [X] T013 [US3] In `Sources/MeetingRecord/SidebarView.swift`, inset the focused row outline within the existing row bounds so the top edge is not clipped by the sidebar/list container. Preserve its red or blue focus color.
- [X] T014 [US3] In `Sources/MeetingRecord/HomeView.swift`, remove the explicit keyboard-focus outline from recent Meeting buttons and verify that Tab, Enter, Space, and accessibility activation still open the selected Meeting.

## Phase 6: Polish and Validation

- [ ] T015 Run the suite and complete every scenario in `specs/006-transcription-sensitivity/quickstart.md` on an Apple Silicon Mac. Record threshold values, test speech, model, results and remaining limits in `specs/006-transcription-sensitivity/quickstart.md`.

## Dependencies & Execution Order

- T001 → T002 establish the starting state and preference.
- US1 T003 and T004 can proceed in parallel after T002. T005 wires the meter and preference. T006 uses the shared threshold and RMS scale. T007 validates filtering.
- US2 follows US1 because batching and thresholding both change the same work-item construction. T008 updates storage, then T009 and T010 batch and advance queue progress. T011 validates stop and recovery behavior. T012 tests storage/query fixtures and may proceed alongside T011 after T010.
- US3 is independent after setup and touches separate SwiftUI files from the audio-processing stories.
- T015 depends on all three stories.

## Parallel Opportunities

| Story | Tasks |
| --- | --- |
| US1 | T003 RMS calculation and T004 Settings controls |
| US2 | T011 lifecycle verification and T012 fixture tests after batching is implemented |
| US3 | T013 sidebar inset and T014 Home focus behavior |

## Implementation Strategy

Deliver US1 first as the smallest usable improvement. It exposes the live level and threshold, filters only the Me transcript input and preserves the original audio. Then implement ten-second batching as US2, including final partial-window and recovery handling. Complete US3 independently alongside either story.
