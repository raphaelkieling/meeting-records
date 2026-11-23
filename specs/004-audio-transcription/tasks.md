---
description: "Implementation tasks for live audio transcription"
---

# Tasks: Live Audio Transcription

**Input**: Design documents in `specs/004-audio-transcription/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/ui-contract.md`

**Tests**: Automated test tasks are omitted because the specification does not explicitly request them. Manual quality, lifecycle, and performance validation remain required by the plan.

## Phase 1: Setup

**Purpose**: Resolve the local ASR engine and model from measured evidence before locking dependencies.

- [ ] T001 Prepare corrected pt-BR, Spanish, English, mixed-language, noisy, and overlapping speech samples and a repeatable scorecard in `specs/004-audio-transcription/research.md`
- [ ] T002 Benchmark Qwen3-ASR-1.7B and WhisperKit with Whisper large-v3 on the reference Mac; record quality, language switching, timestamps, offline operation, memory, and capture-safety results and select one engine/model in `specs/004-audio-transcription/research.md`
- [ ] T003 Record the winning runtime dependency, exact model version, asset source, and measured download size in `Package.swift` and `specs/004-audio-transcription/research.md`

## Phase 2: Foundational

**Purpose**: Add durable storage and engine seams required by all user stories.

- [ ] T004 Add the SQLite migration and persistence APIs for per-Input jobs and transcript segments in `Sources/MeetingRecord/MeetingStore.swift` (canonical fields: `Audio Input.id`, `Audio Input.meetingID`, `Audio Input.kind`, `Audio Input.createdAt`, `Audio Input.endedAt`, `Audio Input.audioSources`, `Audio Input.recordingState` per `specs/004-audio-transcription/data-model.md`)
- [ ] T005 Define transcription job, segment, and model state types in `Sources/MeetingRecord/Transcription.swift` (canonical fields: `Input Transcript Job.inputID`, `Input Transcript Job.meetingID`, `Input Transcript Job.status`, `Input Transcript Job.processedThrough`, `Input Transcript Job.modelID`, `Input Transcript Job.modelVersion`, `Input Transcript Job.lastError`, `Input Transcript Job.updatedAt`; `Transcript Segment.id`, `Transcript Segment.inputID`, `Transcript Segment.audioSource`, `Transcript Segment.startOffset`, `Transcript Segment.endOffset`, `Transcript Segment.text`, `Transcript Segment.revisionState`, `Transcript Segment.sequence`; `Local Transcription Model.modelID`, `Local Transcription Model.version`, `Local Transcription Model.assetLocation`, `Local Transcription Model.downloadSize`, `Local Transcription Model.installationState`, `Local Transcription Model.downloadProgress` per `specs/004-audio-transcription/data-model.md`)
- [ ] T006 Define the selected local ASR adapter boundary and model lifecycle interface in `Sources/MeetingRecord/TranscriptionEngine.swift`

## Phase 3: User Story 1 - Read transcription while recording (Priority: P1)

**Goal**: Transcribe persisted audio incrementally without slowing or interrupting capture.

**Independent Test**: With the selected model available, start and stop a dual-source recording; observe text before stopping, then confirm backlog completion while capture remains responsive.

- [ ] T007 [US1] Publish durable audio checkpoints to transcription only after storage confirms persistence in `Sources/MeetingRecord/RecordingStorage.swift`
- [ ] T008 [US1] Implement a bounded background transcription queue using one loaded model instance; process one Input at a time in Input order, prioritize chunks from the active recording, then drain older pending Inputs sequentially in `Sources/MeetingRecord/TranscriptionCoordinator.swift`
- [ ] T009 [US1] Persist incremental provisional/final segments idempotently and update per-Input status and source offsets in `Sources/MeetingRecord/TranscriptionCoordinator.swift` (canonical fields: `Input Transcript Job.status`, `Input Transcript Job.processedThrough`, `Input Transcript Job.updatedAt`, `Transcript Segment.id`, `Transcript Segment.inputID`, `Transcript Segment.audioSource`, `Transcript Segment.startOffset`, `Transcript Segment.endOffset`, `Transcript Segment.text`, `Transcript Segment.revisionState`, `Transcript Segment.sequence` per `specs/004-audio-transcription/data-model.md`)
- [ ] T010 [US1] Enqueue each newly persisted recording checkpoint for incremental transcription without blocking capture in `Sources/MeetingRecord/RecordingCoordinator.swift`
- [ ] T011 [US1] Keep the active Recording visible in Inputs and add its Pending, Transcribing, or Complete badge while preserving existing card controls in `Sources/MeetingRecord/MeetingStore.swift` and `Sources/MeetingRecord/InputsView.swift`

## Phase 4: User Story 2 - Read one unified Meeting transcription (Priority: P1)

**Goal**: Display every Input transcript once in one Meeting view with source, speaker, timing, and overlap preserved.

**Independent Test**: Open a Meeting with at least two Inputs and confirm all segments appear once in Input order, including overlapping Me/Other passages and live additions.

- [ ] T012 [US2] Query persisted segments in Meeting Input order without storing a duplicate combined transcript in `Sources/MeetingRecord/MeetingStore.swift`
- [ ] T013 [US2] Build the unified scrollable Meeting transcript with Input boundaries, source labels, timestamps, overlap, provisional text, pending context, and the existing empty state in `Sources/MeetingRecord/TranscriptionView.swift`
- [ ] T014 [US2] Connect the Transcription tab to the unified live transcript and refresh it as segments/status change in `Sources/MeetingRecord/ContentView.swift`

