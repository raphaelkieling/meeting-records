# Research for Meetings Home

## Refresh from committed changes

**Decision**: Read recent Meetings and library totals from local storage. Refresh on Home entry and after committed Meeting mutations, recording finalization or recovery, and transcription completion. Reuse the existing recording and transcription coordinators to signal those events.

**Rationale**: ContentView owns Meeting mutations. RecordingCoordinator publishes a revision after recovery and finalization. TranscriptionCoordinator publishes when finishDrainedTranscripts changes durable state. These are existing points where the library is ready to read. Home can skip transcription progress events that cannot affect its count.

**Alternatives considered**: Polling and persisted library-wide counters add ongoing work and more state to reconcile after deletion or recovery.

## Use the saved playback duration

**Decision**: Calculate each finalized recording's duration from the end of its saved audio timeline. Use the checkpoint offset and media duration to find the latest endpoint across both sources. Cache successful per-recording calculations for the app session.

**Rationale**: RecordingPlayback uses those offsets and media ranges to place each clip. AudioSegment stores frame count without sample rate, so stored frame counts alone are insufficient. RecordingStorage can set the end timestamp at recovery, after capture has already stopped. Reading saved media metadata also works for libraries created before this feature.

**Alternatives considered**: Wall-clock differences inflate recovered recordings. Adding the durations of both sources double-counts overlapping time. A persisted duration cache would require extra migration and backfill logic.

## Delete one Meeting and reclaim its files

**Decision**: Delete the target's recording rows and Meeting row in one SQLite transaction and record pending file cleanup in that transaction. Remove the Meeting's directory from the managed Recordings root after commit. Retry pending cleanup on startup or when the user retries a reported failure.

**Rationale**: RecordingStorage scopes files under the Meeting UUID. MeetingStore already cascades audio and transcription data when recordings are deleted, while the recordings foreign key to Meetings requires explicit removal. The durable cleanup record lets the app finish file removal after a crash without leaving a visible Meeting with missing audio. A target with an open recording is ineligible. A stale claim or late result for a removed job can be skipped at the store boundary so the worker can continue.

**Alternatives considered**: Removing files first can leave an intact Meeting with missing audio if the database operation fails. Deleting the database rows and files without a durable cleanup record can leave orphaned audio after an interrupted operation.
