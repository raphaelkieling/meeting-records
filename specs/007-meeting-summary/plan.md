# Plan: Meeting Summary

Add a native SwiftUI tab backed by an app-owned coordinator. Load the saved result and check transcript readiness when the tab opens. Start generation only on button activation and only when the meeting has transcript text and all its recordings have finished transcription. Keep in-flight requests scoped to their meeting across navigation.

Read the transcript in a SQLite snapshot, derive a revision from its ordered contents, and save the latest successful summary in a table that cascades on meeting deletion. Compare the saved revision to the current transcript when displaying the result.

Use the on-device System Language Model through Foundation Models on macOS 26 and later. Summarize chronological sections and merge them when the transcript exceeds the context window. Keep the rest of the app usable on older systems.
