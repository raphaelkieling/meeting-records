# Implementation Plan: Meeting Search, Tags, and Descriptions

**Branch**: `main` | **Date**: 2026-11-23 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/008-meeting-search-tags/spec.md`

## Summary

Add a local Search view directly below Home, backed by a responsive search across meeting names, optional descriptions, available transcript text, and shared tag names. Keep the selected option A layout: text search with the AND-based multi-select tag filter to its right, followed by a concise result list with description and transcript context. Add optional meeting descriptions, shared colored tags, and a meeting context menu flow for editing descriptions and assigning tags. Store all metadata in the existing SQLite store with one additive migration and no new dependency.

## Technical Context

**Language/Version**: Swift 6.0

**Primary Dependencies**: SwiftUI, Foundation, SQLite3; existing WhisperKit / transcription dependencies are unchanged

**Storage**: Existing local SQLite database; add optional meeting description and shared tag/assignment records. Recording audio remains in the existing local files.

**Testing**: Existing XCTest target `MeetingRecordTests`; feature scenarios are described in `quickstart.md`.

**Target Platform**: macOS 14 or later on Apple Silicon, consistent with `PRODUCT.md`

**Project Type**: Native macOS desktop application

**Performance Goals**: On 1,000 meetings, 95% of searches update within 1 second after typing pauses.

**Constraints**: All metadata and search remain local and work offline. Search and tag edits must not interrupt active audio capture, transcript persistence, or normal navigation. Existing meeting, recording, transcript, and deletion recovery behavior must remain intact.

**Scale/Scope**: One user's local library with at least 1,000 meetings, associated transcript passages and shared tags; one active recording at a time.

## Constitution Check

| Principle / Gate | Assessment |
|---|---|
| I. Local processing and offline autonomy | Pass. Search and metadata use the local store; no network service or account is introduced. |
| II. Durable capture before transcription | Pass. Search is a separate read flow and tag/description writes do not change recording or transcript work. Keep store interactions bounded so recording saves retain priority. |
| III. Source preservation and reconstructable results | Pass. Search results derive from existing meetings, transcripts, tags, and descriptions; no source audio or transcript content is replaced. Meeting deletion removes assignments with the meeting while preserving reusable tag definitions, as specified. |
| IV. Transcription fidelity | Pass. Search reads current transcript passages and does not change their speaker labels, timestamps, or overlap. |
| V. Simplicity and Mac validation | Pass. Extend the existing SwiftUI and SQLite seams without a new framework or service. Validate the 1,000-meeting response goal and active-recording behavior on the target Mac. |
| Product scope update | Pass. Search, tags, and descriptions are explicitly documented in `PRODUCT.md` and this feature spec. |

**Gate result**: All gates pass. No constitution amendment is needed.

## Project Structure

### Documentation (this feature)

```text
specs/008-meeting-search-tags/
├── plan.md
├── research.md
├── data-model.md
├── contracts/
│   └── search-ui.md
└── quickstart.md
```

### Source Code (repository root)

```text
Sources/MeetingRecord/
├── ContentView.swift            # Search navigation and app-owned editing state
├── SidebarView.swift            # Search entry, meeting tags icon and context actions
├── HomeView.swift               # Existing list styling reference; no required behavior change
├── Meeting.swift                # Optional description value
├── MeetingStore.swift           # Additive schema migration, tags, descriptions, search query
└── SearchView.swift             # Search field, tag filter, results and excerpts

Tests/MeetingRecordTests/
└── MeetingStoreTests.swift      # Persistence, matching, AND filtering and migration coverage
```

The named source files are the expected implementation seams; keep view and model additions in existing files if that remains clearer after inspecting the current branch.

**Structure Decision**: This is a single-project SwiftUI desktop app. Extend the existing store and sidebar/navigation flow; add a dedicated Search view. Persist shared tags separately from meeting assignments and keep descriptions with their meeting.

## Design Decisions

- Keep `MeetingStore` as the single local data source and perform matching in a bounded store operation. Search by parameterized, case-insensitive partial match across meeting name, description, transcript text, and tag name.
- Apply each selected tag as an AND condition. Return each meeting once with assigned tags and an optional transcript excerpt.
- Begin with a bounded SQLite query over current transcript passages. Measure against the response goal before considering a full-text index; full-text matching adds extra choices for partial terms and incremental transcript changes.
- Use a transactional additive schema migration to add the nullable description, shared tags, and meeting/tag assignments. Preserve existing recordings and transcript rows. Remove assignments with a meeting; retain shared tags after their last assignment is removed.
- Store a stable palette color token on each shared tag. Stage new tags and assignment changes in the Tags modal until Save; Cancel must not persist them.
- Debounce rapid text edits in the Search view and discard stale asynchronous results so slow earlier queries cannot replace newer results. Keep database work off the main UI path.
- Add **Edit Description** beside **Tags** in each meeting's context menu. Save the optional plain text description independently of the meeting title and show it in the meeting detail view and Search result row.
- Keep prototype-only layout variants out of the production source. The selected design is option A, documented in the interaction contract and captured on branch `codex/prototype-meeting-search-tags` (commit `641920a`).

## Complexity Tracking

No constitution violations or extra project layers are required.

