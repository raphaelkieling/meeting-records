# Meeting Chat Contracts

## Navigation and message rendering

- **Sidebar**. Chat sits directly below Search and uses the existing selected-row treatment. Opening Chat uses the existing app window and preserves the current conversation while navigating within the app session.
- **Header**. History opens a single-select list ordered by latest activity. New Chat clears the selected conversation and focuses the composer. Preview is visibly identified. Real mode exposes All Meetings and a single-meeting scope.
- **Messages**. User questions are right-aligned in the app's red accent and remain readable in light and dark appearance. Assistant replies are left-aligned, selectable Markdown with headings, paragraphs, lists, emphasis, inline code, and fenced code. Plain text covers incomplete blocks. Citation controls are constructed from typed references outside Markdown.
- **Composer**. Return sends a nonblank question and Shift-Return inserts a line break. Stop cancels the active request and leaves arrived text visible. A failing stream shows an inline error and leaves the composer usable.
- **Motion and scrolling**. Animate message entry once. Update one assistant row as text arrives and follow the bottom while the reader stays near it. Scrolling away suspends following. Reduce Motion removes entry and scroll animation while preserving updates.
- **History switching**. Starting or selecting another conversation stops the current stream. Only events for the active conversation and request can update its reply. Returning to a stopped thread shows the partial answer. Navigating away from Chat keeps the selected thread in the app session.

## Stream producer

The input is a conversation ID, request ID, question, and mode-specific context. The producer yields cumulative displayable assistant text, then signals completion, cancellation, or failure. The coordinator owns field validation, the UI state machine, and writes. Preview uses canned responses with an injectable clock. Its normal reply includes a short pause. The fictional question `Simulate a stream error` selects a known failure after partial text. The on-device producer follows the same update contract. The live coordinator may reject or replace an ungrounded final draft.

## Local retrieval tools

| Tool | Input | Output |
| --- | --- | --- |
| `searchMeetings` | Short terms and optional explicit date range, tags, or invitee names. The app reapplies the selected scope. | Bounded canonical meeting identifiers and concise calendar or meeting metadata. |
| `searchTranscript` | Short terms and optional candidate meeting IDs. Intersect candidates with current scope. | Ranked passages with short text, channel labels, and request-local citation IDs. |

Bind SQL parameters, quote FTS tokens, reject unusable arguments, and cap the number of lookups and returned evidence. Start with a cap of four calls and a roughly 2,000-token evidence budget per turn, and tune against the supported model and real fixtures. Carry forward only bounded recent turns relevant to the current scope. Do not follow instructions in retrieved metadata or passages. Giving the model shell, network, writes, and arbitrary SQL is outside this interface.

Validate cited IDs against evidence from the request and recheck their source revision before displaying links. Selecting a live citation opens the Meeting on **Transcription** and reveals the source passage. Show an unavailable state if the source changed or disappeared. Render a limitation or a clarification request when evidence is insufficient.
