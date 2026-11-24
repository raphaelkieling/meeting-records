# Tasks: Meeting Chat

**Input**: [Specification](spec.md), [plan](plan.md), [research](research.md), [data model](data-model.md), [contracts](contracts/chat.md), and [quickstart](quickstart.md).

**Validation**: Write the story's requested regression tests before its implementation. Use the native Mac checks in the quickstart to review each story separately.

## Phase 1 — Setup

- [X] T001 Run the baseline XCTest suite from `Package.swift` and note the current runtime, minimum platform, and existing issues in `specs/009-meeting-chat/quickstart.md`.

## Phase 2 — Foundation

- [X] T002 Define shared conversation and message types and a cumulative snapshot producer contract in `Sources/MeetingRecord/MeetingChat.swift`. Apply [data-model.md](data-model.md) to `ChatConversation.id`, `ChatConversation.title`, `ChatConversation.scope`, `ChatConversation.updatedAt`, `ChatMessage.id`, `ChatMessage.conversationID`, `ChatMessage.ordinal`, `ChatMessage.role`, `ChatMessage.body`, `ChatMessage.status`, and `ChatMessage.requestID`.

## Phase 3 — User Story 1 · Try the Chat Experience (P1)

**Goal** — Evaluate the native chat experience offline with fictional conversations.

**Independent test** — Open Chat below Search, select both seeded threads, send a multiline question, see an immediate red bubble and streaming Markdown, and verify Stop, error recovery, history switching, scroll follow, and Reduce Motion without networking.

- [X] T003 [US1] Add controllable-stream tests for cumulative snapshots, Stop, failure, history switching, and stale callbacks in `Tests/MeetingRecordTests/MeetingChatTests.swift`.
- [X] T004 [P] [US1] Implement two fictional sample threads and deterministic normal, paused, and error streams in `Sources/MeetingRecord/MeetingChatPreview.swift`.
- [X] T005 [P] [US1] Implement selectable native Markdown blocks and a readable incomplete-block fallback in `Sources/MeetingRecord/ChatMarkdownView.swift`, reusing the formatting approach in `Sources/MeetingRecord/MeetingSummaryView.swift`.
- [X] T006 [US1] Implement session-only preview history, submission, cancellation, and request-gated snapshot updates in `Sources/MeetingRecord/MeetingChatCoordinator.swift`. Apply [data-model.md](data-model.md) to `ChatMessage.requestID`, `ChatMessage.body`, and `ChatMessage.status`.
- [X] T007 [US1] Build History, New Chat, the Preview label, composer, Stop and inline error handling, red user bubbles, and assistant Markdown in `Sources/MeetingRecord/MeetingChatView.swift`. Implement conditional auto-follow, keyboard access, and Reduce Motion per `specs/009-meeting-chat/contracts/chat.md`.
- [X] T008 [US1] Own the chat coordinator for the app session in `Sources/MeetingRecord/RecordingCoordinator.swift`, route Chat in `Sources/MeetingRecord/ContentView.swift`, and wire the Chat row immediately below Search in both the visual and keyboard focus order in `Sources/MeetingRecord/SidebarView.swift`.
- [ ] T009 [US1] Run the preview tests and review normal and interrupted streams, keyboard navigation, motion, and scrolling on the Mac using `specs/009-meeting-chat/quickstart.md` section 1. Record limitations for visual feedback.

## Phase 4 — User Story 2 · Ask About Real Meetings (P2)

**Goal** — Search the local library and deliver on-device answers with citations.

**Independent test** — Use multilingual recordings and distractors. Ask across the library, follow up, constrain the scope, and verify each cited passage opens at the right transcript position. Repeat offline and with missing evidence.

- [X] T010 [US2] Add fixtures and tests for the FTS5 capability probe, ranked and scoped retrieval, revision replacement, deletion, evidence limits, and citation validation in `Tests/MeetingRecordTests/MeetingChatRetrievalTests.swift`.
- [X] T011 [P] [US2] Implement bounded chronological chunking of completed transcript passages in `Sources/MeetingRecord/MeetingChatRetrieval.swift`. Apply [data-model.md](data-model.md) to `TranscriptChunk.recordingID`, `TranscriptChunk.passageIDs`, `TranscriptChunk.startOffset`, `TranscriptChunk.endOffset`, `TranscriptChunk.body`, and `TranscriptChunk.revision`.
- [X] T012 [P] [US2] Add the app-linked FTS5 capability probe and idempotent derived-index setup in `Sources/MeetingRecord/MeetingStore.swift`. Apply [data-model.md](data-model.md) to `TranscriptChunk.id`, `TranscriptChunk.recordingID`, and `TranscriptChunk.revision`. Keep a missing FTS5 module isolated from core library initialization.
- [X] T013 [US2] Connect batched initial backfill, completed transcript revision changes, retries, and single and all-meetings deletion to atomic index updates in `Sources/MeetingRecord/MeetingStore.swift` and refresh on transcription completion from `Sources/MeetingRecord/MeetingChatView.swift`. Use [data-model.md](data-model.md) for `TranscriptChunk.id` and `TranscriptChunk.revision`.
- [X] T014 [US2] Implement bounded meeting candidate and transcript passage queries with canonical SQL filters, quoted tokens, ranking and source validity checks in `Sources/MeetingRecord/MeetingStore.swift` and `Sources/MeetingRecord/MeetingChatRetrieval.swift`.
- [X] T015 [P] [US2] Add a navigation target that opens the correct recording and highlights the cited passage in `Sources/MeetingRecord/ContentView.swift` and `Sources/MeetingRecord/TranscriptionView.swift`. Apply [data-model.md](data-model.md) to `ChatCitation.meetingID`, `ChatCitation.recordingID`, `ChatCitation.passageIDs`, `ChatCitation.startOffset`, and `ChatCitation.revision`.
- [X] T016 [US2] Adapt available Foundation Models to cumulative snapshots and register the two bounded read-only tools in `Sources/MeetingRecord/OnDeviceMeetingChat.swift`. Enforce the contract in `specs/009-meeting-chat/contracts/chat.md` for scope, evidence, follow-ups, and citation validation.
- [X] T017 [US2] Connect live mode, the scope selector, availability, and typed citation controls in `Sources/MeetingRecord/MeetingChatView.swift` and `Sources/MeetingRecord/MeetingChatCoordinator.swift`. Reset or invalidate live evidence on source deletion through `Sources/MeetingRecord/RecordingCoordinator.swift`.
- [ ] T018 [US2] Run the native cases in `specs/009-meeting-chat/quickstart.md` section 2 and record evidence accuracy, baseline availability, multilingual misses, and impact during an active recording.

