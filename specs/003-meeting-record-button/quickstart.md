# Recording Validation

Use an Apple Silicon Mac with macOS 14 or later, Swift 6, headphones, and a local audio clip. Run `swift test` and `./run` from the repository root after implementation. For a debug build use `MEETING_RECORD_DATA_DIR` with an absolute scratch path. Use disposable Meetings for interruption checks.

1. Create a Meeting. Grant microphone and the macOS screen-recording permission required for computer audio. Start from Inputs, speak into the microphone while playing the clip, switch to Transcription, and stop. Verify the expanded control and white audio waves while recording. Verify that Transcription stays empty.
2. Start again and open a second Meeting. Verify its Record action is disabled and the active sidebar row shows its indicator. Return via that row and stop. Reopen the app and verify two distinct Recordings in order.
3. Inspect the saved tracks. Play the CAF segments with `afplay <segment.caf>`. With headphones, verify microphone speech in Me, clip audio in Other, and overlapping events on the same recording timeline. Measure source offset and drift over a 10-minute run and record the checkpoint loss observed in the next step.
4. Force Quit during a disposable recording after several checkpoints. Reopen twice and confirm one Interrupted entry, playable published segments, and no duplicate index rows. Check a denied permission and a simulated write failure in a disposable data root. Confirm an idle UI after failure and preservation of earlier audio.
5. Repeat offline and with Reduce Motion enabled. Verify keyboard focus, VoiceOver labels, and the static recording indicator.
