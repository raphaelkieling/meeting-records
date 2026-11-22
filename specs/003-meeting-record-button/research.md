# Recording Research

## Capture and permissions

**Decision** — Use ScreenCaptureKit with a display filter and only an audio output for Other. Enable audio, exclude Meeting Record's own process, and persist only audio. Use an AVFoundation audio capture session for Me. Request microphone access after the user starts recording and explain the macOS screen-recording permission required for computer audio. Check app-bundle signing and the microphone usage description and entitlement on the existing launch path.

**Rationale** — This keeps one capture path on macOS 14.0 and retains separate streams. Verify both permissions, whether macOS requires an app restart after granting access, and audio-only capture before wiring the UI. [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) · [Audio configuration](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/capturesaudio) · [Microphone authorization](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media)

**Alternatives considered** — ScreenCaptureKit's combined microphone support requires macOS 15. Core Audio process taps require macOS 14.2 and an aggregate device. [Combined capture sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos) · [Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)

## Alignment

**Decision** — Convert each buffer's presentation timestamp to the Core Media host clock from its source synchronization clock. Store offsets from a common session start.

**Rationale** — Each capture API exposes its clock. Common timestamps preserve overlap and gaps across callbacks. Verify startup offset and drift with a known signal on the reference Mac. [ScreenCaptureKit clock](https://developer.apple.com/documentation/screencapturekit/scstream/synchronizationclock) · [AVFoundation clock](https://developer.apple.com/documentation/avfoundation/avcapturesession/synchronizationclock)

**Alternatives considered** — Callback arrival times incorporate scheduling and queue delays. Mixing the audio would discard source separation.

## Persistence

**Decision** — Write local PCM CAF checkpoints and keep their index and recording state in SQLite. Start with five-second checkpoints.

**Rationale** — Independently readable files let the app recover published audio after an interrupted write, with bounded buffering and no codec dependency. Measure disk growth and recovery on the reference Mac.

**Alternatives considered** — A file written only at Stop risks losing the session. A single long-running file per source requires a reliable repair path when finalization is interrupted. Audio blobs would couple large sequential audio writes to Meeting metadata.
