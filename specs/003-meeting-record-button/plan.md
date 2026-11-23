# Implementation Plan — Meeting Recording

**Branch** — `main` · **Spec** — [Meeting Record Button](spec.md)

## Summary

Implement option E with live audio feedback and local recording. Record microphone and computer audio separately, save both progressively, and show each Recording under Inputs. Transcription displays an empty state during this delivery.

Show each saved Recording as a compact card with the title on the left, Play in the top-right corner, and the recording date in the bottom-right corner. The same button becomes Stop during playback. Starting another card stops the previous one. Playback ends when the user leaves that Meeting's Inputs view, so Stop stays available while audio plays.

## Technical Context

- Swift 6, SwiftUI, Apple Silicon macOS 14+, ScreenCaptureKit, AVFoundation, and the existing SQLite store.
- Store audio files beneath the app's existing Application Support directory. Keep Recording metadata and the audio index in SQLite. Use the same data root for both, including debug overrides.
- Use AVFoundation to play the original Me and Other clips on their shared recording timeline. Mix during playback using the stored segment offsets, preserving overlap and gaps without writing another audio file. Include available audio from interrupted Recordings. Read long recordings incrementally.
- Keep capture and disk writes off the UI thread. Bound buffering and surface write or capture failures. Start with a five-second checkpoint interval and verify it on the reference Mac.
- Validate storage and recovery with Swift tests. Validate permissions, both audio sources, alignment, navigation, and motion in the native app.

## Constitution Check

- **Before research** — Local-only capture, progressive persistence, source preservation, and separate Me and Other tracks are required. This delivery covers the recording portion of the [product acceptance criteria](../../PRODUCT.md). Model selection and transcription acceptance belong to the subsequent slice before the initial product release.
- **After design** — Two timestamped tracks preserve overlap and provide a reconstruction path. Completed checkpoints survive a process exit. The [validation guide](quickstart.md) covers the risks this slice introduces, including explicit permission, interruption, and offline use.

## Project Structure

Reuse the SwiftUI shell and `MeetingStore`. Add one app-scoped capture coordinator and keep file persistence beside the existing store. Update app permission messaging in `Resources/Info.plist`. Keep storage verification in `Tests/MeetingRecordTests`.

## Delivery Order

1. Prove simultaneous capture and timestamp alignment on the target Mac, including permissions and digital audio with headphones.
2. Add progressive writes, the SQLite migration, and restart reconciliation. Verify normal stop, interruption, and write failure.
3. Connect the approved floating control, live levels, sidebar state, and Inputs list. Run native validation.
4. Add the Inputs cards and single-item playback. Validate alignment, Play/Stop, switching cards, and natural completion using saved test recordings.

See [research](research.md), [data model](data-model.md), and the [UI contract](contracts/ui-contract.md).
