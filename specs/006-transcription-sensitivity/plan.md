# Implementation Plan: Microphone Transcription Sensitivity

**Branch**: \`main\` | **Date**: 2026-11-23 | **Spec**: [Microphone Transcription Sensitivity](spec.md)

**Input**: Feature specification from \`specs/006-transcription-sensitivity/spec.md\`

## Summary

Add a microphone sensitivity slider and live input meter in transcription Settings. Use the persisted threshold only to decide whether saved microphone audio is sent to Whisper, preserving original capture and offsets. Increase capture checkpoints from five seconds to ten seconds while allowing the transcript worker to process adjacent checkpoints together and finalize partial audio on stop.

## Technical Context

**Language/Version**: Swift 6  
**Primary Dependencies**: SwiftUI, AVFoundation, WhisperKit and the existing SQLite store  
**Storage**: Existing CAF files, SQLite recording checkpoints, local UserDefaults setting  
**Testing**: Swift Package Manager XCTest and the scenarios in [quickstart.md](quickstart.md)  
**Target Platform**: macOS 14 or later on Apple Silicon  
**Project Type**: Native desktop app  
**Performance Goals**: Read the microphone meter during capture. Publish a normal live transcript window roughly every ten seconds when work is available.  
**Constraints**: Preserve the original recording, offline operation after model setup, accurate timestamps, and independent Other-track processing  
**Scale/Scope**: Settings, capture-level publication, checkpoint storage and the existing transcription worker

## Constitution Check

**Before design**: Pass. Processing remains local and offline after model setup. Capture retains priority, and source audio is preserved before transcription.

**After design**: Pass. Sensitivity only selects audio for derived text. It does not alter the stored recording. Existing actors, checkpoints and UI are reused, with no new dependency. The plan explicitly flushes pending work on stop.

## Project Structure

### Documentation (this feature)

\`\`\`text
specs/006-transcription-sensitivity/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── contracts/
    └── settings-contract.md
\`\`\`

### Source Code

\`\`\`text
Sources/MeetingRecord/
├── ContentView.swift
├── RecordingCoordinator.swift
├── RecordingStorage.swift
├── TranscriptionCoordinator.swift
├── TranscriptionEngine.swift
└── TranscriptionView.swift
Tests/MeetingRecordTests/
├── RecordingStorageTests.swift
└── TranscriptionEngineTests.swift
\`\`\`

**Structure Decision**: Keep the setting in the existing TranscriptionCoordinator and Settings view. Pass the stored threshold to the existing worker. Use the existing recording level stream for the live meter. Extend existing checkpoint sizes and worker batching without adding an audio framework.

## Implementation Sequence

1. Add a locally persisted threshold with the current behavior as default. Display the microphone's current level and threshold in Settings, reusing RecordingCoordinator's existing live input meter.
2. Filter Me audio for transcription using the selected threshold, retaining a context margin and original timeline offsets. Preserve Other processing and all recorded files. Verify boundary and silent-input cases.
3. Change persisted checkpoint publication from five to ten seconds. Batch adjacent audio checkpoints per source before sending work to Whisper, then ensure the stop path signals and drains the last partial window. Validate timestamp continuity, interrupted recovery and final completion.