## Phase 5 — User Story 3 · Return to Saved Conversations (P3)

**Goal** — Restore real chats and their evidence references from local storage.

**Independent test** — Reopen a completed and an interrupted conversation after relaunch, open a retained citation, delete a referenced meeting, and confirm dependent text and citations are gone. Delete a conversation and verify it stays deleted.

- [X] T019 [US3] Add SQLite tests for upgrading an existing library, send atomicity, checkpoint recovery, ordering, thread deletion, and source deletion including inherited and uncited evidence in `Tests/MeetingRecordTests/MeetingChatHistoryTests.swift`.
- [X] T020 [US3] Add live-only SQLite conversation, message, citation, and source-dependency persistence in `Sources/MeetingRecord/MeetingStore.swift`. Apply [data-model.md](data-model.md) to `ChatConversation.id`, `ChatConversation.title`, `ChatConversation.scope`, `ChatConversation.updatedAt`, `ChatMessage.id`, `ChatMessage.conversationID`, `ChatMessage.ordinal`, `ChatMessage.role`, `ChatMessage.body`, `ChatMessage.status`, `ChatMessage.requestID`, `ChatCitation.messageID`, `ChatCitation.meetingID`, `ChatCitation.recordingID`, `ChatCitation.passageIDs`, `ChatCitation.startOffset`, `ChatCitation.revision`, `ChatMessageSource.messageID`, and `ChatMessageSource.meetingID`.
- [X] T021 [US3] Save terminal states and bounded streaming checkpoints, reconcile interrupted replies on launch, and reuse History for persistent threads in `Sources/MeetingRecord/MeetingChatCoordinator.swift` and `Sources/MeetingRecord/MeetingChatView.swift`.
- [X] T022 [US3] Invalidate saved bodies and citations atomically on meeting deletion in `Sources/MeetingRecord/MeetingStore.swift`. Track every source exposed to a reply and reject late snapshots in `Sources/MeetingRecord/MeetingChatCoordinator.swift`. Apply [data-model.md](data-model.md) to `ChatMessage.body`, `ChatMessage.status`, `ChatMessage.requestID`, `ChatMessageSource.messageID`, and `ChatMessageSource.meetingID`.
- [X] T023 [US3] Implement conversation deletion and confirmation on the live History screen in `Sources/MeetingRecord/MeetingChatView.swift` and `Sources/MeetingRecord/MeetingChatCoordinator.swift`.
- [ ] T024 [US3] Validate persistence, interruption, citation reopening, and single and all-meetings deletion using `specs/009-meeting-chat/quickstart.md` section 3.

## Phase 6 — Polish and Cross-Cutting Validation

- [ ] T025 Run the full Swift suite from `Package.swift` and the native scenarios in `specs/009-meeting-chat/quickstart.md`. Record visual, accessibility, capture, migration, and no-network results for the completed increments.

## Dependencies & Execution Order

```text
Setup → Foundation → US1 Preview → visual review → US2 Local Answers → US3 Saved History
```

Polish applies after the last increment included in a delivery. Each story has a separate acceptance procedure in `quickstart.md`.

| Story | Parallel opportunities |
| --- | --- |
| US1 | T004 and T005 touch separate files and can proceed once shared types and the test contract are set. T006 can consume their agreed snapshot interface. |
| US2 | T011, T012 and T015 have distinct files and can proceed after defining the test cases and agreeing on canonical passage identities. T013 and T014 then integrate the index and query paths. |
| US3 | Storage and source invalidation share `MeetingStore.swift`. Sequence T020 → T021 → T022 → T023 to avoid conflicting changes to that file and the chat coordinator. |

## Implementation Strategy

Deliver T001–T009 as the preview MVP. Review message entry, streaming cadence, Markdown, and History on the Mac using fictional data. Add T010–T018 once the interaction is accepted. Add T019–T024 when the evidence and citation flow is ready to persist. Run T025 for the scope being delivered.
