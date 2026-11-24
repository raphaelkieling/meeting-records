# Feature Specification: Meetings Home

**Feature Branch**: `main`

**Created**: 2026-11-23

**Status**: Draft

**Input**: Show the three newest Meetings on Home, provide quick access to their latest saved recordings, and display live library totals, and let the user delete a Meeting from its sidebar menu.

## User Scenarios & Testing

### User Story 1 - Find Recent Meetings (Priority: P1)

As a user opening the app, I want to see my newest Meetings so I can quickly find the one I want to revisit.

**Why this priority**: Finding a recent Meeting is the primary purpose of Home.

**Independent Test**: Create four Meetings at different times, add multiple recordings to the oldest one, and open Home. Check that the three newest Meetings appear in creation order.

**Acceptance Scenarios**:

1. **Given** four Meetings, including a newly created Meeting without recordings, **When** the app opens or the user returns to Home, **Then** Home lists the three newest Meetings by creation time, each once, with the newest first.
2. **Given** a Meeting older than the three shown, **When** the user renames it or adds a recording to it and returns to Home, **Then** the same three Meetings appear in the same order.
3. **Given** two Meetings, **When** Home loads, **Then** it shows exactly those two with their current names. **Given** zero Meetings, **When** Home loads, **Then** it shows an empty state for recent Meetings.

---

### User Story 2 - Open a Meeting at Its Latest Recording (Priority: P2)

As a user returning to a recent Meeting, I want to land at its latest saved recording so I can find the Play control immediately.

**Why this priority**: A direct route keeps the list useful even when a Meeting has many recordings.

**Independent Test**: Open a Meeting from Home after giving it enough recordings to require scrolling. Check that Inputs opens with the newest saved recording visible and highlighted.

**Acceptance Scenarios**:

1. **Given** a recent Meeting with multiple saved recordings, **When** the user activates its Home entry with a click or keyboard, **Then** the app selects that Meeting, opens Inputs, and brings the newest saved recording into view with a highlight. Playback starts only when the user selects Play.
2. **Given** a recent Meeting with no saved recordings, **When** the user activates its Home entry, **Then** the app selects the Meeting and opens Inputs. If it has no recordings at all, the regular Inputs empty state appears.
3. **Given** a recent Meeting with both a saved and an in-progress recording, **When** the user opens it from Home, **Then** the newest saved recording receives the highlight.

---

### User Story 3 - See Recording and Transcription Totals (Priority: P3)

As a user opening Home, I want to see how much time I have recorded and how many transcriptions have finished across my library.

**Why this priority**: Two figures give a quick overview while leaving recent Meetings as the primary content.

**Independent Test**: Across four Meetings, use a library with one hour of synchronized two-track audio and one completed transcription in the oldest Meeting, plus 30 minutes of saved audio with a pending transcription in a recent Meeting. Home shows 1 hour and 30 minutes and one completed transcription.

**Acceptance Scenarios**:

1. **Given** saved recordings in Meetings inside and outside the recent list, **When** Home loads, **Then** both totals cover the entire current library and appear as two labeled values below the list.
2. **Given** an active recording and pending or failed transcriptions, **When** Home loads, **Then** the active recording contributes zero to recorded time and the pending or failed transcriptions contribute zero to the completed count.
3. **Given** Home is visible, **When** a transcription finishes in the background, **Then** the displayed count increases by one without reopening Home. **Given** a library with no saved recordings, **When** Home loads, **Then** both totals are zero.

4. **Given** a recording is in progress, **When** it is saved and Home is visible or the user returns to it, **Then** the total includes its playable duration without a manual refresh.

---

### User Story 4 - Delete a Meeting from the Sidebar (Priority: P3)

As a user managing my local library, I want to delete a Meeting and everything it contains after confirming the action.

**Why this priority**: The sidebar is where users navigate Meetings and can identify the entry they want to remove.

**Independent Test**: Right-click a Meeting with saved audio and a completed transcription. Cancel the dialog and verify the content still opens. Repeat and confirm, then verify the Meeting and its content are gone and Home reflects the remaining library.

**Acceptance Scenarios**:

1. **Given** a Meeting in the sidebar, **When** the user chooses **Delete Meeting…** from its context menu, **Then** a dialog names the Meeting, explains that its contents will be permanently deleted, and offers Cancel and Delete.
2. **Given** that dialog, **When** the user cancels, **Then** the Meeting, its contents, the current selection, and Home totals remain intact.
3. **Given** a Meeting with saved audio and a completed transcription, **When** the user confirms, **Then** the app removes that Meeting and all attached content. The sidebar and Home refresh automatically, including filling the available recent slot and subtracting the deleted audio and completed transcriptions.
4. **Given** the selected Meeting is deleted, **When** it disappears from the library, **Then** Home becomes the selected destination. Deleting another Meeting preserves the current destination.
5. **Given** a Meeting is starting, recording, or saving a recording, **When** the user opens its context menu, **Then** Delete is unavailable until capture finishes.

