# Data Model: Meeting Search and Tags

## Meeting

An existing meeting, with an optional user-authored description.

| Field | Type | Rules |
|---|---|---|
| ID | Stable identifier | Existing identity; unchanged by this feature. |
| Name | Text | Existing non-empty meeting title. |
| Description | Optional plain text | Empty or absent descriptions are allowed. Editable independently of the title. |
| Tags | Tag collection | Derived from the shared meeting/tag assignments; each assigned tag appears once. |
| Created at | Date and time | Existing creation time. |
| Updated at | Date and time | Existing update time; update when the name or description changes. |

Descriptions are shown below the meeting name in the meeting detail view and under the name in search results when non-empty. They participate in text search.

## Tag

A reusable label shared across meetings.

| Field | Type | Rules |
|---|---|---|
| ID | Stable identifier | Unique within the local database. |
| Name | Text | Trim surrounding whitespace; must be non-empty; normalized names are unique without regard to case. |
| Color | Palette token | One value from the fixed predefined palette; the token identifies the display color. |

Tags remain available after all meeting assignments are removed. Renaming and global deletion are outside this feature.

## Meeting Tag Assignment

The many-to-many association between a meeting and a shared tag.

| Field | Type | Rules |
|---|---|---|
| Meeting ID | Meeting reference | Required; removed when the meeting is deleted. |
| Tag ID | Tag reference | Required; tag definition is retained when an assignment is removed. |

The same meeting/tag pair may be assigned only once.

## Search Query

Ephemeral state for the active Search view.

| Field | Type | Rules |
|---|---|---|
| Text | Text | Plain text, case-insensitive partial matching against meeting name, description, transcript text, and tag name. |
| Selected tag IDs | Set of tag IDs | Zero or more; every selected tag must be assigned to a result meeting. |

When both text and tags are present, a result must match the text and all selected tags. Search query state is not required to persist across app restarts.

## Search Result

A derived view of one matching meeting.

| Field | Type | Rules |
|---|---|---|
| Meeting | Meeting | One result per meeting, even when several fields match. |
| Assigned tags | Tags | The meeting's current shared tag assignments. |
| Transcript excerpt | Optional text | Relevant nearby text when the transcript contains the query. |

## Persistence and migration

The next additive database migration adds the optional meeting description column and creates shared tag and meeting/tag assignment records. Existing meetings receive an empty description. Existing recording and transcript records remain intact. Meeting deletion removes assignments through the existing meeting deletion flow but preserves tag definitions.
