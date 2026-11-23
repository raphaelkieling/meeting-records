# Transcription Data Model

## Audio Input

The source audio belonging to a Meeting. For the current feature, a Recording is the concrete Input; the model accepts an imported-audio Input through the same identity and audio-source contract when import is available.

- `id`: Stable Input identifier; a Recording uses its existing Recording ID.
- `meetingID`: Owning Meeting.
- `kind`: Recording or imported audio.
- `createdAt` / `endedAt`: Input order and source timing. An active Recording has no `endedAt`.
- `audioSources`: One or more local audio sources. A Recording has separate Me and Other tracks with offsets on the common recording timeline.
- `recordingState`: Existing capture lifecycle (`starting`, `recording`, `completed`, `interrupted`); remains independent from transcription status.

An active Recording is visible in Inputs so the user can see its transcription badge while it is being captured. On app relaunch, an unfinished capture is recovered as an interrupted Input; audio capture is never resumed automatically.

## Input Transcript Job

One processing lifecycle per Audio Input.

- `inputID`: Stable identifier of the source Input.
- `meetingID`: Meeting that owns the unified transcript.
- `status`: `Pending`, `Transcribing`, or `Complete`.
- `processedThrough`: Last durably transcribed offset per audio source, used to resume after app closure without repeating completed work.
- `modelID` / `modelVersion`: Model asset used to produce the current result.
- `lastError`: Optional local reason that processing remains Pending; does not replace the three user-facing statuses.
- `updatedAt`: Last persisted lifecycle or transcript change.

### Status transitions

```text
Pending → Transcribing → Complete
    ↑            │
    └────────────┘ app closes or processing becomes unavailable
```

`Complete` is terminal for the current model version. On restart, interrupted work returns to Pending and resumes automatically when the model is available. New capture creates a new Input and a new job.

## Transcript Segment

Persisted text derived from a bounded section of one audio source.

- `id`: Stable segment identity for updates and deduplication.
- `inputID`: Source Input.
- `audioSource`: `Me`, `Other`, or the available source label for imported audio.
- `startOffset` / `endOffset`: Time within the source Input.
- `text`: Current recognized words.
- `revisionState`: Provisional or final; a model may replace the latest provisional segment as more context arrives.
- `sequence`: Stable ordering when timestamps are equal or overlap.

Segments from Me and Other may overlap. Within one Input, the unified view orders them by start offset, retaining both passages. The Meeting view concatenates Input results in existing Input order; it does not re-transcribe or store a duplicate combined copy.

## Local Transcription Model

The single model selected for this release.

- `modelID` / `version`: Exact asset used for processing.
- `assetLocation`: Local model bundle after installation.
- `downloadSize`: Bytes shown before explicit download.
- `installationState`: Not installed, downloading, ready, or unavailable.
- `downloadProgress`: Current downloaded bytes while setup is active.

Audio and transcript data remain local. If setup or inference is unavailable, the Audio Input and its existing text are preserved and the job remains Pending.

## Persistence and migration

The current SQLite schema is version 3 and already persists Meetings, Recordings, and Audio Segments. Add the smallest migration needed for per-Input jobs and transcript segments; preserve every existing Recording and checkpoint. Use stable IDs and idempotent writes so a restart cannot duplicate segments. A future import implementation can register its Input identity with the same transcription contract without changing the transcript semantics. Deleting an Input or Meeting removes its jobs and transcript segments together with its source audio.
