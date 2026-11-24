# Research for Microphone Transcription Sensitivity

## Sensitivity should gate transcription audio, not capture

**Decision**: Keep recording all microphone input. Use a stored amplitude threshold only when the worker prepares Me audio for Whisper.

**Rationale**: The user's complaint concerns words hallucinated from low-level mic input. Gating before storage would delete the source audio and make tuning irreversible. The existing recorder already publishes a normalized peak level for the Me track, which can drive a Settings meter.

**Alternatives considered**: A speech-classifying VAD can distinguish speech from noise better than amplitude, but adds a model and calibration work. Noise suppression alters audio quality and can remove parts of soft speech. A threshold slider is the simple behavior requested and can be evaluated before adding those components.

## Ten-second context while preserving capture durability

**Decision**: Publish audio checkpoints every ten seconds and let the transcription worker combine adjacent saved checkpoints on the same source into a roughly ten-second work window when available. Keep source offsets and flush all remaining audio after stop or recovery.

**Rationale**: Each storage checkpoint currently covers about five seconds. Changing only the Whisper call does not create more context if the worker continues decoding each checkpoint separately. Batching at the work-selection boundary preserves durable checkpoints and lets the existing queue process them as one window.

**Alternatives considered**: Buffering ten seconds only in memory delays durable audio and risks loss on crash. Waiting for a long silence to close each window may stall transcription during uninterrupted speech. A rolling context window adds repeated decoding and deduplication complexity.

## Threshold measurement

**Decision**: Use a normalized short-window RMS level for gate decisions while keeping the existing peak display for the recording waveform. Retain a small margin around eligible audio and coalesce adjacent eligible audio before inference.

**Rationale**: RMS better represents sustained signal level than a single peak sample. A small margin protects quiet consonants at gate boundaries. The saved source remains the ground truth.

**Alternatives considered**: Peak-only gating can open on a click. Removing every sample below threshold can distort word beginnings and endings. Silent transcript output remains the fallback when no audio interval qualifies.
