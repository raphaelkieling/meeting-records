# Meeting Chat Validation

Run each section after its corresponding implementation increment. Use an Apple Silicon Mac. Use a compatible Xcode and an isolated test library for live fixtures. Record the model, macOS version, and observations when evaluating live retrieval.

## Implementation validation on 2026-11-24

- Baseline on Apple Silicon macOS 27.2.1 and Xcode 27.2 passed 31 tests before the chat changes.
- Native preview in an isolated app and database showed the newest sample thread, a red right-aligned user bubble, incremental assistant Markdown, History selection, keyboard send, and bottom following on a long conversation. Automated preview tests covered Stop, stale callbacks, and partial errors. Reduce Motion and scrolling away during an active stream remain manual checks.
- The app-linked SQLite tests exercised indexing, accent-insensitive retrieval, scope, citation validation, stale revision replacement, migration, restart recovery, and deletion of dependent replies. Testing on a macOS 14 runtime remains open.
- The installed on-device model reported that it was still preparing. Real generation, native citation navigation, multilingual model quality, real-history relaunch, and impact during active capture remain unverified.

```sh
xcrun swift test --disable-sandbox --cache-path .build/cache --manifest-cache local
./run
```

## 1. Preview

1. Disable networking. Open **Chat** below **Search** on a Mac without a configured chat model. Verify the Preview label and select both sample threads in **History**.
2. Choose **New Chat**, type a multiline question, and send it. Verify the right-aligned red bubble appears immediately. Watch a single left-aligned response stream across headings, lists, and a code fence. No parts of the response should appear twice.
3. Scroll up during streaming. Verify the scroll position stays put. Return to the bottom and verify it follows updates. Switch to another thread mid-stream, return, and confirm only the original partial reply remains. Try Stop, then send `Simulate a stream error` and verify that you can send again after the error.
4. Test keyboard navigation, Reduce Motion, light and dark appearance, and a narrow window. Confirm the streaming text remains readable and the composer stays reachable. Navigate Home and back, then relaunch. The selected preview remains within the session and the next launch opens only fresh fixture state.

## 2. Live retrieval and citations

1. On a Mac with Apple Intelligence available and prepared, seed an isolated library with completed recordings in Portuguese, Spanish and English, a mixed-language passage, and similarly titled distractors. Give the relevant meetings different dates, labels, or invitees. Record the expected source passage for each question.
2. Disconnect networking. Ask a question about a decision, then ask who owned the follow-up without repeating the question. Verify that the app shows grounded answers, with a usable limitation when the transcript does not establish identity.
3. Ask again in single-meeting scope, including a case where evidence is outside the scope. Click a citation with valid evidence and verify the selected recording and passage match the reference time. Retry with punctuation and unaccented terms. Track paraphrase and cross-language misses.
4. Delete or retranscribe a source and verify stale results and citations do not resolve. Confirm the app-linked FTS5 probe on macOS 14 while testing Preview there. Exercise the unavailable-index and unavailable-model states. During live indexing and generation, start and stop a recording and verify that its saved audio and transcript queue remain consistent.

## 3. Saved history

1. Generate a complete answer and stop a second one after text appears. Relaunch and verify history order, complete and stopped states, and clickable valid citations.
2. Quit during a third stream. Reopen the saved thread and verify that the last persisted text is labelled interrupted and generation remains idle.
3. Delete one source meeting used in a reply and a later follow-up. Verify both assistant bodies are cleared and the user questions remain. Repeat with Delete All Meetings while a reply is generating. Ensure late snapshots cannot restore cleared text.
4. Delete a chat thread, relaunch, and verify the thread and its evidence references remain absent.
