# Feature Specification: Create, Rename, and Navigate Meetings

**Feature Branch**: Not created; no branch hook is configured.

**Created**: 2026-11-21

**Status**: Draft

**Input**: User description: "I want to add a meeting, show it in the sidebar sorted by the most recently updated one, and have a plus button in the Meetings section. Reuse the existing SQLite storage, allow renaming by double-clicking either the sidebar name or the open Meeting title, and show only a Transcription tab with an icon; more tabs will come later."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create a Meeting from the Sidebar (Priority: P1)

As a user, I want a plus button beside the Meetings heading so I can create a distinct, empty Meeting and immediately open its workspace.

**Why this priority**: Creating a Meeting is the first step toward organizing a new meeting and using later recording or import features.

**Independent Test**: Starting with an empty list, activate the plus button and verify that one named Meeting appears, is selected, and opens in the main content. Close and reopen the app to verify that it remains available.

**Acceptance Scenarios**:

1. **Given** Home, Settings, or an existing Meeting is open, **When** the user activates the plus button beside Meetings, **Then** exactly one new Meeting is saved, appears at the top of the sidebar, becomes the sole selected destination, and opens in the main content with its name visible.
2. **Given** no Meetings exist, **When** the user creates the first Meeting, **Then** the empty-list message is replaced by that Meeting and the plus button remains available.
3. **Given** a newly created Meeting, **When** the user views it, **Then** it has an automatically generated, non-empty English name and contains no Inputs or Transcription content; creation does not start recording, importing, or transcription, or request audio permissions.
4. **Given** a successfully created Meeting, **When** the user closes and reopens the app offline, **Then** the same Meeting identity and name remain in the sidebar and can be selected; Home remains the initial destination.
5. **Given** creation cannot be saved, **When** the user activates the plus button, **Then** an understandable error is shown, no unsaved Meeting appears as successfully created, existing Meetings and selection are preserved, and the user can retry.
6. **Given** keyboard-only navigation or an assistive technology, **When** the user reaches the plus button, **Then** it has visible keyboard focus and the accessible name "Add Meeting" and can be activated without a pointer.

---

### User Story 2 - Find the Most Recently Updated Meeting First (Priority: P2)

As a user, I want Meetings ordered by their latest saved change so I can quickly return to the most recently changed work.

**Why this priority**: A predictable order keeps recent work easy to find as the list grows.

**Independent Test**: Use three Meetings with distinct saved update times. Verify descending order on load, save a change to the oldest Meeting by renaming it, and verify that it moves to the top without losing the active selection.

**Acceptance Scenarios**:

1. **Given** Meetings with different last-update times, **When** the sidebar loads or refreshes after a saved change, **Then** Meetings appear from most recently updated to least recently updated.
2. **Given** an existing list, **When** a new Meeting is created, **Then** its creation counts as its first update and it appears before previously existing Meetings.
3. **Given** an older Meeting, **When** a change to its stored name or content is successfully saved, **Then** its last-update time reflects that save and the sidebar reorders accordingly while preserving the selected Meeting's identity.
4. **Given** an existing Meeting, **When** the user only selects, opens, or reads it, **Then** its last-update time and the sidebar order remain unchanged.
5. **Given** Meetings with identical last-update times, **When** the sidebar is refreshed or the app is reopened, **Then** those tied Meetings retain a consistent relative order; a newly created Meeting still appears first when its update time ties existing Meetings.
6. **Given** existing local Meetings from the app-shell feature, **When** the updated app opens, **Then** every Meeting remains available with the same identity and name, and repeated loads produce the same order until a saved change occurs.

---

### User Story 3 - Rename a Meeting in Place (Priority: P1)

As a user, I want to double-click a Meeting name in the sidebar or its title at the top of the main content to rename it without opening a separate form.

**Why this priority**: An automatically named Meeting needs an easy way to become recognizable.

**Independent Test**: Rename from the sidebar, then from the main title, and reopen the app. Verify that both locations display the saved name and that the Meeting moves to the top after each actual change.

**Acceptance Scenarios**:

