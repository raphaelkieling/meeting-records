# Data Model

| Entity | Relevant data | Rules |
| --- | --- | --- |
| Microphone sensitivity | Normalized threshold in the range 0...1 | Local user preference. The default preserves the current near-silence behavior. Applies only to Me audio submitted for transcription. |
| Microphone input level | Normalized short-window RMS level | Live value shown in Settings on the same scale as the threshold. |
| Audio checkpoint | Recording ID, source, timeline offset, frames, media path | Persist every approximately ten seconds per source. Existing shorter checkpoints remain readable. |
| Transcription window | Recording ID, source, first offset, last offset, selected audio intervals | Combine adjacent checkpoints for one source. Preserve original offsets and a small margin around threshold-qualified intervals. Never combine Me and Other. |
| Transcript progress | Recording ID, source, checkpoint key, processed-through offset | Advance through every checkpoint represented in a submitted window only after saving its result. Preserve retry and completion behavior. |

## Processing invariants

- Audio is persisted before transcription decisions. The threshold does not remove or rewrite stored CAF files.
- A window that has no qualifying Me intervals returns empty text and still advances progress through the audio it considered.
- Windows preserve the common recording timeline. Segment timestamps are mapped back to original offsets, including gaps created by the gate.
- A stopped or recovered recording is complete only after all saved checkpoints, including a final partial checkpoint, have been processed.
