# Data Model

| Entity | Relevant data | Rules |
| --- | --- | --- |
| Meeting | ID, current name, creation time | Select the newest three by creation time with a stable ID tie-break. Each Meeting appears once. |
| Recording | ID, Meeting ID, start time, finalization state, saved clips | A saved recording has finalized or recovered audio. The latest one in Inputs is selected by start time with a stable ID tie-break. |
| Audio segment | Recording ID, source, timeline offset, media duration | The recording duration is the maximum segment endpoint across the two tracks. Aggregate one duration per saved recording and format after summing. |
| Transcript job | Recording ID, status | Each saved Recording with a Complete job contributes one to the count. A silent recording can have a Complete job. |
| Pending Meeting file deletion | Meeting ID | One durable entry per deleted Meeting, created in the database deletion transaction. Clear the entry when the managed Meeting directory is gone. |

## Reads and refreshes

Read the recent Meetings, saved Recording IDs and completed count against a consistent library snapshot. Resolve uncached recording durations from existing clip metadata outside the main actor. Coalesce overlapping refresh requests and publish only the latest result. Discard cached durations for removed recordings. Treat an unreadable saved duration as unavailable and offer retry.

## Deletion lifecycle

1. Check that the target has no starting, active or finishing capture. Block new capture for that target while deletion is in progress and enforce the persisted open-recording check inside the store transaction.
2. Within the transaction, delete its recording rows and Meeting row, allowing existing cascades to remove audio and transcript metadata. Insert one cleanup entry. Rollback leaves the Meeting and files intact.
3. Once committed, remove the managed directory for that Meeting UUID. If it is already absent, cleanup succeeds. Keep the cleanup entry on failure and retry safely. A migration adds the cleanup table and preserves existing library data.
4. Skip a queued job if its Recording disappeared before the worker claims it. Ignore a late result if the job no longer exists. Check job existence and write the result in the same store transaction so the worker can continue with other Meetings.
