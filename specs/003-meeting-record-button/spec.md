# Feature Specification — Meeting Record Button

**Feature Branch** — Current branch (`main`)  
**Created** — 2026-11-22  
**Status** — Draft  
**Input** — Keep a Record button visible inside each Meeting and add an Inputs tab beside Transcription.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Start and stop recording (Priority: P1)

After creating a Meeting, I can choose when to start recording and stop from either tab.

**Why this priority** — Recording is the primary action inside a Meeting.  
**Independent Test** — Create a Meeting, start recording, change tabs, then stop.

1. **Given** I create or reopen a Meeting that can record, **when** it opens, **then** the visible Record button is ready and capture starts only when I press it.
2. **Given** the Meeting is recording, **when** I switch tabs or scroll the contents, **then** the floating control still shows the live audio level and Stop. Stopping adds the finished Recording to Inputs. Recording again adds a separate entry.
3. **Given** I leave the recording Meeting, **when** I open another Meeting, **then** its Record button is disabled. The active Meeting has a red indicator at the right edge of its sidebar row. Selecting that row returns me to the Meeting where I can stop.

### User Story 2 - Find source material (Priority: P2)

I can find the recordings saved for this Meeting in Inputs. Transcription remains visible as a separate tab for future processing.

**Why this priority** — Inputs gives users one place to find their original material.  
**Independent Test** — Record twice, reopen the Meeting, and check that both recordings appear in Inputs.

1. **Given** I open a Meeting, **when** I view its tabs, **then** Inputs appears first with an icon and Transcription is next to it.
2. **Given** a Meeting with saved inputs, **when** I select Inputs, **then** I see its saved recordings in start order. A new Meeting shows an empty state.

### Edge Cases

- While one Meeting is recording, other Meetings show Record as disabled with a reason. The sidebar row provides the route back to the recording Meeting.
- After an unexpected close or capture failure, preserve the audio already saved and mark the Recording as interrupted. A failed start creates no visible Input.
- If capture cannot start, show the reason, keep the Meeting idle, and create no Input.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001** — Show Inputs as the first tab, with an icon and accessible name, beside Transcription. Select Inputs by default when opening a Meeting.
- **FR-002** — Keep Record or Stop visible and keyboard-accessible within the Meeting across tab switches and scrolling. Use an icon-only idle control that expands on start to show white audio waves and a Stop icon. Provide distinct accessible names and respect Reduce Motion for transitions and sidebar pulsing.
- **FR-003** — Start capture only on explicit action. Capture microphone (Me) and computer audio (Other) locally as separate tracks. Allow one recording at a time and keep capture running during navigation. Follow the availability and failure behavior in Edge Cases.
- **FR-004** — Save both tracks progressively and list each saved Recording under its Meeting's Inputs tab. Keep earlier entries when a new one is added. Show an empty state when the Meeting has no Inputs.

### Key Entities

- **Meeting** — Owns its Inputs and has a source determined by its first saved Input.
- **Input** — One Recording or imported file that belongs to a Meeting.
- **Transcription** — The Meeting's unified text derived from its Inputs.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001** — Starting and stopping each takes one action from either tab in a Meeting eligible to record.
- **SC-002** — After two successful recording sessions, Inputs shows two separate entries in recording order.
- **SC-003** — In a walkthrough, the user can find where to stop an active recording and where to find the saved item, without prompting.

## Assumptions

- The approved design is option E in the [prototype](record-button-prototype.html). Inputs is the default tab. The prototype uses simulated audio levels and this slice uses live capture levels.
- This slice covers recording, local storage, and recovery. Import and transcription processing are future work. The first saved Input still determines the Meeting's source.
- Constitution principles I–V and [PRODUCT.md](../../PRODUCT.md) apply, including local operation, durable capture, source preservation, separate Me and Other tracks, and validation on the user's Mac.