## Phase 5: User Story 3 - Recover transcription after the app closes (Priority: P2)

**Goal**: Recover saved audio and resume unfinished transcription without restarting capture.

**Independent Test**: Close during capture, reopen, confirm the Input is interrupted and capture remains stopped, observe unfinished transcription resume, then explicitly start a distinct Input.

- [ ] T015 [US3] Recover an unfinished capture as an interrupted Input while preserving its audio checkpoints and recording lifecycle in `Sources/MeetingRecord/RecordingStorage.swift` (canonical fields: `Audio Input.id`, `Audio Input.meetingID`, `Audio Input.createdAt`, `Audio Input.endedAt`, `Audio Input.audioSources`, `Audio Input.recordingState` per `specs/004-audio-transcription/data-model.md`)
- [ ] T016 [US3] Resume jobs from saved per-source offsets on launch, returning interrupted work to Pending and preserving completed segments in `Sources/MeetingRecord/TranscriptionCoordinator.swift` (canonical fields: `Input Transcript Job.inputID`, `Input Transcript Job.status`, `Input Transcript Job.processedThrough`, `Input Transcript Job.lastError`, `Input Transcript Job.updatedAt` per `specs/004-audio-transcription/data-model.md`)
- [ ] T017 [US3] Ensure an explicit post-relaunch start creates a separate Input and job without auto-resuming capture in `Sources/MeetingRecord/RecordingCoordinator.swift` (canonical fields: `Audio Input.id`, `Audio Input.meetingID`, `Audio Input.kind`, `Audio Input.createdAt`, `Audio Input.recordingState`, `Input Transcript Job.inputID`, `Input Transcript Job.meetingID`, `Input Transcript Job.status` per `specs/004-audio-transcription/data-model.md`)

## Phase 6: User Story 4 - Prepare the local transcription model (Priority: P2)

**Goal**: Let the user explicitly download the selected model once and transcribe offline afterward.

**Independent Test**: Review the selected model and size, download it with visible progress, disconnect from the internet, and transcribe a saved Input locally.

- [ ] T018 [US4] Implement explicit model download, progress, installation readiness, and local asset resolution in `Sources/MeetingRecord/TranscriptionEngine.swift` (canonical fields: `Local Transcription Model.modelID`, `Local Transcription Model.version`, `Local Transcription Model.assetLocation`, `Local Transcription Model.downloadSize`, `Local Transcription Model.installationState`, `Local Transcription Model.downloadProgress` per `specs/004-audio-transcription/data-model.md`)
- [ ] T019 [US4] Add Settings UI identifying the selected model and download size before download, with progress, readiness, and unavailable explanation in `Sources/MeetingRecord/ContentView.swift`
- [ ] T020 [US4] Gate transcription scheduling on model readiness and retain audio as Pending with an explanation when unavailable in `Sources/MeetingRecord/TranscriptionCoordinator.swift` (canonical fields: `Input Transcript Job.status`, `Input Transcript Job.modelID`, `Input Transcript Job.modelVersion`, `Input Transcript Job.lastError`, `Input Transcript Job.updatedAt` per `specs/004-audio-transcription/data-model.md`)

## Phase 7: Polish & Cross-Cutting Validation

**Purpose**: Verify quality, capture safety, offline behavior, and responsiveness on the reference Mac.

- [ ] T021 Profile a 60-minute dual-track Release recording with Instruments; tune checkpoint cadence, QoS, compute units, and bounded worker settings without audio loss in `specs/004-audio-transcription/research.md`
- [ ] T022 Record manual validation outcomes for 10 Inputs, mixed pt-BR/es/en speech, overlap, offline inference, app-close recovery, and pending backlog drain in `specs/004-audio-transcription/quickstart.md`

## Dependencies & Execution Order

### Phase Dependencies

- Setup selects and locks one runtime/model before implementation depends on it.
- Foundational storage and adapter contracts block all user stories.
- User stories follow the listed order; US3 and US4 can be developed independently after foundation, while runtime execution in US1 requires the model to be ready.
- Polish depends on the end-to-end flows being integrated.

### User Story Dependencies

- **US1 (P1)**: Depends on the model/runtime decision and foundational persistence; requires a ready local model to demonstrate transcription.
- **US2 (P1)**: Depends on transcript persistence from US1; the view can be implemented against persisted segments before the live queue is complete.
- **US3 (P2)**: Depends on durable job and segment persistence; recovery behavior can be validated independently after foundation.
- **US4 (P2)**: Depends on the selected model from Setup; its Settings and installation flow enables offline processing for US1.

### Parallel Opportunities

- T001 can run independently of UI work; T002 depends on its sample set; T003 depends on the benchmark decision.
- After foundation, US2 view work (T013) can proceed alongside US3 recovery work and US4 setup UI, with shared-store edits coordinated.
- Within US1, checkpoint publication and Inputs badge integration can proceed in separate files; queue orchestration depends on the persistence and engine interfaces.

## Parallel Example: User Story 1

```text
T007: Publish durable checkpoints from RecordingStorage.swift
T011: Show active Input and transcription badge in InputsView.swift
```

## Implementation Strategy

### MVP First

Complete Setup and Foundational, then US1 to produce incremental per-Input transcription with a ready local model. Add US2 next so users can read the unified Meeting transcript. US3 and US4 complete restart recovery and first-time local model setup; validate the full flow offline before release.

### Incremental Delivery

Deliver in order: model decision and persistence seams → live per-Input transcription → unified transcript → recovery and explicit model setup → 60-minute performance and multilingual validation.
