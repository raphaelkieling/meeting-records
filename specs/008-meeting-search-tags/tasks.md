# Tasks: Meeting Search, Tags, and Descriptions

**Input**: Design documents from `specs/008-meeting-search-tags/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/search-ui.md`, and `quickstart.md`

**Tests**: No automated test tasks are included; the request did not ask to add tests. Validation scenarios are documented in `quickstart.md`.

**Organization**: Tasks are grouped by the four user stories in the feature specification.

## Phase 1: Setup

**Purpose**: Confirm existing project support before adding feature code.

- [X] T001 Confirm existing SwiftUI, SQLite, and XCTest project configuration is sufficient without new dependencies in `Package.swift`.

---

## Phase 2: Foundational

**Purpose**: Add shared meeting metadata and local persistence needed by every story.

- [X] T002 [P] Add optional `Meeting.Description` and derived `Meeting.Tags` to `Sources/MeetingRecord/Meeting.swift` as defined in `data-model.md`.
- [X] T003 [P] Define `Tag.ID`, `Tag.Name`, `Tag.Color`, `MeetingTagAssignment.Meeting ID`, and `MeetingTagAssignment.Tag ID` in `Sources/MeetingRecord/Tag.swift`, following `data-model.md` field constraints.
- [X] T004 Add the additive SQLite schema migration for `Meeting.Description`, shared tags, and meeting/tag assignments in `Sources/MeetingRecord/MeetingStore.swift`, preserving existing records and retaining unused shared tags per `data-model.md`.
- [X] T005 Add local read, create, assign, unassign, and update operations for descriptions and tags in `Sources/MeetingRecord/MeetingStore.swift`, enforcing `Tag.Name`, `Tag.Color`, and `MeetingTagAssignment.Meeting ID` and `MeetingTagAssignment.Tag ID` constraints from `data-model.md`.

**Checkpoint**: Existing meetings remain readable; descriptions, shared tags, and assignments can be stored locally.

---

## Phase 3: User Story 1 - Find Meetings by Text (Priority: P1) 🎯 MVP

**Goal**: Find meetings by title, description, transcript text, or tag name and inspect useful context in the results.

**Independent Test**: Search unique terms placed separately in a meeting title, description, transcript, and tag. Confirm each meeting appears once, transcript matches have an excerpt, and descriptions appear beneath matching meeting titles.

### Implementation

- [X] T006 [P] [US1] Define `SearchQuery` and `SearchResult` in `Sources/MeetingRecord/SearchModels.swift`, citing `SearchQuery.Text`, `SearchQuery.Selected tag IDs`, `SearchResult.Meeting`, `SearchResult.Assigned tags`, and `SearchResult.Transcript excerpt` in `data-model.md`.
- [X] T007 [US1] Implement local partial text matching and transcript excerpt selection in `Sources/MeetingRecord/MeetingStore.swift`, covering name, description, transcript text, and tag name per `SearchQuery.Text` and `SearchResult.Transcript excerpt` in `data-model.md`.
- [X] T008 [US1] Add the Search destination directly below Home and render its view through `Sources/MeetingRecord/SidebarView.swift` and `Sources/MeetingRecord/ContentView.swift`.
- [X] T009 [US1] Build option A in `Sources/MeetingRecord/SearchView.swift`: live search field, matching meeting rows, description, transcript excerpt, tags, date, and informative empty states; keep store work asynchronous and ignore stale results.

**Checkpoint**: Text search works from the sidebar and returns each matching meeting once with available context.

---

## Phase 4: User Story 2 - Organize Meetings with Shared Tags (Priority: P1)

**Goal**: Assign reusable palette-colored tags to meetings from the meeting context menu.

**Independent Test**: Open Tags for a meeting, assign an existing tag, create a tag with a palette color, save, and confirm the sidebar icon and consistent shared color. Cancel a separate edit and confirm it is not applied.

### Implementation

- [X] T010 [US2] Build `Sources/MeetingRecord/TagManagementView.swift` with current assignments, shared tag selection, palette-based tag creation, and explicit Save/Cancel behavior using the operations from `MeetingStore.swift`.
- [X] T011 [US2] Add the Tags context-menu action and a right-side tag icon for tagged meetings in `Sources/MeetingRecord/SidebarView.swift`, wiring modal state through `Sources/MeetingRecord/ContentView.swift`.

