# Implementation Plan: Meetings Home

**Branch**: `main` | **Date**: 2026-11-23 | **Spec**: [Meetings Home](spec.md)

**Input**: Feature specification from `specs/005-meetings-home/spec.md`

## Summary

Replace the Home placeholder with three recently created Meetings and two library totals. Open a Meeting from Home in Inputs with its latest saved recording visible. Refresh Home from committed library changes. Add confirmed Meeting deletion through the sidebar, with recoverable cleanup of local audio files.

## Technical Context

**Language/Version**: Swift 6  
**Primary Dependencies**: SwiftUI, AVFoundation, SQLite, and existing WhisperKit processing  
**Storage**: Existing local SQLite database and per-Meeting recording directories  
**Testing**: Swift Package Manager tests and the native macOS checks in [quickstart.md](quickstart.md)  
**Target Platform**: macOS 14 or later on Apple Silicon  
**Project Type**: Desktop app  
**Performance Goals**: Keep audio metadata reads off the main actor and reuse each saved duration across refreshes within the app session  
**Constraints**: Offline operation, refresh after committed changes, durable deletion across database and file storage  
**Scale/Scope**: One Home view, one sidebar menu action, and their existing navigation and storage paths

## Constitution Check

**Before design**: Pass. The [product acceptance criteria](../../PRODUCT.md#critérios-de-aceitação-da-primeira-versão) cover offline library use and full Meeting deletion.

**After design**: Pass. The app reads and deletes local data (I), preserves capture through finalization (II), removes a Meeting's sources and derived data after confirmation (III), and reuses current app components (V). The design requires no new dependency. The quickstart covers saved audio, interrupted recovery, processing and deletion.

## Project Structure

### Documentation (this feature)

```text
specs/005-meetings-home/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── contracts/
    └── ui-contract.md
```

### Source Code (repository root)

```text
Sources/MeetingRecord/
├── ContentView.swift
├── HomeView.swift
├── SidebarView.swift
├── InputsView.swift
├── MeetingStore.swift
├── RecordingCoordinator.swift
├── RecordingStorage.swift
└── TranscriptionCoordinator.swift
Tests/MeetingRecordTests/
├── MeetingStoreTests.swift
└── RecordingStorageTests.swift
```

**Structure Decision**: Keep navigation in ContentView, use a small HomeView for presentation, and extend the existing store and coordinators for refresh and deletion.

## Implementation Sequence

1. Add the Home library read and reuse saved playback timing. Show the recent list and compact totals, and pass the Home navigation intent to Inputs for its initial scroll and highlight.
2. Wire refresh to committed Meeting mutations, recording finalization or recovery, and transcription completion. Prevent an older async read from replacing newer results. Cover list ordering and totals with existing store and recording test fixtures.
3. Add sidebar confirmation. Recheck the target's capture state, delete its rows and enqueue its file cleanup atomically, then update navigation and Home. Retry pending cleanup after interruption or failure. Verify cancellation, active capture, late transcription, and cleanup retry.
