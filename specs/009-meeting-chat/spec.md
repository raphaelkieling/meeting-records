# Feature Specification: Meeting Chat

**Feature**: `009-meeting-chat`  
**Created**: 2026-11-24  
**Status**: Draft

## User Scenarios & Testing

### User Story 1 — Try the Chat Experience (P1)

As a user, I want to open Chat and try a conversation so I can assess the sidebar entry, message layout, animation, streaming, and history selection before using real meetings.

**Independent test**: On a Mac with networking disabled, open Chat below Search, select each seeded conversation in History, choose New Chat, send a message, and observe a red bubble followed by a progressively rendered Markdown reply. Stop a second reply, switch conversations mid-stream, and repeat with Reduce Motion enabled.

- Chat opens as a destination in the existing window. History selects a thread and New Chat starts an empty one. Switching restores each thread's messages.
- The sender's text appears immediately in a right-aligned app-red bubble. Assistant text streams on the left in a Markdown viewer. A visible Preview label identifies the use of fictional data.
- The composer supports keyboard send, multiline input, and Stop. A stopped reply retains text already shown. Sending an empty message has no effect.
- Streaming does not steal scroll position from someone reading older messages. Reduce Motion suppresses entry animations and animated scrolling while keeping the text updates.
- The preview remains usable across navigation within the app session. Preview threads and sample data are isolated from the meeting library and future live history.

### User Story 2 — Ask About Real Meetings (P2)

As a user, I want Chat to find meetings relevant to my question and cite the transcript so I can verify answers and ask follow-ups.

**Independent test**: Seed a local library with a relevant decision and a distractor across multiple meetings. Ask a question spanning the library, follow up without repeating the meeting title, then select a single meeting and repeat. Verify the linked transcript, no-evidence behavior, and offline operation on a Mac with the local model available.

- Chat can search all meetings or a single selected meeting. Candidate search supports title, description, tags, date, and available calendar invitee names. Transcript search ranks passages within the requested scope.
- Chat extracts search terms and explicit filters locally. The model can request bounded lookups through the app's read-only retrieval interface. Follow-ups carry only the current thread's recent context and pass through the same scope checks.
- Replies distinguish plans and invitees from what the transcript establishes. A citation opens the relevant meeting on the Transcription tab, identifies the recording and timestamp, and reveals the cited passage. Insufficient evidence produces a limited answer or a request for clarification.
- Real answers stream using the on-device model where available. The preview remains available when the device cannot run that model. No calendar data or transcript text leaves the Mac.

### User Story 3 — Return to Saved Conversations (P3)

As a user, I want to reopen real conversations from History so I can continue where I left off and verify earlier answers.

**Independent test**: Ask a real question, relaunch, reopen the thread, and follow a citation. Repeat after cancelling a response and after deleting a source meeting. Delete a thread and verify it stays deleted after relaunch.

- Live history lists conversations by most recent activity. It retains sent questions, streamed answer checkpoints, and source references locally.
- Interrupted replies are visibly incomplete. Reopening a conversation does not automatically restart generation.
- Deleting a conversation removes its messages and sources. Deleting a source meeting removes its retrieval entries and clears dependent assistant text, including replies grounded in that source through a prior turn. The owner's questions remain in their conversation.

## Requirements

- **FR-001**: Chat MUST sit immediately below Search and reuse the app's native SwiftUI layout and red accent.
- **FR-002**: The preview MUST work with two seeded sample conversations and deterministic Markdown streaming, including a controlled pause and an error fixture.
- **FR-003**: Assistant Markdown MUST support headings, paragraphs, lists, emphasis, inline code, and fenced code. Incomplete Markdown MUST remain readable while its text arrives.
- **FR-004**: Sidebar navigation, the compose and Stop controls, History, and citations MUST be usable by keyboard and expose clear accessibility labels. Preview animation MUST honor Reduce Motion.
- **FR-005**: Retrieval MUST use rebuildable local indexes with stable links to original transcript passages. Initial indexing, retries, retranscription, and deletion MUST leave results consistent with the source recordings.
- **FR-006**: Live generation MUST use only validated results and a bounded prompt. Calendar and transcript content MUST be treated as data. Speaker channels and invited names MUST remain distinct.
- **FR-007**: Persistence MUST support restart, partial answers, deletion, and source invalidation. A stopped or superseded stream MUST be unable to append text to another reply.
- **FR-008**: Validation MUST cover preview stream and cancellation behavior, SQLite migration and deletion, local retrieval ranking, citation validation, multilingual fixtures, and capture responsiveness.

## Success Criteria

- **SC-001**: A user can evaluate message entry, streaming, cancellation, Markdown, and history offline using the preview alone.
- **SC-002**: Each answer in the real-chat acceptance cases cites a supporting passage or states the evidence gap. Scoped questions do not cite meetings outside the selected scope.
- **SC-003**: After restart, completed live replies and source references reopen from History. Interrupted replies stay labelled, and a deleted meeting cannot appear in new results or through previously saved assistant text.

## Scope

Deliver the preview first. Real retrieval and durable history are planned follow-up increments. The current expansion covers local, read-only meeting retrieval. Vector search, cloud model support for Chat, playback seeking, and generic tool execution are deferred. See `PRODUCT.md`, Meeting Chat expansion, for the product acceptance criteria.
