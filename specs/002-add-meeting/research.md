# Research: Create, Rename, and Navigate Meetings

## Existing implementation

Inspected Package.swift, all five source files, MeetingStoreTests.swift, scripts/build-app.sh, and the prior quickstart. The app is Swift 6/SwiftUI on macOS 14+, with no package dependencies. MeetingStore is an actor that opens SQLite per load and creates schema v1 with id, name, and createdAt. Ordering currently uses createdAt descending and UUID ascending. ContentView owns selection/list state and SidebarView owns keyboard row focus. Existing tests cover read safety, malformed records, version rejection, and rollback.

These repository observations are current planning evidence, not proof that the proposed changes work.

## Decisions

### Reuse SQLite and the actor

**Decision**: Extend the existing direct SQLite3 store; extract shared connection/schema code only as needed for create and rename.

**Rationale**: Persistence, database location, debug isolation, and failure conventions already exist. No additional ORM or concurrency layer is necessary.

**Alternatives considered**: SwiftData/Core Data or a new repository layer would expand migration and integration work without serving a requested behavior.

### Transactional v1 to v2 migration

**Decision**: Validate the old schema/records, add `updatedAt REAL NOT NULL DEFAULT 0`, backfill it from createdAt, and set user_version=2 in one immediate transaction. Fresh databases start at v2. Roll back on failure and reject newer versions.

**Rationale**: SQLite requires a non-null default for an added NOT NULL column. An explicit transaction keeps the schema, backfill, and version update atomic. Backfilling creation time avoids presenting old Meetings as newly edited.

**Alternatives considered**: Recreating or dropping the database risks data loss; assigning migration time changes user-visible history.

Sources: [SQLite ALTER TABLE](https://www.sqlite.org/lang_altertable.html), [SQLite transactions](https://www.sqlite.org/lang_transaction.html).

### Stable recency with no new sequence column

**Decision**: Use updatedAt descending, canonical UUID ascending. Assign a strictly increasing effective updatedAt inside each write transaction using the later of wall-clock now and the greatest saved timestamp's next representable value. Preserve equal legacy timestamps with UUID ties.

**Rationale**: New or genuinely renamed Meetings always move first, even for rapid saves or a backward clock. UUID tie-breaking preserves the old list's ordering when legacy creation times tie. Validate finite timestamps and reject overflow.

**Alternatives considered**: A persisted edit sequence also works but requires another column. Hidden rowid is unsuitable as a durable tie-breaker because VACUUM can change it in tables without an INTEGER PRIMARY KEY. Plain clock-only timestamps plus UUID ties cannot guarantee a new Meeting first on equal times.

The monotonic timestamp rule is a project design choice, not a SQLite feature. Source: [SQLite rowid tables](https://www.sqlite.org/rowidtable.html).

### One inline rename session

**Decision**: Bind a draft to TextField, use FocusState targets distinguishing sidebar/header, save on submit or focus loss, and cancel on Escape. Keep saved data separate from the draft. Add accessible Rename alternatives and guard pending navigation until saving succeeds.

**Rationale**: Both requested entry points share one mutation path and cannot create conflicting editors. Native field validation/focus and explicit cancellation keep accidental loss or duplicate saves observable and preventable.

**Alternatives considered**: A modal rename form adds steps; independent sidebar/header drafts can diverge. Binding one focus value to multiple active fields is ambiguous.

Sources: [TextField](https://developer.apple.com/documentation/swiftui/textfield), [FocusState](https://developer.apple.com/documentation/swiftui/focusstate), [onExitCommand](https://developer.apple.com/documentation/swiftui/view/onexitcommand(perform:)), [onTapGesture](https://developer.apple.com/documentation/swiftui/view/ontapgesture(count:perform:)). Save-on-blur and navigation policy are explicit product defaults, not API requirements. Local ui-ux-pro-max SwiftUI guidance also supports focused native fields and validation feedback.

### One visible Transcription tab

**Decision**: Use the established TabView/tabItem API with a native Label and SF Symbol text.alignleft. Keep the title above the tab container and show an empty state. Validate both label and icon in the actual macOS presentation, adapting the tab header if necessary.

**Rationale**: The package supports macOS 14. Newer Tab APIs raise the deployment requirement; one tab does not warrant a registry or future tabs.

**Alternatives considered**: A text-only heading fails the requested icon/tab presentation; placeholder Inputs or future tabs exceed current scope.

Sources: [tabItem](https://developer.apple.com/documentation/swiftui/view/tabitem(_:)), [Tab](https://developer.apple.com/documentation/swiftui/tab), [Label](https://developer.apple.com/documentation/swiftui/label).

## Research outcome

No unresolved clarifications remain. Native gesture precedence, focus after reorder, and actual tab icon visibility require implementation-time validation. No migration or UI code was executed during research.