1. **Given** a Meeting row or an open Meeting title, **When** the user double-clicks its name, **Then** that name becomes an inline text field with keyboard focus; double-clicking a sidebar name also selects that Meeting.
2. **Given** an edited name, **When** the user presses Enter or leaves the field, **Then** surrounding whitespace is trimmed and a non-empty changed name is saved; both locations show the new name, the Meeting moves to the top, and its identity and selection remain intact.
3. **Given** an edit in progress, **When** the user presses Escape, **Then** the saved name and update time remain unchanged.
4. **Given** a blank or whitespace-only draft, **When** the user attempts to save, **Then** the app explains that a name is required and retains the draft for correction without changing the saved name or recency.
5. **Given** a storage failure during rename, **When** save is attempted, **Then** the old saved name and sidebar order remain intact and the draft remains available to retry or cancel.
6. **Given** an unchanged name after trimming, **When** the edit is committed, **Then** editing ends without updating recency or changing order.
7. **Given** keyboard-only or assistive-technology navigation, **When** the user invokes Rename for a focused Meeting row or its main title, **Then** the same inline editing flow is available without double-clicking.

---

### User Story 4 - Open the Transcription Workspace (Priority: P2)

As a user, I want an open Meeting to show a Transcription tab with an icon so I can identify its workspace before transcription features are added.

**Why this priority**: Establishes the requested Meeting layout without anticipating other tabs or processing features.

**Independent Test**: Open a new Meeting and an existing Meeting; each shows its title at the top and exactly one selected tab labeled Transcription with a visible icon and an understandable empty state.

**Acceptance Scenarios**:

1. **Given** a Meeting is created or selected, **When** its main content opens, **Then** its editable title appears above exactly one tab labeled "Transcription", accompanied by an icon and selected by default.
2. **Given** an empty Meeting, **When** Transcription is viewed, **Then** it shows "No transcription yet." without recording, import, processing controls, or invented transcript content.
3. **Given** the user switches between Meetings, **When** each opens, **Then** the title matches the selected Meeting and Transcription remains the sole selected tab.

### Edge Cases

- Multiple deliberate activations create distinct Meetings, even if generated names coincide; each activation creates at most one record, and internal retries do not duplicate a successful creation.
- If creation is still in progress, additional activations must not start overlapping creation requests; the control communicates its unavailable state until completion.
- With 30 or more Meetings, creation reveals the new selected row at the top of the list without moving Home, Settings, or the Meetings heading out of reach.
- Long generated names follow the existing truncation and full-name discovery behavior without widening the sidebar.
- Failed changes do not update recency or reorder Meetings.
- Renaming supports Unicode, punctuation, duplicate names, and long names; name collisions never merge Meetings.
- Only one inline editor is active at a time. Before navigation, creation, or starting another edit, a changed draft must save successfully; invalid or failed saves keep the current editor and destination until corrected or cancelled.
- A pending save cannot be submitted twice by both Enter and focus loss, and reordering must not move focus to another Meeting.
- Existing Meetings without a recorded last-update time receive a stable fallback order without losing data or being represented as newly edited on every launch.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Meetings section MUST show a plus button adjacent to its heading, available regardless of the selected destination or whether the list is empty, and accessible without scrolling the Meeting rows.
- **FR-002**: Activating the plus button MUST create exactly one distinct, empty Meeting with a non-empty, automatically generated English name, without requiring title entry or confirmation.
- **FR-003**: A successful creation MUST save the Meeting locally before presenting it as created, place it first in the sidebar, reveal its row, and select and open it in the main content.
- **FR-004**: Creating a Meeting MUST NOT create Inputs, start recording, import files, run transcription, request audio permissions, or require an account, internet connection, or model download.
- **FR-005**: Created Meetings MUST retain their identities, names, and recency information across app restarts. Existing local Meetings MUST remain available without data loss.
- **FR-006**: The sidebar MUST sort Meetings by descending last successful update time on load and after saved changes. Creation MUST establish the initial update time; successful changes to stored Meeting names or content MUST advance it. Viewing, selecting, failed saves, and app restarts MUST NOT advance it.
- **FR-007**: Ties in update time MUST resolve consistently across refreshes and restarts. Creation MUST put the new Meeting ahead of existing Meetings even when update times tie. Reordering MUST preserve the active destination's identity.
- **FR-008**: If creation fails, the app MUST display an understandable error and permit retry without adding a phantom row, changing the active destination, losing existing data, or duplicating a successfully saved Meeting.
- **FR-009**: The plus button MUST support keyboard activation, visible focus, and the accessible name "Add Meeting". It MUST prevent overlapping creation requests while a creation is pending.
- **FR-010**: Existing empty-list, scrolling, long-name, and navigation behavior MUST remain usable as Meetings are added. Home MUST remain the initial destination on app launch.
- **FR-011**: Meetings lacking historical update information MUST receive a stable fallback position that does not change on each launch; subsequent successful updates MUST make them participate in the same recency ordering as other Meetings.

