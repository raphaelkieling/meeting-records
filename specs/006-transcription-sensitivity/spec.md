# Feature Specification: Microphone Transcription Sensitivity

**Feature Branch**: \`main\`

**Created**: 2026-11-23

**Status**: Draft

**Input**: Add a Settings sensitivity control to avoid transcribing very quiet microphone input, and increase the live transcription window to approximately 10 seconds, and fix two identified keyboard focus outlines in the Home and sidebar meeting list.

## User Scenarios & Testing

### User Story 1 - Set the Microphone Sensitivity (Priority: P1)

As a user, I want to set how loud microphone audio must be before it is sent for transcription, so quiet room noise is less likely to become invented words.

**Why this priority**: The reported false phrases occur on the user's own microphone track. This control directly addresses that track and lets the user tune it.

**Independent Test**: In Settings, adjust the threshold while watching a live input meter, then record quiet speech and room noise. Verify the original audio remains saved and only eligible microphone audio is transcribed.

**Acceptance Scenarios**:

1. **Given** Settings open, **When** the user changes the microphone sensitivity control, **Then** the current input level and threshold are visible and the chosen value is saved for the next and subsequent recordings.
2. **Given** the microphone signal remains below the configured threshold, **When** transcription processes the audio, **Then** that quiet audio does not produce transcript text.
3. **Given** microphone speech is above the configured threshold, **When** transcription processes it, **Then** the speech is sent to the model with a margin of context before and after the eligible audio.
4. **Given** the user speaks quietly, **When** they raise the threshold above their speech level, **Then** they can see the level fall below the threshold and understand that speech could be omitted.
5. **Given** the Other track has speech, **When** microphone sensitivity is changed, **Then** the Other track transcription is unaffected.

---

### User Story 2 - Transcribe in Longer Windows (Priority: P2)

As a user, I want speech grouped into windows of about ten seconds so the model receives more context and is less likely to hallucinate in tiny fragments.

**Why this priority**: Ten-second windows address the short-fragment behavior while preserving live transcription during a recording.

**Independent Test**: Record continuous speech and pauses. Verify transcription work becomes available in roughly ten-second windows, the final shorter window is processed on stop, and timeline timestamps remain aligned.

**Acceptance Scenarios**:

1. **Given** an active recording, **When** a source has accumulated about ten seconds of audio, **Then** the saved audio becomes eligible for transcription as a window while recording continues.
2. **Given** a recording stops with a shorter final window, **When** capture finalizes, **Then** the remaining saved audio is transcribed.
3. **Given** adjacent windows contain one continuous sentence, **When** their text is displayed, **Then** timing and words remain in order without artificial gaps or duplicated overlap.
4. **Given** no eligible microphone speech exists in a window, **When** transcription completes, **Then** the window completes without invented transcript text and without blocking other source work.

### User Story 3 - Keep Navigation Outlines Visible (Priority: P2)

As a keyboard user, I want focus outlines in the sidebar to remain fully visible and the Home cards to stay free of unwanted focus borders.

**Independent Test**: Navigate the sidebar Meetings with keyboard focus and verify the first row's outline is not clipped. Tab through Home and verify Home cards do not add the blue outline.

**Acceptance Scenarios**:

1. **Given** the first Meeting row is focused, **When** it draws its red or blue keyboard focus outline, **Then** the full border including its top edge is visible.
2. **Given** a recent Meeting card on Home, **When** it receives keyboard focus, **Then** it remains accessible and activatable without drawing the unwanted blue outline.

### Edge Cases

- A brief pause inside a sentence must not erase nearby speech. A small context margin is retained around threshold crossings and adjacent eligible audio is grouped.
- Raising the threshold can suppress quiet words. The meter shows the threshold relative to current microphone input.
- The saved Me audio remains complete even when parts are excluded from transcription.
- Empty and near-silent input must complete without generating text.
- Changing the setting during an active recording applies to windows that have not started transcription yet. Already submitted work is not rewritten.
- The Other track does not use the microphone threshold.
- Settings remain available when the app is offline and across app restarts.

## Requirements

### Functional Requirements

- **FR-001** — Settings MUST provide a persistent microphone transcription threshold and a live input-level display on the same scale.
- **FR-002** — The threshold MUST only determine which portions of the Me track are sent to transcription. It MUST NOT modify or discard saved audio.
- **FR-003** — The app MUST retain a configurable context margin around eligible audio and group nearby eligible portions so speech is not cut at threshold crossings or normal pauses.
- **FR-004** — The default threshold MUST preserve current microphone transcription behavior until the user changes it.
- **FR-005** — The app MUST increase the live transcription checkpoint window from the current approximately five seconds to approximately ten seconds per audio source.
- **FR-006** — On stop or recovery, the app MUST process the final partial window and complete all saved audio processing.
- **FR-007** — Transcript timestamps and source ordering MUST remain aligned with the original saved recording after filtering and windowing.
- **FR-008** — Other track audio MUST continue to be transcribed independently of the microphone threshold.
- **FR-010** — Sidebar focus outlines MUST remain fully visible at the first row, including the top edge.
- **FR-011** — Home recent Meeting buttons MUST remain keyboard accessible without an unwanted blue focus border.
- **FR-009** — The user MUST be able to see when the input level is below the configured threshold while tuning the setting.

### Key Entities

- **Microphone sensitivity setting** — A locally stored threshold used only to choose microphone audio for transcription.
- **Transcription window** — A portion of saved audio with an offset, source, and duration. Windows preserve source timing and may include the configured context margin.
- **Input level** — The live microphone signal level shown against the sensitivity threshold.

## Success Criteria

### Measurable Outcomes

- **SC-001** — With microphone audio consistently below the configured threshold, no text is produced from that audio while its original audio remains playable.
- **SC-002** — With speech consistently above threshold, at least 95% of a set of test utterances remain transcribed with no words lost at window boundaries.
- **SC-003** — During continuous capture, eligible work is normally produced in windows between 9 and 11 seconds, and a final shorter window completes within one normal processing cycle after stopping.
- **SC-004** — In at least 9 out of 10 user calibration attempts, the user can position the threshold above room noise and below their ordinary speaking level using the meter.
- **SC-006** — The first sidebar row’s complete keyboard focus outline remains visible, while Home entries remain keyboard operable without the blue outline.
- **SC-005** — Changing microphone sensitivity does not change text or completion behavior for the Other track.

## Assumptions

- The sensitivity threshold applies to microphone transcription only. It does not perform speech recognition or remove noise from saved audio.
- Audio currently saved in five-second checkpoints remains compatible. New windowing operates over the saved segments and their original offsets.
- The existing local Whisper model and processing queue remain in use.
- The default threshold preserves the current behavior to avoid changing transcription for existing users before they tune it.
