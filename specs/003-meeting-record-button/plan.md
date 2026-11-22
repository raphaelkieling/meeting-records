# Implementation Plan — Meeting Recording

**Branch** — `main` · **Spec** — [Meeting Record Button](spec.md)

## Summary

Implement option E with live audio feedback and local recording. Record microphone and computer audio separately, save both progressively, and show each Recording under Inputs. Transcription displays an empty state during this delivery.

## Technical Context

- Swift 6, SwiftUI, Apple Silicon macOS 14+, ScreenCaptureKit, AVFoundation, and the existing SQLite store.
- Store audio files beneath the app's existing Application Support directory. Keep Recording metadata and the audio index in SQLite. Use the same data root for both, including debug overrides.
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

See [research](research.md), [data model](data-model.md), and the [UI contract](contracts/ui-contract.md).
