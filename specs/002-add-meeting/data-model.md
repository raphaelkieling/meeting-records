# Data Model: Meeting Creation and Rename

## Persisted Meeting

| Field | Representation | Rule |
| --- | --- | --- |
| id | Canonical UUID string / Swift UUID | Stable primary identity; never derived from name or position. |
| name | UTF-8 text / Swift String | Trim user input; non-empty, no embedded NUL; allow Unicode, punctuation, duplicate and long names. |
| createdAt | REAL epoch seconds / Date | Finite; preserved on rename and migration. |
| updatedAt | REAL epoch seconds / Date | Finite; established on create and advanced only on successful changed writes. |

No Input or Transcription record is created. The Transcription tab is an empty presentation of the Meeting workspace, not a persisted transcript.

## Schema lifecycle

- v0: Initialize a fresh database at v2 using the existing transactional approach; conflicting unexpected schema fails without erasing it.
- v1: Validate historical rows/schema first; in one transaction add updatedAt with non-null constant default, backfill from createdAt, then set user_version to 2. Preserve IDs, names, createdAt, and row count.
- v2: Load using the new fields and validate their types/finite values. Do not rewrite names or timestamps merely on load.
- Other versions: Reject without destructive recovery. Malformed databases/rows fail explicitly.

Legacy whitespace-valid names are preserved byte-for-byte during migration. New create/rename input rejects embedded NUL; migration does not silently clean historical data. Rollback must leave schema version and rows intact on failed upgrade.

## Ordering and write rules

Load with `ORDER BY updatedAt DESC, id ASC`. Use the same comparator in memory with canonical UUID strings. For each actual write, inside BEGIN IMMEDIATE compute an effective timestamp greater than every current updatedAt and no earlier than wall-clock now. Use Double.nextUp for equal/backward clock values and reject non-finite values. New creation sets both createdAt and updatedAt to this effective timestamp; rename preserves createdAt.

A no-op normalized rename returns the original record without advancing timestamps. Errors and cancellation never affect recency. There is no rowid ordering, sequence column, or global mutable in-memory clock.

`createMeeting(id:name:)` uses a caller-generated UUID for one logical creation; if the ID already exists, return its saved record without overwriting it. Bind all values in prepared statements. `renameMeeting(id:name:)` requires an existing UUID and validates the normalized name. Mutation operations return their affected record only after commit; do not attach a fallible post-commit reload to the result.

## Transient state

- Saved list and Destination remain owned by ContentView. Destination.meeting(UUID) survives list reordering.
- Rename session: UUID, origin (sidebar or header), draft, optional error. One active session globally; the other surface shows saved text until success.
- Mutation status: idle, creating, or saving rename. Prevent overlapping requests and double commit from Enter plus focus loss.
- Pending action: destination change, creation, or another rename. Continue once after successful commit/no-op; invalid/save failure keeps the current editor and destination. Escape cancels the draft and pending action.
- On success merge the committed Meeting into the saved list, sort, clear the editor/error, and restore appropriate focus to that UUID. On failure retain saved data and draft, expose retry/cancel.

## Relationships and transitions

One Meeting has one navigation row and one main title displaying the same saved name. The sole Transcription tab is selected whenever that Meeting opens. No durable tab-selection state is required.

Creation: idle → pending → saved/selected, or error with original list/selection.
Rename: display → editing → saving → display with committed name; invalid/save failure → editing with draft/error; Escape → display with original saved name.