**Checkpoint**: Tags can be created once, assigned to several meetings, and persist locally with a consistent color.

---

## Phase 5: User Story 3 - Filter Meetings by Tags (Priority: P1)

**Goal**: Combine text and multiple selected tags with AND semantics.

**Independent Test**: Select `work` and `1-1`; confirm only meetings containing both remain. Add a text term and confirm the result must also match that term.

### Implementation

- [X] T012 [US3] Add a multi-select shared-tag filter to the right of the text field in `Sources/MeetingRecord/SearchView.swift` and apply all selected tags as AND constraints in `Sources/MeetingRecord/MeetingStore.swift`, citing `SearchQuery.Selected tag IDs` in `data-model.md`.

**Checkpoint**: Text-only, tag-only, and combined searches return the expected meetings.

---

## Phase 6: User Story 4 - Describe a Meeting (Priority: P2)

**Goal**: Add and update an optional description without changing the title, recordings, or transcript.

**Independent Test**: Save a description from the meeting context menu, confirm it appears beneath the title and in Search, find it by a distinctive phrase, then cancel an edit and confirm the saved description is unchanged.

### Implementation

- [X] T013 [US4] Build `Sources/MeetingRecord/MeetingDescriptionEditorView.swift` with optional plain-text entry and explicit Save/Cancel behavior for `Meeting.Description` in `data-model.md`.
- [X] T014 [US4] Add Edit Description to the meeting context menu and show saved descriptions beneath the title in the meeting detail view through `Sources/MeetingRecord/SidebarView.swift` and `Sources/MeetingRecord/ContentView.swift`.
- [X] T015 [US4] Ensure description matches are included and displayed in `Sources/MeetingRecord/SearchView.swift` using the `Meeting.Description` definition in `data-model.md`.

**Checkpoint**: Descriptions can be edited, persisted, displayed, and found without modifying source audio or transcript content.

---

## Phase 7: Polish and Cross-Cutting Concerns

**Purpose**: Preserve responsiveness, accessibility, and local-first behavior across all stories.

- [X] T016 Review `Sources/MeetingRecord/SearchView.swift`, `Sources/MeetingRecord/SidebarView.swift`, and `Sources/MeetingRecord/MeetingStore.swift` against `contracts/search-ui.md` and `quickstart.md`; confirm query work stays off the main UI path, controls have accessible labels, and search does not touch recording or transcript writes.

---

## Dependencies and Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies.
- **Foundational (Phase 2)**: Depends on setup; blocks all user stories.
- **User Stories (Phases 3–6)**: Depend on the foundation. US3 builds on the search view from US1 and shared tags from US2. US4 adds editable descriptions that US1 already includes in matching and result presentation.
- **Polish (Phase 7)**: Depends on all four user stories.

### User Story Dependencies

- **US1 (P1)**: Starts after Phase 2. Useful independently for title, description, transcript, and any existing tag text.
- **US2 (P1)**: Starts after Phase 2. Creates and assigns the tags US1 can search and US3 can filter.
- **US3 (P1)**: Depends on US1's query and result flow and US2's shared tag catalog.
- **US4 (P2)**: Depends on Phase 2. Description persistence is foundational; its edit surface is independently usable. Search for descriptions is integrated in US1.

### Parallel Opportunities

- T002 (`Meeting.swift`) and T003 (`Tag.swift`) can run in parallel because they edit different files.
- After Phase 2, the first portions of US1 and US2 can proceed independently until their shared navigation and sidebar integrations.
- User stories US1 and US2 can be implemented in parallel by separate contributors after the foundation; US3 must wait for both. US4's editor can proceed after Phase 2, while its Search result integration depends on US1.

## Parallel Example

```text
Task: T002 Add optional Meeting.Description in Sources/MeetingRecord/Meeting.swift
Task: T003 Define Tag and MeetingTagAssignment in Sources/MeetingRecord/Tag.swift
```

## Implementation Strategy

1. Complete setup and the shared metadata migration.
2. Deliver US1 as the initial useful increment, then US2 so users can create and assign the tags surfaced by search.
3. Add the multi-tag filter in US3.
4. Complete description editing and detail presentation in US4.
5. Review responsiveness and accessibility without altering recording or transcript paths.
