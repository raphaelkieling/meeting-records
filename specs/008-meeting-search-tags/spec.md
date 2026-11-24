# Feature Specification: Meeting Search, Tags, and Descriptions

**Feature Branch**: `008-meeting-search-tags`

**Created**: 2026-11-23

**Status**: Draft

**Input**: User description: "Add a search button below Home with a plain text search field that searches across meetings, plus an easy way to add shared tags to meetings and filter meetings by multiple tags."

## User Scenarios & Testing

### User Story 1 - Find Meetings by Text (Priority: P1)

As a user, I want to search meeting titles, descriptions, transcripts, and tag names from a dedicated search view so I can find a meeting by something I remember from it.

**Why this priority**: Text search provides value immediately, including for meetings that have not been tagged.

**Independent Test**: Create meetings with distinct titles, transcript passages, and tags. Open Search, type a matching term, and verify that each matching meeting appears with a useful transcript excerpt when the transcript matched.

**Acceptance Scenarios**:

1. **Given** meetings have titles, descriptions, transcripts, or tags containing a term, **When** the user types that term in Search, **Then** matching meetings appear as the query changes.
2. **Given** a meeting matches within its transcript, **When** it appears in the results, **Then** the result includes a relevant transcript excerpt.
3. **Given** a meeting has a description, **When** it appears in the results, **Then** the description appears beneath its title.
4. **Given** no meeting matches the current text, **When** the user searches, **Then** the view communicates that there are no matching meetings.

### User Story 2 - Organize Meetings with Shared Tags (Priority: P1)

As a user, I want to assign reusable, colored tags to meetings so I can organize related meetings consistently.

**Why this priority**: Tags provide the organization and filtering capability that makes the search view especially useful for recurring categories such as work and 1:1 meetings.

**Independent Test**: Open a meeting's context menu, choose Tags, assign an existing tag, create a tag with a palette color, confirm, and verify its label and tag icon in the sidebar. Assign the same tag to another meeting and verify its color is consistent.

**Acceptance Scenarios**:

1. **Given** a meeting is visible in the sidebar, **When** the user opens its context menu and chooses Tags, **Then** a modal shows its currently assigned tags.
2. **Given** the Tags modal is open, **When** the user selects or deselects existing tags and confirms, **Then** the meeting's assignments are saved.
3. **Given** the Tags modal is open, **When** the user creates a new tag and chooses a predefined color, **Then** that shared tag becomes available for assignment to other meetings.
4. **Given** a meeting has one or more tags, **When** it appears in the sidebar, **Then** a tag icon appears on the right side of its row.

### User Story 3 - Filter Meetings by Tags (Priority: P1)

As a user, I want to select multiple tags as filters so I can narrow the list to meetings that have all selected tags.

**Why this priority**: Combining tags with AND supports focused searches such as meetings tagged both work and 1:1.

**Independent Test**: Create meetings with different combinations of two tags, select both tags in Search, and confirm that only meetings with both tags remain.

**Acceptance Scenarios**:

1. **Given** the user selects multiple tags, **When** the results update, **Then** only meetings containing every selected tag appear.
2. **Given** the user has entered text and selected tags, **When** results update, **Then** a meeting appears only if it matches the text and contains every selected tag.
3. **Given** no tags are selected, **When** the user searches by text, **Then** tag filtering does not exclude text matches.
4. **Given** the text field is empty and tags are selected, **When** results update, **Then** all meetings with every selected tag appear.

### User Story 4 - Describe a Meeting (Priority: P2)

As a user, I want to add or update an optional description for a meeting so I can remember its purpose and find it later.

**Why this priority**: Descriptions add context to meetings and become another searchable way to find them, while title, transcript, and tag search remain useful without descriptions.

**Independent Test**: Add a description from a meeting's context menu, confirm it appears beneath the meeting title and in search results, and find the meeting by searching a distinctive description phrase.

**Acceptance Scenarios**:

1. **Given** a meeting has no description, **When** the user chooses Edit Description and saves text, **Then** the description is shown beneath the meeting title and in Search results.
2. **Given** a meeting has a description, **When** the user edits and saves it, **Then** the new text replaces the old description and is searchable.
3. **Given** the user edits a description, **When** they cancel, **Then** the previously saved description remains unchanged.
4. **Given** a meeting has no description, **When** it appears in Search results, **Then** no blank description placeholder is shown.

### Edge Cases

