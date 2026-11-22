# Tasks: Create, Rename, and Navigate Meetings

**Input**: Design documents from `specs/002-add-meeting/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [UI contract](contracts/ui-contract.md), and [quickstart.md](quickstart.md).

**Organization**: Preserve story identifiers from the specification, but execute P1 stories first: US1, US3, then P2 stories US2 and US4. All paths below are repository-relative.

**Tests**: The specification does not explicitly request new automated tests or TDD, so no new automated-test authoring tasks are generated. Maintain compatibility of the existing XCTest suite and run it. The persistence and UI scenarios in the plan remain required as reproducible validation using isolated databases and native app inspection. Do not create tests that mirror SwiftUI layout.

## Format: `[ID] [P?] [Story] Description`

Each task uses an unchecked checkbox, sequential ID, optional [P] for independent files, a story label only in story phases, and exact file paths. [P] denotes an opportunity after its phase prerequisites are satisfied; it does not authorize starting an agent or editing the same file concurrently.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Use the existing project and establish a reproducible validation record; no new package setup is needed.

- [X] T001 Confirm the existing Swift 6/macOS 14 build and isolated-data launch procedure against Package.swift and scripts/build-app.sh, and create specs/002-add-meeting/validation.md with environment, baseline command outcomes, and pending evidence sections; follow specs/002-add-meeting/quickstart.md and keep the personal database untouched.

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Make the existing model and SQLite store ready for safe writes. Complete this phase before story work.

- [X] T002 Extend Sources/MeetingRecord/Meeting.swift with updatedAt, a shared recency comparator, and create/rename name normalization; implement the canonical constraints for Meeting.id, Meeting.name, Meeting.createdAt, and Meeting.updatedAt defined in specs/002-add-meeting/data-model.md#persisted-meeting, preserving the distinction between legacy record validation and new input normalization described in its Schema lifecycle section.
- [X] T003 Refactor only the shared connection/schema handling needed in Sources/MeetingRecord/MeetingStore.swift, keeping SQLite resources scoped and finalized; initialize fresh v2 databases, validate legacy v1 data and migrate transactionally, backfill without changing historical identity/name/creation values, and roll back or reject incompatible/malformed storage per specs/002-add-meeting/data-model.md#schema-lifecycle and its canonical Meeting.id, Meeting.name, Meeting.createdAt, and Meeting.updatedAt definitions under Persisted Meeting.
- [X] T004 Add the shared immediate-transaction write support in Sources/MeetingRecord/MeetingStore.swift: bind values, compute strictly increasing finite effective timestamps, handle empty/equal/backward-clock cases and overflow, and return committed records without a post-commit reload; resolve Meeting.createdAt and Meeting.updatedAt according to specs/002-add-meeting/data-model.md#persisted-meeting and its Ordering and write rules section.
- [X] T005 Adapt existing initializers, positional inserts, expected schema versions, and unsupported-future-version fixtures in Tests/MeetingRecordTests/MeetingStoreTests.swift to the v2 model while retaining explicit legacy-v1 coverage/fixtures and the existing malformed-data, rollback, read-failure, Unicode, and duplicate-name checks; use v3 for unsupported future versions and do not erase existing checks.

**Checkpoint**: The model and database support v2 without destructive migration. Existing suite compiles against the changed model. Detailed migration evidence is completed in T018.

## Phase 3: User Story 1 - Create a Meeting from the Sidebar (Priority: P1) — MVP

**Goal**: One plus activation creates, saves, reveals, and opens a distinct empty Meeting.

**Independent validation**: Start with an isolated empty database; create from each destination and restart offline. One activation adds one persisted UUID with the same name visible in the row and main title. A failed save preserves the previous list and selection.

- [X] T006 [P] [US1] Implement createMeeting(id:name:) in Sources/MeetingRecord/MeetingStore.swift using T004; persist the caller's creation identity, return an existing record unchanged for the same retried ID, and establish its timestamps without creating Inputs or transcript data; follow Meeting.id, Meeting.name, Meeting.createdAt, and Meeting.updatedAt in specs/002-add-meeting/data-model.md#persisted-meeting and its Ordering and write rules section.
- [X] T007 [P] [US1] Add the fixed Meetings heading-row plus Button in Sources/MeetingRecord/SidebarView.swift with an injected creation action and availability state, accessible name/help "Add Meeting", native keyboard focus, loading/pending disabled states, and selected-new-row reveal behavior; keep Home, Settings, and the heading outside the scroll area per specs/002-add-meeting/contracts/ui-contract.md#sidebar.
- [X] T008 [US1] Wire creation in Sources/MeetingRecord/ContentView.swift using T006 and T007: generate a small random English name and one UUID per logical request, serialize mutations, merge/sort the committed result using the shared comparator, select/reveal it, and expose retryable mutation errors separately from load errors without replacing the saved list or starting audio/network work.
- [X] T009 [US1] Execute the Create and restart scenarios in specs/002-add-meeting/quickstart.md and record actual outcomes in specs/002-add-meeting/validation.md: empty-list transition, creation from all destinations, deliberate repeated activations versus pending requests, persisted identity/name after restart, keyboard Add Meeting, and write-lock failure/retry with no phantom or duplicate row; defer the final tab appearance to US4.

**Checkpoint**: The creation-only MVP works. Opening a Meeting may still use the existing detail placeholder until US4.

## Phase 4: User Story 3 - Rename a Meeting in Place (Priority: P1)

**Goal**: Edit either visible Meeting name inline and safely save, cancel, or recover from failure.

**Independent validation**: Rename an existing or newly created Meeting first from its sidebar name and then its main title. Both surfaces and persisted data agree, changed saves move it first, and cancellation/no-op/failure does not change recency.

- [X] T010 [US3] Implement renameMeeting(id:name:) in Sources/MeetingRecord/MeetingStore.swift through the shared transaction path, handling missing identity, normalized no-op, and save failure while preserving creation information; implement Meeting.id, Meeting.name, Meeting.createdAt, and Meeting.updatedAt as defined in specs/002-add-meeting/data-model.md#persisted-meeting and its Ordering and write rules section.
- [X] T011 [US3] Add one rename-session coordinator to Sources/MeetingRecord/ContentView.swift with UUID, origin, draft, error, mutation status, and pending action; route both entry points through it, merge/sort only committed records, retain invalid/failed drafts and saved values, and deduplicate Enter/focus-loss saves according to specs/002-add-meeting/data-model.md#transient-state.
- [X] T012 [US3] Implement the sidebar inline name field in Sources/MeetingRecord/SidebarView.swift using the shared session: retain single-click selection, start rename on double-click, add context-menu Rename and focused Shift-Command-R access, distinguish field focus from row focus, support Enter/blur save and Escape cancel, and prevent sidebar arrow commands from intercepting text editing; preserve focus on the same UUID after save/reorder.
- [X] T013 [US3] Implement the main-title inline editor in Sources/MeetingRecord/ContentView.swift with a distinct header focus target, double-click and keyboard/context-menu entry, accessible field label/help, validation/save feedback, and retry/cancel; keep the other name surface on its saved value until commit as required by specs/002-add-meeting/contracts/ui-contract.md#inline-rename-at-both-locations.
- [X] T014 [US3] Route destination changes, Add Meeting, and starting another rename through the shared edit coordinator in Sources/MeetingRecord/ContentView.swift and Sources/MeetingRecord/SidebarView.swift: successful/no-op commits continue the pending action exactly once, invalid/save failures keep the editor and current destination, Escape discards draft and pending action, and pending writes prevent overlapping submissions or editor replacement.
- [X] T015 [US3] Execute the Rename and recency scenarios and write-lock failure/recovery procedure from specs/002-add-meeting/quickstart.md, recording evidence in specs/002-add-meeting/validation.md for both edit surfaces, Unicode/apostrophes/duplicate/long names, blank and NUL rejection, whitespace trimming, no-op, Escape, Enter plus blur deduplication, pending navigation/create/edit behavior, and focus after reordering.

**Checkpoint**: Existing Meetings can be renamed without needing creation. The existing list is updated by UUID and real changed saves move the affected Meeting first. Full persisted-list ordering follows in US2.

## Phase 5: User Story 2 - Find the Most Recently Updated Meeting First (Priority: P2)

**Goal**: Make persisted loading and in-memory mutation results use the same stable recency order.

**Independent validation**: Seed three Meetings with different updatedAt values and a pair with equal values; load, rename the oldest, reopen, and compare identity/order. Viewing alone leaves timestamps unchanged.

- [X] T016 [US2] Change loading in Sources/MeetingRecord/MeetingStore.swift to updatedAt descending and canonical UUID ascending, and align loaded results with mutation merge ordering in Sources/MeetingRecord/ContentView.swift using the comparator in Sources/MeetingRecord/Meeting.swift; follow the Meeting.id and Meeting.updatedAt definitions in specs/002-add-meeting/data-model.md#persisted-meeting and its Ordering and write rules section without advancing timestamps for selection, reads, app launch, or failed/no-op writes.
- [X] T017 [US2] Validate ordering with isolated v2 fixtures via specs/002-add-meeting/quickstart.md and record results in specs/002-add-meeting/validation.md: distinct/equal timestamps, stable restart order, old Meeting rename to first, selection and focus remaining on UUID, repeated viewing with unchanged stored times, and creation/rename ahead of a fixture timestamp later than wall-clock now; use controlled input rather than changing the system clock.
- [X] T018 [US2] Run the isolated legacy-v1 migration and failure scenarios in specs/002-add-meeting/quickstart.md, supplementing that guide with exact fixture commands where needed; record row counts, preserved identities/names/createdAt, backfilled updatedAt, stable legacy ties, repeated reopen, invalid schema/records, migration rollback, and unknown-v3 rejection in specs/002-add-meeting/validation.md without modifying the personal database.

**Checkpoint**: Persisted and visible order are consistent after migration, writes, and reopening. US2's UI rename acceptance scenario can now be exercised end-to-end through US3.

## Phase 6: User Story 4 - Open the Transcription Workspace (Priority: P2)

**Goal**: Show exactly one selected Transcription tab, with icon and empty content, beneath the editable title.

**Independent validation**: Open two Meetings and create another. Each shows the correct title above a single selected Transcription tab with visible icon/text and "No transcription yet."

- [X] T019 [US4] Replace the Meeting detail placeholder in Sources/MeetingRecord/ContentView.swift with a macOS-14-compatible single Transcription tab beneath the editable title, using text.alignleft and the exact empty-state text from specs/002-add-meeting/contracts/ui-contract.md#main-content; expose tab selection accessibly without duplicate icon announcements, keep Home/Settings separate, and add no Inputs tab, transcript persistence, processing controls, or tab registry.
- [X] T020 [US4] Inspect the actual native tab presentation using specs/002-add-meeting/quickstart.md and record evidence in specs/002-add-meeting/validation.md for new/existing Meetings, switching, selected semantics, visible label plus icon, and preserved title editing at 720×480; if the native TabView style hides the icon, adjust only the tab header in Sources/MeetingRecord/ContentView.swift using the plan's native-styled labeled-header fallback and recheck accessibility.

**Checkpoint**: All four user stories are complete; no future tabs have been introduced.

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Finish language consistency and verify the complete feature on the user's Mac.

- [X] T021 Translate remaining strings touched by this feature in Sources/MeetingRecord/ContentView.swift, Sources/MeetingRecord/SidebarView.swift, and Sources/MeetingRecord/Meeting.swift to English, including storage/validation failures and retry labels; preserve existing navigation/error behavior and leave unrelated project content unchanged.
- [X] T022 Run the build, existing XCTest suite, and native debug bundle procedure from specs/002-add-meeting/quickstart.md using Package.swift and scripts/build-app.sh; resolve integration/compiler/regression failures in the affected Sources/MeetingRecord/ files and Tests/MeetingRecordTests/MeetingStoreTests.swift, and record commands/results and any actual environment limitations in specs/002-add-meeting/validation.md.
- [ ] T023 Complete the cross-story native review from specs/002-add-meeting/quickstart.md and specs/002-add-meeting/contracts/ui-contract.md; record 100-Meeting create-to-visible timing, fixed headings/scrolling, long-name discovery, both rename surfaces, focus/keyboard/VoiceOver, light/dark appearance, minimum window, offline/no-audio-permission behavior, and failure recovery in specs/002-add-meeting/validation.md, correcting observed defects in the affected source files and updating the quickstart only where the runnable procedure changed.

## Dependencies & Execution Order

### Phase dependencies

Setup T001 → foundational T002–T005 → US1 T006–T009 → US3 T010–T015 → US2 T016–T018 → US4 T019–T020 → polish T021–T023.

Within foundation, T003 follows T002; T004 follows T003; T005 follows the model/schema changes. T008 waits for both T006 and T007. All validation tasks follow the corresponding implementation. T022 runs after source changes finish; fix/recheck only affected checks if T023 finds defects.

### Story dependency graph

```text
Setup → Foundation → US1 (P1, MVP) → US3 (P1) → US2 (P2) → US4 (P2) → Final validation
```

This is the recommended integration order because the feature touches the same few files. US3's store operation and editing behavior can be exercised with persisted fixtures rather than requiring US1's plus button; this sequence reuses the shared UI mutation handling established by US1. US2's SQL ordering can be validated with fixtures after foundation, but its rename-driven acceptance scenario depends on US3. US4 needs only a selected persisted Meeting; it is sequenced after rename because both modify ContentView.swift. Each phase has an independent acceptance procedure once its prerequisites are met.

### Parallel opportunities and examples per story

- **US1**: After foundation, T006 [P] (MeetingStore.swift) and T007 [P] (SidebarView.swift) can proceed independently against their documented method/action contracts. Integrate them in T008; validate in T009.
- **US3**: Keep T010–T014 sequential: the shared coordinator, title, sidebar bindings, and action gating depend on each other. There is no safe additional same-story implementation parallelism in these files. T015 follows integration.
- **US2**: Keep T016 before T017/T018. Do not concurrently update the shared validation.md or quickstart.md while recording the ordering and migration scenarios.
- **US4**: T020 depends on T019's running UI; icon fallback depends on what is actually observed. No speculative parallel implementation is needed.

No parallel agents are required. Small shared files make sequential integration simpler; do not manufacture independent modules to create parallel work.

## Implementation Strategy

### MVP first

Complete setup, foundation, and US1. Validate single-activation creation, persistence/reopen, and failure recovery. This is a reviewable creation-only increment; it does not fulfill the entire requested feature yet.

### Incremental delivery

Add US3's inline rename at both locations, then US2's persisted recency ordering, then US4's visible Transcription tab. Validate each checkpoint and finish cross-story review. Record actual evidence rather than declaring acceptance from source inspection alone. No publishing, branch creation, new dependency, or deployment is required.

### Constraint traceability and completion

The implementing tasks explicitly resolve every constrained persisted field to the canonical Persisted Meeting table in data-model.md: Meeting.id and Meeting.name → T002/T003/T006/T010; Meeting.createdAt → T002/T003/T004/T006/T010; Meeting.updatedAt → T002/T003/T004/T006/T010/T016. Transient edit state and relationships are implemented in T011–T014 and T019. Every functional requirement is assigned: FR-001–005 and FR-008–010 → US1/final review; FR-006–007 and FR-011 → foundation/US2; FR-012–014 and FR-016 → US3; FR-015 → US4.

Mark tasks complete only after their actual outcomes are verified. The generation of this file does not mark implementation or validation complete. No before_tasks or after_tasks hooks are registered because .specify/extensions.yml is absent.

## Implementation outcome (2026-11-22)

T001–T022 are complete; results are recorded in [validation.md](validation.md). T023 remains partially complete: native layout, light/dark appearance, minimum-size production-view wrapper, keyboard/AX semantics, scale timing, and failure recovery were reviewed. A full spoken VoiceOver-only session and a physically disconnected-network run remain unverified. The deployment target is macOS 14, but runtime testing used macOS 27.2.1. No implementation work remains in the four user stories; these remaining items are validation limits, not claimed passes.