- **FR-012**: Users MUST be able to rename a Meeting by double-clicking its sidebar name or the main title. A keyboard-accessible Rename action MUST expose the same flow at both locations.
- **FR-013**: Inline rename MUST trim surrounding whitespace, reject empty names, save on Enter or leaving the field, and cancel on Escape. Unchanged names MUST NOT update recency. Duplicate names and Unicode MUST be supported.
- **FR-014**: A successful rename MUST update both displayed names and recency while preserving Meeting identity and selection. Validation or save failure MUST retain the draft with an understandable error and preserve saved data and order.
- **FR-015**: Each open Meeting MUST display its title above exactly one selected tab labeled "Transcription" with a visible icon. Empty Meetings MUST show "No transcription yet." within that tab. No additional tabs or transcription processing are included.
- **FR-016**: Only one rename editor MUST be active at a time. An action that leaves a changed draft MUST wait for a successful save or explicit cancellation before proceeding; invalid or failed saves MUST preserve the editor and current destination.

### Key Entities *(include if feature involves data)*

- **Meeting**: A distinct local meeting workspace with a stable identity, a display name, creation information, and last successful update information. New Meetings have no Inputs or Transcription content. Names need not be unique.
- **Meeting list**: The sidebar's ordered collection of Meetings, with a consistent rule for equal update times and a selection that follows Meeting identity rather than row position.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From Home, Settings, or an existing Meeting, a user can create and open one new empty Meeting with one activation of the plus button and no additional form or confirmation.
- **SC-002**: With 100 local Meetings, a successfully saved new Meeting is visible and selected at the top within one second of activation during validation on the user's Mac.
- **SC-003**: In all ordering scenarios, including equal update times and repeated app launches, the sidebar matches the specified recency order; opening a Meeting alone causes zero order changes.
- **SC-004**: All successfully created Meetings retain their identities and names after closing and reopening the app offline, with no missing or duplicate records in the validation set.
- **SC-005**: A user can reach and activate Add Meeting using only the keyboard and identify the resulting selected Meeting; creation also succeeds with no internet access or audio permissions.
- **SC-007**: In every rename acceptance scenario, both visible names match the saved name after success and after reopening; cancellation, unchanged names, and rejected saves cause zero recency changes.
- **SC-008**: Every opened Meeting shows exactly one selected Transcription tab, with both its text and icon visible, including at the existing minimum window size.
- **SC-006**: In all simulated creation-failure scenarios, existing Meetings and the active destination remain intact, no phantom Meeting is shown, and retry after recovery creates exactly one Meeting.

## Assumptions

- This feature builds on the existing app shell, local Meeting storage, and selection behavior in `specs/001-app-shell/spec.md`. It adds creation and recency ordering that were explicitly deferred by that feature.
- The user's reference to a plus in the Meetings tab means a plus beside the existing Meetings section heading in the sidebar.
- Automatic random names follow PRODUCT.md. The exact vocabulary is a presentation choice; names must be non-empty, English, and readable. A naming collision does not merge Meetings.
- Successful stored changes define "updated"; merely opening a Meeting does not. Renaming is the only existing-Meeting modification introduced by this feature.
- Scope updated on 2026-11-21 by the planning request: inline renaming and the single Transcription tab are included. Deleting, searching, manually ordering, recording, importing, transcription processing, and additional tabs remain outside this feature. The Inputs tab described in PRODUCT.md is deferred, not removed from the full product.
- The constitution's local operation, empty Meeting creation without capture, durable persistence, and smallest necessary scope apply. No changes to product principles are required.
- The exact fallback and tie-breaking rules will be chosen during planning, subject to stable ordering, preservation of existing Meetings, and new Meetings appearing first.
