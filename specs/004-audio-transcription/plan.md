# Implementation Plan: Live Audio Transcription

**Branch**: `004-audio-transcription` (planned; current checkout remains `main`) | **Date**: 2026-11-23 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/004-audio-transcription/spec.md`

## Summary

Add quality-first, offline transcription for each audio Input and present the results as one Meeting transcription. Use one WhisperKit runtime with selectable Large v3, Small, and Base assets for later validation. Persisted audio chunks feed a bounded background transcription pipeline so capture, durable writes, and UI remain responsive. Add per-Input transcript state and segments, explicit one-time model download, recovery after app closure, and the unified Transcription view.

## Technical Context

**Language/Version**: Swift 6, SwiftUI; the package currently targets macOS 14.

**Primary Dependencies**: Existing AVFoundation, ScreenCaptureKit, Swift Concurrency, and SQLite. Use WhisperKit 0.15.0 for local ASR.

**Storage**: Existing SQLite schema v3 for Meetings, Recordings, and Audio Segments; local `.caf` checkpoints in Application Support. Add persisted per-Input transcription jobs and transcript segments. Store installed model bundles locally outside the database.

**Testing**: Existing XCTest suite with new storage and pipeline coverage, corrected local speech samples for a manual quality benchmark, native UI validation, and Release-build Instruments profiling.

**Target Platform**: macOS 14+ on Apple Silicon. Reference machine: Apple M4 Max, 14 CPU cores, 36 GB memory, macOS 27.2.1.

**Project Type**: Single SwiftUI macOS desktop app.

**Performance Goals**: Prioritize transcript quality while guaranteeing durable capture. Across a 60-minute dual-track recording on the reference machine, lose no captured audio to ASR pressure and keep Meeting navigation usable. Measure transcript update delay, real-time factor, memory, heat, and post-stop backlog drain; set no unsupported sub-second latency promise.

**Constraints**: All audio inference remains on-device after an explicit model download. Never send audio or transcript data to a service. Capture and disk persistence outrank ASR. Preserve Me/Other tracks and overlapping timestamps. Do not restart audio capture after app closure. Keep the existing macOS 14 deployment floor unless a separate product decision changes it.

**Scale/Scope**: A Meeting can contain multiple audio Inputs; verify the unified view with 10 Inputs. One Recording may contain two concurrently captured audio sources. Model evaluation includes long dual-track capture and mixed Portuguese, Spanish, and English.

## Constitution Check

### Before research

- **I. Local/offline processing** — PASS. The selected model is explicitly downloaded once and inference remains local.
- **II. Capture durability** — PASS. Persist audio checkpoints before ASR scheduling; ASR delay cannot block or discard capture.
- **III. Preserved source and reconstruction** — PASS. Persist results per Input and derive the unified Meeting view in the existing Input order.
- **IV. Faithful transcript** — PASS. Retain Me/Other identity, offsets, overlapping speech, and supported language changes.
- **V. Simplicity and Mac validation** — PASS. Ship one benchmarked model, reuse existing storage and UI, and profile on the reference Mac before locking concurrency settings.

No gate violations identified.

## Design Decisions

### Model selection

Offer Whisper Large v3 (suggested), Small, and Base in Settings. Downloads are explicit and the active model is used for new Inputs and saved Inputs that have not started. Inputs with saved progress retain their original model version when they resume. Compare quality and performance on the reference Mac after implementation. The evaluation does not gate development. See [research.md](research.md) for the asset pins and candidate background.

### Concurrency and capture protection

Reuse `RecordingCapture`'s ordered serial callback queue, `RecordingStorage` actor, bounded sample stream, and SQLite actors. Do not execute model inference on `MainActor`, the AV capture callback queue, or the durable storage actor.

Publish a checkpoint to disk first, then signal a single background worker through a coalescing notification. The worker pulls one eligible checkpoint from SQLite at a time, favoring the active Input. Run inference in an isolated background worker coordinated with Swift Concurrency. Keep chunks ordered within each Input and audio source. Start with one loaded model instance and a bounded inference worker; let Core ML or the selected runtime use its supported compute devices. Scale concurrency only when Release profiling proves it improves update delay without capture overruns, unbounded memory, or duplicated work. If work backs up, keep the source audio durable, expose Pending/Transcribing state, and drain the persisted backlog after capture.

The existing Inputs query excludes an open Recording. Extend it so the active Input appears with its Pending/Transcribing badge while recording. Closing the app ends capture; recovery finalizes that Input as interrupted and resumes only unfinished transcription from its saved checkpoint.

## Constitution Check

### After design

- **I. Local/offline processing** — PASS. Explicit model setup is part of this feature; subsequent capture and transcription require no network.
- **II. Capture durability** — PASS. Bounded ASR scheduling consumes persisted checkpoints and cannot block AV capture or durable writes.
- **III. Preserved source and reconstruction** — PASS. Transcript jobs and timestamped segments are stored by Input and combined deterministically for display.
- **IV. Faithful transcript** — PASS. The model evaluation covers pt-BR/es/en and language switching; segment timestamps preserve both tracks and overlap.
- **V. Simplicity and Mac validation** — PASS. The design adds one engine, reuses current storage and capture, and tunes worker count only after profiling.

No gate violations identified.

## Project Structure

### Documentation (this feature)

```text
specs/004-audio-transcription/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── ui-contract.md
└── tasks.md                 # Created later by $speckit-tasks
```

### Source Code (repository root)

```text
Sources/MeetingRecord/
├── ContentView.swift                 # Meeting tabs and local-model setup route
├── InputsView.swift                  # Existing Input cards plus per-Input status badge
├── MeetingStore.swift                # Schema migration and transcript persistence
├── RecordingCoordinator.swift        # Publish live Input and prioritize capture lifecycle
├── RecordingStorage.swift            # Persist chunks before making them eligible for ASR
├── Transcription.swift               # Status, transcript segment, and model state
├── TranscriptionEngine.swift         # Adapter boundary for the single selected local engine
├── TranscriptionCoordinator.swift    # Bounded work, recovery, and model scheduling
└── TranscriptionView.swift           # Unified Meeting transcript

