# Research: Meeting Chat

## Native preview and Markdown

**Decision** — Use separate fictional conversations with deterministic cumulative snapshots paced in small word groups. Inject a controllable delay for tests. Give each response one stable row, animate row entry once, and follow the bottom while the reader is already there. Reuse Summary's SwiftUI block layout and Foundation inline Markdown. Handle headings, lists and code fences at the block level and show incomplete blocks as readable text. Render citations through typed SwiftUI controls.

**Rationale** — This permits repeatable visual evaluation and matches the on-device stream's snapshot shape. Keeping preview data in memory avoids creating or indexing a user's library during the demo. Native views support selection, headings, and keyboard navigation.

**Alternatives considered** — A real model would vary response timing and require setup. A WebView or Markdown package would add dependencies or a rendering surface before validating the intended subset. [Foundation Markdown documentation](https://developer.apple.com/documentation/foundation/instantiating-attributed-strings-with-markdown-syntax) · [Foundation Models stream snapshots](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/responsestream/snapshot)

## Retrieval and indexing

**Decision** — Keep canonical transcript records in MeetingStore. Use an app-gated FTS5 virtual table over derived chunks from completed recordings. Start with roughly 250–450 tokens per chunk, estimated without an additional tokenizer dependency. Preserve chronological order, prefer whole passages, and use neighboring context within the same recording. Use `unicode61 remove_diacritics 2`, BM25 ranking, parameterized SQL and quoted search terms. Apply meeting and date scope before top-k selection.

**Rationale** — The app already stores stable passage identities and recording-relative offsets. The existing command-palette substring search returns meetings and a first excerpt. A local ranked passage index gives the chat better evidence without changing that search. Use explicit writes to the chunk and FTS tables in the same transaction. Capturing an index revision before indexing and checking it again before publication prevents stale results after retranscription. Delete FTS rows in the same transaction as their chunk rows. Restrict indexing and matching to recordings with a valid current revision.

**Alternatives considered** — The current substring search can locate named meetings, but full transcript scans and first excerpts make it a weak passage ranker. Embeddings could help with paraphrase or cross-language retrieval. Review misses from the multilingual acceptance set before adding them. SQLite FTS5 and accent-insensitive matching were verified on the current Mac. The app-linked macOS 14 runtime still needs a capability check. If the module is missing, keep Preview and existing library behavior available. [SQLite FTS5](https://www.sqlite.org/fts5.html)

## Model and citations

**Decision** — Use the existing Apple Intelligence availability pattern for real generation. Use Foundation Models only on supported systems. Expose two typed read-only operations and enforce scope, request budgets, and citation validity in the app. Resolve citation IDs to a meeting, recording, and original passage identities. Start with transcript navigation and a highlighted passage.

**Rationale** — The app can keep real questions and evidence on-device without extending the existing Summary provider setting. Model-provided labels or links cannot be trusted to identify actual sources. Follow-ups can retain recent turns and context through bounded requests scoped to the selected meetings.

**Alternatives considered** — A cloud provider would need a separate product and privacy decision. Opening audio at the cited offset adds playback work that can follow transcript navigation. [Foundation Models tools](https://developer.apple.com/documentation/foundationmodels/tool)

## Durable history

**Decision** — Keep fixture and live conversations separate. Write live questions and pending replies on submit, checkpoint visible assistant text, and persist terminal states. Store source references and meeting-level dependency records together with assistant text. Clear dependent assistant output on meeting deletion, including replies that reused a sourced earlier turn.

**Rationale** — An earlier assistant response can retain meeting information even when a citation is removed. Tracking all meeting data included in generation, including uncited and inherited evidence, allows deletion and prevents stale streams from restoring removed content.

**Alternatives considered** — Persisting only final answers loses visible text on interruption. Keeping raw prompt or transcript copies in history duplicates the library and complicates deletion.
