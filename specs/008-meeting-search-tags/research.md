# Research: Meeting Search, Tags, and Descriptions

## Decisions

### Local persistence and schema

**Decision**: Keep SQLite in `MeetingStore` as the local source of truth. Add an optional description to meetings, a shared tag table, and a many-to-many meeting/tag assignment table in one additive schema migration.

**Rationale**: `MeetingStore` owns database access and transactional schema upgrades (`Sources/MeetingRecord/MeetingStore.swift:7-18,185-257`). Meeting rows currently store an ID, name, and timestamps (`Sources/MeetingRecord/Meeting.swift:3-18`). Existing recording and transcript relationships already use SQLite foreign keys. Deleting a meeting should remove its assignments while preserving shared tags, including unused tags, as established in the feature requirements.

**Alternatives considered**:
- Store tag names on each meeting: rejected because tags must be shared and retain one color across meetings.
- Persist description in a separate file: rejected because it would split meeting metadata and complicate deletion and search.

### Search execution

**Decision**: Use one bounded, local store search operation over meeting names, descriptions, persisted transcript passages, and shared tag names. Apply all selected tags as AND constraints. Return a meeting once, its assigned tags, and a relevant transcript excerpt when the transcript contains the text match. Begin with parameterized case-insensitive partial matching over the existing transcript segment table; avoid introducing a second index until the 1,000-meeting / 1-second / 95th-percentile goal is measured.

**Rationale**: Transcript passages are persisted incrementally, and their rows already carry text and reading-order fields (`Sources/MeetingRecord/MeetingStore.swift:497-508,638-675,700-730`). A store query avoids loading every full transcript into the UI on each keystroke. Partial matching meets the feature's simple text-search behavior. Search must remain local and must not block recording.

**Alternatives considered**:
- Load all meetings and transcripts into memory for every keystroke: rejected because it repeats work and copies potentially large transcript content into the UI.
- Add full-text indexing immediately: deferred until measurement demonstrates that a direct bounded query misses the target. Token-oriented indexing needs extra decisions for partial matches and incremental transcript updates.

### UI structure

**Decision**: Use prototype option A as the planning baseline: the existing Meeting Record sidebar remains, Search is directly below Home, and the main view has a compact text field with the multi-select tag filter immediately to its right. Results use the current app's simple list density, show the meeting name, optional description, transcript excerpt when relevant, tags, and date. The meeting context menu exposes Tags and Edit Description actions. The existing app-owned navigation state and `SidebarView` row context menu are the natural integration seams (`Sources/MeetingRecord/ContentView.swift:3-5,150-163`; `Sources/MeetingRecord/SidebarView.swift:23-26,107-139`).

**Rationale**: The user selected option A from three working variations. It keeps search controls close to the results and preserves the existing sidebar, accent color, and restrained row styling (`Sources/MeetingRecord/HomeView.swift:12-43`; `Sources/MeetingRecord/MeetingRecordApp.swift:4,15`).

**Alternatives considered**:
- Option B: a persistent filter rail on the left. Not selected; it uses more of the limited main-view width.
- Option C: centered search with quick tag chips. Not selected; it gives the view a more dashboard-like hierarchy than the existing app.

### Tag colors and shared assignments

**Decision**: Store a stable tag identifier, unique normalized name, and a color token selected from a fixed palette. Store assignments separately. Apply modal changes only on Save; Cancel discards the meeting's pending assignment changes and any not-yet-saved new tag.

**Rationale**: This supports reuse, consistent color, and the confirmed shared-tag behavior while keeping cancellation predictable. The palette's visual values can be chosen during implementation without changing the data contract.

**Alternatives considered**:
- Free-form color entry: rejected because the user asked for a predetermined palette.
- Creating tags that remain persisted after cancelling the modal: rejected because the UI contract confirms modal changes only on Save.

### Meeting descriptions

**Decision**: Make description optional plain text, editable from a meeting's context menu and shown beneath the meeting title in its detail view. Search descriptions alongside meeting names, transcripts, and tag names; show a non-empty description under the title in search results.

**Rationale**: The user explicitly asked to add a description to meetings and confirmed that search should find and show it. Keeping descriptions optional preserves the simple create-meeting flow.

**Alternatives considered**:
- Search description but hide it from results: rejected by the user's preference to search and show it.
- Require a description when creating a meeting: rejected because it adds friction to the existing quick creation flow.