- A meeting may have no tags; its sidebar row does not show a tag icon.
- A meeting may have an empty description; search and meeting views remain usable without it.
- Cancelling a description edit preserves its last saved value.
- A newly created tag must have a non-empty name and one color from the predefined palette before it can be saved.
- A tag may be assigned to many meetings and must use the same selected color everywhere.
- When a tag is deselected in a meeting's Tags modal, it is removed from that meeting but remains available as a shared tag.
- With empty search text and no selected tags, the dedicated Search view shows an instructional empty state rather than implying that meetings are missing.
- Search matches may come from multiple fields in one meeting; the meeting appears only once.
- Search remains usable with a large meeting collection and does not make recording or normal navigation unresponsive.

## Requirements

### Functional Requirements

- **FR-001**: The sidebar MUST provide a Search entry below Home that opens a dedicated search view.
- **FR-002**: The search view MUST provide a plain text field and a multi-select tag filter positioned to its right.
- **FR-003**: Text search MUST find matches in meeting titles, descriptions, available transcript text, and tag names.
- **FR-004**: Search results MUST update as the user types without requiring a separate submit action.
- **FR-005**: Search results MUST list each matching meeting once and MUST show a relevant transcript excerpt when the match is in transcript text.
- **FR-006**: Text search and selected tag filters MUST be combined with AND semantics.
- **FR-007**: When multiple tags are selected, a meeting MUST match every selected tag to appear.
- **FR-008**: The tag filter MUST allow the user to select and clear multiple shared tags.
- **FR-009**: A meeting's context menu MUST include a Tags action that opens a modal showing its assigned tags and the available shared tags.
- **FR-010**: The Tags modal MUST allow the user to assign existing tags, remove assignments, and confirm or cancel changes.
- **FR-011**: The Tags modal MUST allow creating a shared tag with a non-empty name and a color selected from a predefined palette.
- **FR-012**: A shared tag MUST retain its name and color consistently across all meetings to which it is assigned.
- **FR-013**: A meeting row in the sidebar MUST show a tag icon on its right side when that meeting has at least one tag.
- **FR-014**: Tag assignments and shared tag definitions MUST persist locally across app restarts.
- **FR-015**: Search MUST remain responsive during recording and ordinary app navigation, including for a large collection of meetings.
- **FR-016**: The search view MUST communicate when the current text and tag filters produce no matching meetings.
- **FR-017**: A meeting MUST have an optional plain-text description that users can create and update independently of its title.
- **FR-018**: The meeting's context menu MUST provide an Edit Description action with explicit save and cancel behavior.
- **FR-019**: A saved description MUST appear beneath the meeting title in its detail view and beneath the title in search results when non-empty.
- **FR-020**: Description edits MUST persist locally across app restarts and MUST NOT alter a meeting's recordings or transcripts.

### Key Entities

- **Tag**: A reusable label with a name and one predefined color, shared across meetings.
- **Meeting Tag Assignment**: The association between a meeting and a shared tag.
- **Meeting Description**: Optional plain text that describes a meeting and is editable independently of its title.
- **Meeting Search**: A text query and zero or more selected tag filters used to find matching meetings.
- **Search Result**: A matching meeting, optionally accompanied by a transcript excerpt that contains the text match.

## Success Criteria

### Measurable Outcomes

- **SC-001**: For every unique title, description, transcript, or tag term in the acceptance dataset, Search returns the matching meeting exactly once without requiring the user to open other meetings.
- **SC-002**: For a collection of 1,000 meetings, search results update within 1 second after typing pauses, for at least 95% of searches on a supported Mac.
- **SC-003**: Users can assign an existing tag or create and assign a colored tag to a meeting in under 30 seconds.
- **SC-004**: Selecting two or more tags returns only meetings containing all selected tags, with no incorrect matches in the acceptance dataset.
- **SC-005**: Adding tags and searching do not interrupt an active recording or prevent normal navigation.
- **SC-006**: Users can add or update a meeting description and find it in Search in under 30 seconds.

## Assumptions

- Search is local and works offline, consistent with the product's local-first behavior.
- Meeting descriptions are optional plain text and are edited from a meeting's context menu; empty descriptions are allowed.
- Text matching is case-insensitive and supports partial terms; a dedicated query language is not part of this feature.
- Transcript search covers transcript text currently available to the app; it does not trigger a new transcription.
- Newly created tags remain in the shared tag list even if later removed from every meeting; global tag deletion and renaming are outside this feature.
- The predefined color palette is small, fixed, and chosen by the product; users select one color when creating a tag.
- Search results follow existing meeting navigation behavior when opened.
