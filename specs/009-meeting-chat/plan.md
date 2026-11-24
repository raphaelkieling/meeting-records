# Implementation Plan: Meeting Chat

**Feature**: `009-meeting-chat` | **Date**: 2026-11-24 | **Spec**: [spec.md](spec.md)

## Summary

Ship a native SwiftUI preview first so the user can assess live-feeling Markdown, bubble entry, scroll behavior, and the history selector with fictional conversations. Then add local meeting retrieval and on-device generation. Persist live conversations in a separate increment after the retrieval and citation flow is usable.

## Technical Context

| Area | Decision |
| --- | --- |
| Language | Swift 6 and Swift Package Manager |
| Platform | Apple Silicon macOS 14+ for the app and preview. Real generation requires macOS 26+ with Apple Intelligence available. |
| UI | SwiftUI and Foundation Markdown parsing. Reuse the current app accent, typography, and Summary formatting conventions. |
| Storage | Existing SQLite library and SQLite FTS5. Add a reconstructible index and additive history migration. No new packages or model downloads for preview. |
| Streaming | Deterministic asynchronous fixture snapshots, then Foundation Models snapshots through the same UI contract. Keep one active request and one assistant row per turn. |
| Testing | XCTest for state, persistence, and retrieval. Native quickstart scenarios for timing, scrolling, accessibility, real-model quality, and recording. |
| Performance | Display submitted text in the same interaction. Batch stream updates and throttle durable checkpoints. Use bounded local retrieval and small indexing batches that yield to capture writes. |
| Scope | One Chat destination, two read-only retrieval tools, one local generation provider, zero new dependencies. |

## Constitution Check

| Principle | Before research | After design |
| --- | --- | --- |
| I. Local operation | Keep preview and live retrieval offline. | Preview uses fictional data. Real generation uses an available on-device model. No cloud transport for Chat. |
| II. Capture priority | Avoid capture pipeline changes. | Index asynchronously from committed completed transcripts. Bound database work and explicitly verify capture during indexing and generation. |
| III. Provenance and reconstructibility | Preserve Meetings, Inputs, and transcription segments as canonical records. | Store original passage references, rebuild the index, and clear derived assistant content when its source meeting is deleted. |
| IV. Faithfulness | Retain Me and Other as channels. | Validate citations and exercise Portuguese, Spanish, English, and mixed-language audio. Calendar invitation data supplies search context. |
| V. Simplicity | Validate interaction before adding storage or inference. | Reuse native SwiftUI, existing SQLite and Foundation Models. No vector database or external Markdown renderer. |

The product expansion and acceptance criteria are recorded in [PRODUCT.md](../../PRODUCT.md#meeting-chat-expansion). The design preserves the local-processing commitment. Both gates pass without an amendment.

## Project Structure

```text
specs/009-meeting-chat/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── contracts/chat.md
├── quickstart.md
└── tasks.md

Sources/MeetingRecord/
├── ContentView.swift
├── SidebarView.swift
├── MeetingRecordApp.swift
├── MeetingSummaryView.swift
├── TranscriptionView.swift
├── RecordingCoordinator.swift
├── TranscriptionCoordinator.swift
├── MeetingStore.swift
├── MeetingChat.swift
├── MeetingChatCoordinator.swift
├── MeetingChatView.swift
├── MeetingChatPreview.swift
├── ChatMarkdownView.swift
├── MeetingChatRetrieval.swift
└── OnDeviceMeetingChat.swift

Tests/MeetingRecordTests/
├── MeetingChatTests.swift
├── MeetingChatRetrievalTests.swift
└── MeetingChatHistoryTests.swift
```

Keep navigation in the existing window. The app-scoped Chat coordinator owns conversation and request state. Its fixture and on-device producers both publish cumulative snapshots. The retrieval module owns chunking, ranking, and citation resolution. MeetingStore owns writes and schema migrations. Keep recording, transcription, and Summary behavior compatible with the current library.

## Delivery

1. **Preview** adds the sidebar destination, in-memory history selector, composer, animation, deterministic streaming, and safe Markdown. Review it on the Mac before starting live retrieval.
2. **Local answers** add an app-level FTS5 capability check, staged backfill, read-only retrieval, on-device generation, and source navigation. The live conversation is session-only during this increment.
3. **Saved history** adds persisted real conversations, throttled checkpoints, source dependencies, and deletion and restart handling. Continue using isolated fixtures in Preview.

See [research](research.md), [data model](data-model.md), [interaction contract](contracts/chat.md), and [validation guide](quickstart.md) for implementation details and checks.