### Edge Cases

- Meetings with identical creation times use a consistent order across repeated visits. Recordings with identical start times likewise produce a consistent highlight.
- A saved interrupted recording uses the duration of its recovered audio on the playback timeline. Time between the interruption and recovery is excluded.
- Background transcription of a deleted Meeting cannot restore it or stop work on other Meetings. A failed or interrupted file cleanup remains pending and can be retried.
- A completed transcription for a saved recording counts even when its audio contains no speech.
- When library data cannot be read, the affected Home content shows an error and offers a retry. An empty list and zero totals represent a successfully read library.

## Requirements

### Functional Requirements

- **FR-001** — The app MUST show Home on launch and let users return to it from the sidebar. Home MUST work offline.
- **FR-002** — Home MUST show up to three Meetings from the local library in descending order of creation time, with one entry per Meeting and its current name. A Meeting is eligible as soon as it is created. Renames, recordings and transcriptions MUST leave its creation order intact.
- **FR-003** — Activating an entry by mouse or keyboard MUST select that Meeting and open Inputs. The app MUST bring the saved recording with the latest start time into view and highlight it when one exists. Playback MUST require a separate Play action.
- **FR-004** — Home MUST show two labeled values below recent Meetings, total recorded time and completed transcriptions. Both values MUST cover the current local library.
- **FR-005** — Total recorded time MUST add the playable duration of each saved recording once. Synchronized tracks share one playback timeline. Recovered recordings contribute their saved playable duration. In-progress recordings are excluded.
- **FR-006** — Completed transcriptions MUST count each saved recording whose transcription is in the Complete state once.
- **FR-007** — Returning to Home MUST reflect the current library. Home MUST update from saved library changes without a manual refresh. Recording finalization or recovery updates recorded time, transcription completion updates the count, and Meeting deletion updates the list and both totals.
- **FR-008** — Home MUST show an empty state when the library has no Meetings and zero totals when it has no saved recordings. If a read fails, Home MUST show the affected content as unavailable and provide a retry.
- **FR-009** — A Meeting's sidebar context menu MUST offer **Delete Meeting…**. The app MUST require explicit confirmation in a dialog that names the Meeting and describes the permanent removal of its contents.
- **FR-010** — Confirmed deletion MUST remove the Meeting and its attached Inputs, audio files, transcripts and pending processing. Failure to finish cleanup MUST be reported and remain recoverable. Deletion MUST be unavailable while the target Meeting is starting, recording, or saving a recording.
- **FR-011** — When the deleted Meeting is selected, the app MUST select Home. Otherwise the app MUST preserve the current destination.

### Key Entities

- **Meeting** — A named meeting with a creation time and zero or more Inputs. Its creation time determines its place on Home.
- **Recording** — A capture session associated with one Meeting. Its start time determines the highlight in Inputs. Its saved duration is measured on the shared playback timeline.
- **Recording transcription** — The processing result for one Recording. Its Complete state determines whether it contributes to the total.

## Success Criteria

### Measurable Outcomes

- **SC-001** — At launch and on return to Home, libraries with zero, one, two, three and four Meetings show exactly zero, one, two, three and three entries respectively. In each case the entries are the newest by creation time.
- **SC-002** — From Home, one click or keyboard activation opens the selected Meeting in Inputs and makes its latest saved recording visible, even when the Inputs list exceeds one screen. A Meeting with no recordings opens its Inputs empty state in the same single activation.
- **SC-003** — In a library with 60 minutes of two-track saved audio, 30 minutes of one-track saved audio, and one completed recording transcription, Home shows 90 minutes of total recorded time and one completed transcription. The count becomes two when the second transcription completes while Home is visible.
- **SC-004** — With network access disabled, a user can reopen the app, see their recent Meetings and totals, and navigate from Home to an existing recording.
- **SC-005** — After cancelling deletion, the target remains available. When the user confirms deletion of a recent Meeting with ten minutes of audio and one completed transcription in a four-Meeting library, the fourth Meeting fills the open slot, the totals decrease by ten minutes and one transcription, and the deleted contents are gone after relaunch.

## Assumptions

- The recent list uses existing Meeting names. The recording highlight points to the existing Inputs card.
- Statistics cover recordings currently retained in the library. Imported material falls outside these recording totals.
- The feature depends on the existing saved recording and transcription completion states. It adds no steps to recording or transcription.
- Constitution principles I, II, III and V apply. Offline access, saved audio, and completed processing remain the basis for what Home displays. The navigation supports the first-version acceptance criteria for working with local Meetings and their Inputs. See [PRODUCT.md](../../PRODUCT.md#critérios-de-aceitação-da-primeira-versão).