Tests/MeetingRecordTests/
├── MeetingStoreTests.swift           # Migration and transcript storage
└── TranscriptionPipelineTests.swift  # Ordering, deduplication, status, recovery
```

**Structure Decision**: Extend the existing single SwiftUI executable and its SQLite store. Keep ASR behind one app-internal engine boundary so the quality bake-off does not spread model-specific types through UI or persistence. Do not add a second application, server, or remote service.

## Delivery Order

1. **Pin runtime and assets** — Pin WhisperKit and the selectable model assets.
2. **Persist transcript state** — Add the SQLite migration, per-Input job/status, timestamped source segments, provisional replacement, idempotent checkpoint writes, and resume offsets. Preserve existing Recording rows and clips.
3. **Build the isolated pipeline** — Publish active Input state, enqueue only durable checkpoints, run bounded background inference, persist progress, resume unfinished work after launch, and finalize status after all audio is processed.
4. **Integrate setup and UI** — Add explicit model download size/progress/readiness in Settings, add the status badge to existing Inputs rows, and render the unified live transcript in the Transcription tab.
5. **Validate and tune** — Run the native scenarios and model scorecard after integration, and profile a 60-minute dual-track Release run with Instruments. Tune chunk cadence, QoS, compute units, and bounded worker count from evidence; verify offline operation and app-closure recovery.

See [research](research.md), [data model](data-model.md), [UI contract](contracts/ui-contract.md), and [quickstart](quickstart.md).

## Complexity Tracking

No constitution violations or additional projects are required. The model adapter and bounded worker are necessary to isolate local inference from capture, storage, and UI.
