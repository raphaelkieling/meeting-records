# Quickstart: Audio Transcription Validation

## Prerequisites

- Apple Silicon Mac; baseline used for performance measurements: M4 Max, 36 GB memory, macOS 27.2.1.
- A model candidate installed explicitly for the evaluation. Model downloads are not required for build-only validation.
- Consent to record all people whose audio is in the evaluation clips. Keep private recordings and reference transcripts outside the repository.

## Build and launch

```sh
swift test
./run
```

## End-to-end scenarios

1. In Settings, review the chosen model and its download size, explicitly download it, and confirm progress and Ready state.
2. Disconnect from the internet. Record a Meeting and confirm transcript text appears during capture. Check that the corresponding Input badge progresses Pending → Transcribing → Complete after stop and backlog drain.
3. Play back the Meeting's unified Transcription. Confirm each passage appears once, in Input order, with its source Input, Me/Other label, timestamp, and overlap retained.
4. Record twice in one Meeting. Confirm both Input badges are independent and the Transcription tab contains both results in recording order.
5. Close the app during a recording. Reopen it and confirm capture stays stopped, the persisted audio remains a separate Input, unfinished transcription resumes from its checkpoint, and another capture starts only after an explicit action.
6. Repeat with transcription slowed or unavailable. Confirm recording and disk writes continue, captured audio is not lost, the queue remains bounded in memory, and pending transcription drains after capture stops or the model becomes available.
7. Run a 60-minute dual-track recording and continue navigating the Meeting. Confirm no capture-overrun error or missing audio, then record backlog drain time.

## Model quality and performance review

Use the same corrected sample set for Qwen3-ASR-1.7B and WhisperKit large-v3 candidates. Include Brazilian Portuguese, Spanish, English, language switching, overlap, quiet speech, and background noise. Record WER/CER by language, language-ID accuracy, correction time, timestamp quality, model load time, peak memory, thermal behavior, transcript update delay, real-time factor, queue depth, and audio capture errors. Choose the highest-quality candidate that meets the capture and responsiveness guardrails in [research.md](research.md). Do not commit private audio or full reference transcripts.

Use a Release build for profiling. Capture Time Profiler and Swift Concurrency Instruments traces while ASR and both tracks are active. Verify inference does not execute on `MainActor`, the AV capture callback queue, or the durable storage actor. See [the data model](data-model.md) and [UI contract](contracts/ui-contract.md) for expected persisted and visible states.
