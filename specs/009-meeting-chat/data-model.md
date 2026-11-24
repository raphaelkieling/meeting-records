# Data Model: Meeting Chat

The existing Meeting, Recording and TranscriptPassage records remain canonical. The app reconstructs retrieval data from them. Preview conversations exist in memory and never use the live history tables.

## ChatConversation

| Field | Constraint |
| --- | --- |
| `id` | Stable, unique UUID. |
| `title` | Non-empty display title. Derive it from the first question, or show New Chat before sending. |
| `scope` | All Meetings or one existing Meeting ID. If that Meeting is deleted, preserve the thread and show an unavailable scope until the user changes it. |
| `updatedAt` | Required local activity timestamp. History sorts descending with ID as a stable tie-breaker. |

## ChatMessage

| Field | Constraint |
| --- | --- |
| `id` | Stable, unique UUID, allocated before rendering. |
| `conversationID` | Required parent. Delete messages with the conversation. |
| `ordinal` | Nonnegative, unique within the conversation. Preserve order through restart. |
| `role` | User or assistant. |
| `body` | A trimmed, non-empty user question or cumulative assistant Markdown. Assistant text may be empty before the first snapshot or after source invalidation. |
| `status` | Complete for a user question. Pending, streaming, complete, stopped, failed, interrupted, or source removed for an assistant reply. |
| `requestID` | Required for an assistant reply and absent for a user question. Immutable once allocated. A snapshot must match the conversation and active request. |

A send creates the question and its pending reply together. The first snapshot enters streaming. Completion, Stop, failure, relaunch recovery, and source deletion set the respective terminal state. Delete or invalidate before late snapshots can write. A terminal reply cannot resume. Relaunch changes any remaining pending or streaming answer to interrupted and preserves its latest committed body.

## TranscriptChunk

| Field | Constraint |
| --- | --- |
| `id` | SQLite integer key used by the FTS table. Internal to the rebuildable index. |
| `recordingID` | Required recording reference. A chunk contains passage text from one recording. |
| `passageIDs` | Non-empty ordered original passage identities. Preserve recording, channel, checkpoint, and sequence identity. |
| `startOffset` | Nonnegative recording-relative offset of the first passage. |
| `endOffset` | Recording-relative offset at or after the start. Covers every contributing passage. |
| `body` | Non-empty derived text with channel labels and bounded size. Keep each original passage traceable if a long passage needs splitting. |
| `revision` | Required source and chunking revision. Only current revisions are eligible for retrieval. |

Chunk records and matching FTS rowids change in the same transaction. Source changes invalidate the prior revision before any fresh results can use it. Initial backfill and retries replace the same recording's chunks. Meeting deletion removes their entries in the same operation.

## ChatCitation

| Field | Constraint |
| --- | --- |
| `messageID` | Required assistant message reference. Remove on message deletion or invalidation. |
| `meetingID` | Required source Meeting ID from validated retrieval. |
| `recordingID` | Required source Recording ID owned by that Meeting. |
| `passageIDs` | Non-empty canonical passage references supplied by retrieval. |
| `startOffset` | Nonnegative recording-relative offset associated with the cited passage. |
| `revision` | Required source revision at citation time. A link whose original passage or revision can no longer be resolved shows Source unavailable. |

FTS rowids and raw excerpts are excluded from citations. Show titles and timestamps by resolving current canonical data.

## ChatMessageSource

| Field | Constraint |
| --- | --- |
| `messageID` | Required assistant message reference. Delete with the message. |
| `meetingID` | Required source meeting ID. The pair with messageID is unique. Record all meetings whose data entered generation, including inherited context, even if a reply cites fewer sources. |

A live reply's checkpoint and accumulated source dependencies commit together. Single-meeting and all-meetings deletion atomically clear affected assistant bodies and citations, set source removed, and remove the dependency records. In-flight work is cancelled or rejected before it can write another snapshot. User-authored questions remain.
