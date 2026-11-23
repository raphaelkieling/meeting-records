# Feature Specification: Live Audio Transcription

**Feature Branch**: Not created; the prototype is captured on `prototype/audio-transcription`.

**Created**: 2026-11-23

**Status**: Draft

**Input**: User description: "Transcribe audio Inputs in real time, keep a transcript attached to each audio, and show all transcripts together in the Meeting's Transcription tab."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Read transcription while recording (Priority: P1)

As a user, I want each audio Input to be transcribed while it is being recorded, so I can see the conversation appear without waiting for the recording to finish.

**Why this priority**: Incremental transcription is the primary outcome of this feature.

**Independent Test**: Start a Meeting recording and confirm that transcript text appears in the Meeting's Transcription tab before stopping the recording, then confirm that the Input becomes Complete after pending text is processed.

**Acceptance Scenarios**:

1. **Given** a Meeting is recording, **when** audio is captured, **then** its Input shows Pending until transcription begins, then Transcribing while its text is updated.
2. **Given** a recording is stopped, **when** any queued audio has been transcribed, **then** its Input status becomes Complete and its final text appears in the unified Transcription.
3. **Given** audio transcription falls behind capture, **when** more audio is being recorded, **then** capture continues and the Input remains Transcribing until all captured audio is processed.

### User Story 2 - Read one unified Meeting transcription (Priority: P1)

As a user, I want the Transcription tab to bring together the text from every audio Input, so I can read the whole Meeting in one place while still knowing which recording and audio source each passage came from.

**Why this priority**: Separate Input results should remain traceable while the Meeting is readable as one transcript, even when it has several recordings.

**Independent Test**: Add two or more audio Inputs with distinct text, open Transcription, and confirm that all text appears in Input order with its source and speaker labels.

**Acceptance Scenarios**:

1. **Given** a Meeting has multiple audio Inputs, **when** the user opens Transcription, **then** one unified reading view contains each Input's transcript in the order defined for Meeting Inputs.
2. **Given** text from different Inputs appears in the unified view, **when** the user reads any passage, **then** its source Input and available speaker label remain identifiable.
3. **Given** the active recording is being transcribed, **when** new text is available, **then** it appears in the unified view without waiting for the recording to stop.
4. **Given** a Meeting has no transcribed text, **when** the user opens Transcription, **then** the existing empty state is shown until text is available.

### User Story 3 - Recover transcription after the app closes (Priority: P2)

As a user, I want saved audio and its partial transcript to survive the app closing, so the unfinished transcript can continue later without recording the same audio again.

**Why this priority**: A device shutdown can interrupt a recording, and losing its saved audio or transcript would undermine the value of durable capture.

**Independent Test**: Close the app during a recording, reopen it, confirm that capture has not restarted and the saved Input remains, then confirm that its unfinished transcription resumes. Start a new recording explicitly and verify that it becomes a separate Input.

**Acceptance Scenarios**:

1. **Given** the app closes during an active recording, **when** it is reopened, **then** capture remains stopped and the saved audio is available as its own Input.
2. **Given** a saved Input has unfinished transcription, **when** the app reopens and transcription is available, **then** processing resumes automatically from the saved progress and the Input shows Pending or Transcribing as appropriate.
3. **Given** the user wants to continue recording after reopening, **when** they explicitly start recording, **then** a new Input is created and transcribed independently of the recovered Input.

### Edge Cases

- A Meeting may have many Inputs; the unified view includes each transcript once and retains its source label.
- The transcript may lag behind audio capture; recording continues and the status remains Transcribing until the backlog is processed.
- The app may close while capturing or while processing saved audio. Saved audio and completed transcript text are retained; capture does not restart automatically, while unfinished transcription resumes automatically after reopening.
- If transcription cannot start because the required processing capability is unavailable, the audio remains preserved and Pending, and the user receives an explanation.
- An audio Input may come from a recording or, when audio import is available, an imported file. This feature does not add or change the import flow.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Each audio Input MUST retain its own transcript result and transcription status.
- **FR-002**: For a Recording, transcription MUST start automatically as captured audio becomes available, without waiting for the user to stop recording.
- **FR-003**: Transcription MUST update incrementally while recording. Delayed transcription MUST NOT stop or discard audio capture.
- **FR-004**: After recording stops, the system MUST process remaining captured audio before marking that Input's transcript Complete.
- **FR-005**: The existing Inputs presentation MUST remain intact, with one transcription status badge added to each audio Input. The badge MUST use only Pending, Transcribing, or Complete and MUST describe transcription progress.
- **FR-006**: The Meeting's Transcription tab MUST show a single unified view containing the transcript results of all its audio Inputs, in the order defined for Meeting Inputs.
- **FR-007**: The unified Transcription MUST identify each passage's source Input and preserve the available Me and Other source labels and timing, including overlapping passages.
- **FR-008**: New transcript text MUST appear in the unified view as it becomes available. The view MUST reflect the individual Input's current status and show Complete only after all audio for that Input has been processed.
- **FR-009**: If the app closes during capture, audio capture MUST stop. The system MUST preserve recoverable audio and transcript progress as an unfinished Input and MUST NOT resume capture automatically after reopening.
- **FR-010**: After reopening, the system MUST resume unfinished transcription automatically from saved progress when processing is available. Existing transcript text MUST be retained.
- **FR-011**: Starting capture after reopening MUST require an explicit user action and MUST create a separate Input.
- **FR-012**: Audio Inputs from recording or import MUST use the same per-Input transcription and unified Meeting view. Importing audio itself is outside this feature.
- **FR-013**: If transcription is unavailable, the system MUST preserve the audio, leave the Input Pending, and explain why transcription has not started.

### Key Entities *(include if feature involves data)*

- **Audio Input**: A recording or imported audio source belonging to a Meeting, with its original audio, order, and transcription status.
- **Input Transcript**: The transcript text and source passages derived from one Audio Input, updated as processing advances.
- **Meeting Transcription**: The unified reading view derived from the Meeting's Input Transcripts, preserving source Input, audio-source labels, and timing.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a recording walkthrough, users can read transcript text before stopping capture, and the Input reaches Complete after its remaining audio is processed.
- **SC-002**: With 10 audio Inputs, the Transcription view contains every Input's transcript exactly once and lets the user identify the source Input for each passage.
- **SC-003**: In all tested lifecycle states, each Input's badge matches one of Pending, Transcribing, or Complete and describes its transcription progress.
- **SC-004**: After closing the app during recording, reopening preserves the saved Input, does not restart capture, resumes unfinished transcription automatically, and creates a separate Input only after the user starts recording again.

## Assumptions

- The selected presentation follows option C in the captured prototype on branch `prototype/audio-transcription`.
- A Meeting's unified transcription follows the existing Input order; passages retain their within-Input timing and source labels.
- A badge reports transcription progress. Whether its audio capture was interrupted remains separate from the three transcription statuses.
- Audio import is a future Input creation path; this feature transcribes imported audio once an audio Input exists but does not implement import controls.
- The configured local transcription capability is available for automatic processing. When it is not available, the Input remains Pending and the user is told why.
