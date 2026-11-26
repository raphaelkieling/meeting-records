import Foundation
import CryptoKit
import SQLite3

actor MeetingStore {
    private let databaseURL: URL?
    private var didOpenChatIndex = false

    init(databaseURL: URL? = nil) {
        self.databaseURL = databaseURL
    }

    static func defaultDatabaseURL(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        #if DEBUG
        if let directory = environment["MEETING_RECORD_DATA_DIR"] {
            guard directory.hasPrefix("/") else { throw MeetingStoreError.invalidDirectory }
            return URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent("meetings.sqlite")
        }
        #endif
        return try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                           appropriateFor: nil, create: false)
            .appendingPathComponent("MeetingRecord", isDirectory: true)
            .appendingPathComponent("meetings.sqlite")
    }

    func loadMeetings() throws -> [Meeting] {
        try withDatabase { try readMeetings(db: $0) }
    }

    struct HomeSummary: Sendable {
        let meetings: [Meeting]
        let savedRecordingCount: Int
        let recordedTime: TimeInterval
        let missingDurationIDs: [UUID]
        let completedTranscriptions: Int
    }

    func loadHomeSummary() throws -> HomeSummary {
        try withDatabase { db in
            try transaction(db: db, readOnly: true) {
                let meetings = try readMeetings(db: db, recentOnly: true)
                let statement = try prepare("""
                    SELECT count(*), coalesce(sum(r.duration), 0), coalesce(sum(j.status = 'Complete'), 0)
                    FROM recordings r LEFT JOIN transcript_jobs j ON j.inputID = r.id
                    WHERE r.endedAt IS NOT NULL
                    """, db: db)
                defer { sqlite3_finalize(statement) }
                let result = sqlite3_step(statement)
                guard result == SQLITE_ROW else { throw MeetingStoreError.sqlite(result) }
                let missing = try chatRows("""
                    SELECT id FROM recordings WHERE endedAt IS NOT NULL AND duration IS NULL ORDER BY startedAt, id
                    """, [], db: db) { row in
                        guard let id = text(row, column: 0).flatMap(UUID.init(uuidString:))
                        else { throw MeetingStoreError.invalidRecord }
                        return id
                    }
                return HomeSummary(meetings: meetings, savedRecordingCount: Int(sqlite3_column_int64(statement, 0)),
                                   recordedTime: sqlite3_column_double(statement, 1), missingDurationIDs: missing,
                                   completedTranscriptions: Int(sqlite3_column_int64(statement, 2)))
            }
        }
    }

    func createMeeting(id: UUID, name: String, description: String? = nil,
                       calendarEventDate: Date? = nil, calendarName: String? = nil,
                       calendarDetails: CalendarEventDetails? = nil) throws -> Meeting {
        let name = try Meeting.normalizedName(name)
        let description = Meeting.normalizedDescription(description)
        return try withDatabase { db in
            try transaction(db: db) {
                let meetings = try readMeetings(db: db)
                if let existing = meetings.first(where: { $0.id == id }) { return existing }
                guard try !exists("SELECT 1 FROM pending_meeting_deletions WHERE meetingID = ?", id: id, db: db)
                else { throw MeetingStoreError.notFound }
                let time = try nextUpdate(after: meetings)
                let meeting = try Meeting(id: id, name: name, description: description, createdAt: time, updatedAt: time,
                                          calendarEventDate: calendarEventDate, calendarName: calendarName)
                let statement = try prepare("INSERT INTO meetings(id, name, description, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?)", db: db)
                defer { sqlite3_finalize(statement) }
                try bind(id.uuidString, at: 1, to: statement)
                try bind(name, at: 2, to: statement)
                try bind(description, at: 3, to: statement)
                try check(sqlite3_bind_double(statement, 4, time.timeIntervalSince1970))
                try check(sqlite3_bind_double(statement, 5, time.timeIntervalSince1970))
                try finish(statement)
                try insertSidebarItem(id: id, meetingID: id, name: nil, db: db)
                if let calendarEventDate, let calendarName {
                    let source = try prepare("""
                        INSERT INTO calendar_meeting_inputs(meetingID, eventDate, calendarName, details)
                        VALUES (?, ?, ?, ?)
                        """, db: db)
                    defer { sqlite3_finalize(source) }
                    try bind(id.uuidString, at: 1, to: source)
                    try check(sqlite3_bind_double(source, 2, calendarEventDate.timeIntervalSince1970))
                    try bind(calendarName, at: 3, to: source)
                    let encoded = try calendarDetails.map { try String(decoding: JSONEncoder().encode($0), as: UTF8.self) }
                    try bind(encoded, at: 4, to: source)
                    try finish(source)
                }
                return meeting
            }
        }
    }

    func renameMeeting(id: UUID, name: String) throws -> Meeting {
        try updateMeeting(id: id, name: name, metadata: nil)
    }

    func updateMeeting(id: UUID, name: String, description: String?, selectedTagIDs: Set<UUID>) throws -> Meeting {
        try updateMeeting(id: id, name: name, metadata: (Meeting.normalizedDescription(description), selectedTagIDs))
    }

    private func updateMeeting(id: UUID, name: String, metadata: (description: String?, tags: Set<UUID>)?) throws -> Meeting {
        let name = try Meeting.normalizedName(name)
        return try withDatabase { db in
            try transaction(db: db) {
                let meetings = try readMeetings(db: db)
                guard let existing = meetings.first(where: { $0.id == id }) else { throw MeetingStoreError.notFound }
                let description = if let metadata { metadata.description } else { existing.description }
                var updatedAt = existing.updatedAt
                if existing.name != name || existing.description != description {
                    updatedAt = try nextUpdate(after: meetings)
                    let statement = try prepare("""
                        UPDATE meetings SET name = ?, description = ?, updatedAt = ? WHERE upper(id) = ?
                        """, db: db)
                    defer { sqlite3_finalize(statement) }
                    try bind(name, at: 1, to: statement)
                    try bind(description, at: 2, to: statement)
                    try check(sqlite3_bind_double(statement, 3, updatedAt.timeIntervalSince1970))
                    try bind(id.uuidString, at: 4, to: statement)
                    try finish(statement)
                    guard sqlite3_changes(db) == 1 else { throw MeetingStoreError.notFound }
                }

                var tags = existing.tags
                if let metadata, metadata.tags != Set(tags.map(\.id)) {
                    try writeMeetingTags(meetingID: id, selectedTagIDs: metadata.tags, newTags: [], db: db)
                    tags = try readTagsByMeeting(db: db)[id] ?? []
                }
                return try Meeting(id: id, name: name, description: description, tags: tags,
                                   createdAt: existing.createdAt, updatedAt: updatedAt,
                                   calendarEventDate: existing.calendarEventDate, calendarName: existing.calendarName)
            }
        }
    }

    func allTags() throws -> [Tag] {
        try withDatabase { try readAllTags(db: $0) }
    }

    func saveTag(_ tag: Tag, updating: Bool) throws {
        try withDatabase { db in
            try transaction(db: db) {
                let existing = try readAllTags(db: db)
                guard !existing.contains(where: { $0.id != tag.id && $0.normalizedKey == tag.normalizedKey }) else {
                    throw MeetingStoreError.duplicateTagName
                }
                try writeTag(tag, updating: updating, db: db)
            }
        }
    }

    func deleteTag(_ id: UUID) throws {
        try withDatabase { db in
            try transaction(db: db) {
                try execute("DELETE FROM meeting_tags WHERE tagID = ?", id: id, db: db)
                try execute("DELETE FROM tags WHERE id = ?", id: id, db: db)
            }
        }
    }

    private func writeTag(_ tag: Tag, updating: Bool = false, db: OpaquePointer) throws {
        let sql = updating
            ? "UPDATE tags SET name = ?2, normalizedName = ?3, color = ?4 WHERE id = ?1"
            : "INSERT INTO tags(id, name, normalizedName, color) VALUES (?, ?, ?, ?)"
        let statement = try prepare(sql, db: db)
        defer { sqlite3_finalize(statement) }
        try bind(tag.id.uuidString, at: 1, to: statement)
        try bind(tag.name, at: 2, to: statement)
        try bind(tag.normalizedKey, at: 3, to: statement)
        try bind(tag.color.rawValue, at: 4, to: statement)
        try finish(statement)
        guard sqlite3_changes(db) == 1 else { throw MeetingStoreError.notFound }
    }

    private func readAllTags(db: OpaquePointer) throws -> [Tag] {
        let statement = try prepare("SELECT id, name, color FROM tags ORDER BY normalizedName, id", db: db)
        defer { sqlite3_finalize(statement) }
        var tags: [Tag] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return tags }
            guard code == SQLITE_ROW,
                  let id = text(statement, column: 0).flatMap(UUID.init(uuidString:)),
                  let name = text(statement, column: 1),
                  let color = text(statement, column: 2).flatMap(TagColor.init(rawValue:)) else {
                throw MeetingStoreError.invalidRecord
            }
            tags.append(try Tag(id: id, name: name, color: color))
        }
    }

    func saveMeetingTags(meetingID: UUID, selectedTagIDs: Set<UUID>, newTags: [Tag]) throws {
        try withDatabase { db in
            try transaction(db: db) {
                guard try exists("SELECT 1 FROM meetings WHERE upper(id) = ?", id: meetingID, db: db) else {
                    throw MeetingStoreError.notFound
                }
                try writeMeetingTags(meetingID: meetingID, selectedTagIDs: selectedTagIDs, newTags: newTags, db: db)
            }
        }
    }

    private func writeMeetingTags(meetingID: UUID, selectedTagIDs: Set<UUID>, newTags: [Tag], db: OpaquePointer) throws {
        let existingTags = try readAllTags(db: db)
        var normalizedNames = Set(existingTags.map(\.normalizedKey))
        var validTagIDs = Set(existingTags.map(\.id))
        for tag in newTags {
            guard normalizedNames.insert(tag.normalizedKey).inserted else { throw MeetingStoreError.duplicateTagName }
            guard validTagIDs.insert(tag.id).inserted else { throw MeetingStoreError.invalidRecord }
        }
        guard selectedTagIDs.isSubset(of: validTagIDs) else { throw MeetingStoreError.notFound }
        for tag in newTags { try writeTag(tag, db: db) }
        try execute("DELETE FROM meeting_tags WHERE upper(meetingID) = ?", id: meetingID, db: db)
        for tagID in selectedTagIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            let statement = try prepare("""
                INSERT INTO meeting_tags(meetingID, tagID)
                SELECT id, ? FROM meetings WHERE upper(id) = ?
                """, db: db)
            defer { sqlite3_finalize(statement) }
            try bind(tagID.uuidString, at: 1, to: statement)
            try bind(meetingID.uuidString, at: 2, to: statement)
            try finish(statement)
        }
    }

    func deleteMeeting(_ id: UUID) throws {
        try withDatabase { db in
            try transaction(db: db) {
                let owner = "upper(meetingID) = ?"
                guard try !exists("SELECT 1 FROM recordings WHERE \(owner) AND endedAt IS NULL", id: id, db: db)
                else { throw MeetingStoreError.meetingRecording }

                try removeChatMeetingData(id, db: db)
                try execute("DELETE FROM recordings WHERE \(owner)", id: id, db: db)
                try execute("DELETE FROM meetings WHERE upper(id) = ?", id: id, db: db)
                guard sqlite3_changes(db) == 1 else { throw MeetingStoreError.notFound }
                try execute("INSERT INTO pending_meeting_deletions VALUES (?)", id: id, db: db)
            }
        }
    }

    func deleteAllMeetings() throws -> [UUID] {
        try withDatabase { db in
            try transaction(db: db) {
                let ids = try readMeetings(db: db).map(\.id)
                for id in ids {
                    guard try !exists("SELECT 1 FROM recordings WHERE upper(meetingID) = ? AND endedAt IS NULL LIMIT 1",
                                      id: id, db: db)
                    else { throw MeetingStoreError.meetingRecording }
                    try removeChatMeetingData(id, db: db)
                    try execute("DELETE FROM recordings WHERE upper(meetingID) = ?", id: id, db: db)
                    try execute("DELETE FROM meetings WHERE upper(id) = ?", id: id, db: db)
                    try execute("INSERT INTO pending_meeting_deletions VALUES (?)", id: id, db: db)
                }
                try execute("DELETE FROM sidebar_items", db: db)
                return ids
            }
        }
    }

    func pendingMeetingDeletions() throws -> [UUID] {
        try withDatabase { db in
            let statement = try prepare("SELECT meetingID FROM pending_meeting_deletions ORDER BY meetingID", db: db)
            defer { sqlite3_finalize(statement) }
            var ids: [UUID] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { return ids }
                guard result == SQLITE_ROW else { throw MeetingStoreError.sqlite(result) }
                guard let id = text(statement, column: 0).flatMap(UUID.init(uuidString:))
                else { throw MeetingStoreError.invalidRecord }
                ids.append(id)
            }
        }
    }

    func finishMeetingDeletion(_ id: UUID) throws {
        try withDatabase { db in
            try execute("DELETE FROM pending_meeting_deletions WHERE meetingID = ?", id: id, db: db)
        }
    }

    private func nextUpdate(after meetings: [Meeting]) throws -> Date {
        var value = Date().timeIntervalSince1970
        if let latest = meetings.map({ $0.updatedAt.timeIntervalSince1970 }).max() {
            value = max(value, latest.nextUp)
        }
        guard value.isFinite else { throw MeetingStoreError.invalidRecord }
        return Date(timeIntervalSince1970: value)
    }

    func recordingRoot() throws -> URL {
        let url = try databaseURL ?? Self.defaultDatabaseURL()
        return url.deletingLastPathComponent().appendingPathComponent("Recordings", isDirectory: true)
    }

    func removeCalendarLink(from meetingID: UUID) throws -> Meeting {
        try withDatabase { db in
            try transaction(db: db) {
                let meetings = try readMeetings(db: db)
                guard let meeting = meetings.first(where: { $0.id == meetingID }) else { throw MeetingStoreError.notFound }
                try execute("DELETE FROM calendar_meeting_inputs WHERE upper(meetingID) = ?", id: meetingID, db: db)
                guard sqlite3_changes(db) == 1 else { return meeting }
                let updatedAt = try nextUpdate(after: meetings)
                let statement = try prepare("UPDATE meetings SET updatedAt = ? WHERE upper(id) = ?", db: db)
                defer { sqlite3_finalize(statement) }
                try check(sqlite3_bind_double(statement, 1, updatedAt.timeIntervalSince1970))
                try bind(meetingID.uuidString, at: 2, to: statement)
                try finish(statement)
                return try Meeting(id: meetingID, name: meeting.name, description: meeting.description,
                                   tags: meeting.tags, createdAt: meeting.createdAt, updatedAt: updatedAt)
            }
        }
    }

    func scheduledEnd(for meetingID: UUID) throws -> Date? {
        try withDatabase { db in
            let statement = try prepare("SELECT details FROM calendar_meeting_inputs WHERE meetingID = ?", db: db)
            defer { sqlite3_finalize(statement) }
            try bind(meetingID.uuidString, at: 1, to: statement)
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { throw MeetingStoreError.sqlite(result) }
            guard let details = text(statement, column: 0) else { return nil }
            return try JSONDecoder().decode(CalendarEventDetails.self, from: Data(details.utf8)).endDate
        }
    }

    private func withDatabase<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        let url = try databaseURL ?? Self.defaultDatabaseURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        defer { if let handle { sqlite3_close(handle) } }
        guard result == SQLITE_OK, let db = handle else { throw MeetingStoreError.sqlite(result) }
        try check(sqlite3_busy_timeout(db, 3_000))
        try execute("PRAGMA foreign_keys = ON", db: db)
        try ensureSchema(db: db)
        return try operation(db)
    }

    private func schemaVersion(db: OpaquePointer) throws -> Int32 {
        let statement = try prepare("PRAGMA user_version", db: db)
        let step = sqlite3_step(statement)
        let version = sqlite3_column_int(statement, 0)
        sqlite3_finalize(statement)
        guard step == SQLITE_ROW else { throw MeetingStoreError.sqlite(step) }
        guard (0...13).contains(version) else { throw MeetingStoreError.incompatibleVersion }
        return version
    }

    private func ensureSchema(db: OpaquePointer) throws {
        guard try schemaVersion(db: db) < 13 else { return }
        try transaction(db: db) {
            let version = try schemaVersion(db: db)
            guard version < 13 else { return }
            if version < 3 {
                if version == 0 {
                    try execute("""
                        CREATE TABLE meetings (
                            id TEXT PRIMARY KEY NOT NULL,
                            name TEXT NOT NULL CHECK(length(trim(name)) > 0),
                            createdAt REAL NOT NULL,
                            updatedAt REAL NOT NULL
                        )
                        """, db: db)
                } else if version == 1 {
                    // Validate before altering the schema so invalid historical data leaves no partial upgrade.
                    _ = try readMeetings(db: db, legacy: true)
                    try execute("ALTER TABLE meetings ADD COLUMN updatedAt REAL NOT NULL DEFAULT 0", db: db)
                    try execute("UPDATE meetings SET updatedAt = createdAt", db: db)
                }
                try execute("""
                    CREATE TABLE recordings (
                        id TEXT PRIMARY KEY NOT NULL,
                        meetingID TEXT NOT NULL REFERENCES meetings(id),
                        startedAt REAL NOT NULL,
                        endedAt REAL,
                        state TEXT NOT NULL CHECK(state IN ('starting', 'recording', 'completed', 'interrupted')),
                        CHECK((endedAt IS NULL) = (state IN ('starting', 'recording')))
                    )
                    """, db: db)
                try execute("""
                    CREATE UNIQUE INDEX one_open_recording ON recordings ((1))
                    WHERE state IN ('starting', 'recording')
                    """, db: db)
                try execute("""
                    CREATE TABLE audio_segments (
                        recordingID TEXT NOT NULL REFERENCES recordings(id) ON DELETE CASCADE,
                        source TEXT NOT NULL CHECK(source IN ('me', 'other')),
                        startOffset INTEGER NOT NULL CHECK(startOffset >= 0),
                        frameCount INTEGER NOT NULL CHECK(frameCount > 0),
                        relativePath TEXT NOT NULL UNIQUE,
                        PRIMARY KEY (recordingID, source, startOffset)
                    )
                    """, db: db)
            }
            if version < 4 { try createTranscriptionTables(db) }
            if version < 5 {
                try execute("""
                    CREATE TABLE pending_meeting_deletions (meetingID TEXT PRIMARY KEY NOT NULL)
                    """, db: db)
            }
            if version < 6 {
                try execute("""
                    CREATE TABLE meeting_summaries (
                        meetingID TEXT PRIMARY KEY NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
                        text TEXT NOT NULL,
                        model TEXT NOT NULL,
                        transcriptRevision TEXT NOT NULL
                    );
                    PRAGMA user_version = 6;
                    """, db: db)
            }
            if version < 7 {
                try execute("""
                    ALTER TABLE meetings ADD COLUMN description TEXT;
                    CREATE TABLE tags (
                        id TEXT PRIMARY KEY NOT NULL,
                        name TEXT NOT NULL CHECK(length(trim(name)) > 0),
                        normalizedName TEXT NOT NULL UNIQUE,
                        color TEXT NOT NULL CHECK(color IN ('gold', 'lavender', 'green', 'coral', 'blue', 'rose'))
                    );
                    CREATE TABLE meeting_tags (
                        meetingID TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
                        tagID TEXT NOT NULL REFERENCES tags(id) ON DELETE RESTRICT,
                        PRIMARY KEY (meetingID, tagID)
                    );
                    CREATE INDEX meeting_tags_by_tag ON meeting_tags(tagID, meetingID);
                    PRAGMA user_version = 7;
                    """, db: db)
            }
            if version < 8 {
                try execute("CREATE TABLE calendar_meeting_inputs(meetingID TEXT PRIMARY KEY NOT NULL REFERENCES meetings(id) ON DELETE CASCADE, eventDate REAL NOT NULL, calendarName TEXT NOT NULL); PRAGMA user_version = 8;", db: db)
            }
            if version < 9 {
                try execute("""
                    ALTER TABLE calendar_meeting_inputs ADD COLUMN details TEXT;
                    PRAGMA user_version = 9;
                    """, db: db)
            }
            if version < 10 { try createChatTables(db) }
            if version < 11 {
                try execute("""
                    ALTER TABLE audio_segments ADD COLUMN duration REAL CHECK(duration > 0);
                    ALTER TABLE recordings ADD COLUMN duration REAL CHECK(duration >= 0);
                    CREATE INDEX recording_missing_duration ON recordings(startedAt, id)
                    WHERE endedAt IS NOT NULL AND duration IS NULL;
                    PRAGMA user_version = 11;
                    """, db: db)
            }
            if version < 12 {
                try execute("""
                    CREATE TABLE pending_recording_deletions (
                        recordingID TEXT PRIMARY KEY NOT NULL,
                        meetingID TEXT NOT NULL
                    );
                    PRAGMA user_version = 12;
                    """, db: db)
            }
            if version < 13 {
                try execute("""
                    CREATE TABLE sidebar_items (
                        id TEXT PRIMARY KEY NOT NULL,
                        meetingID TEXT UNIQUE REFERENCES meetings(id) ON DELETE CASCADE,
                        parentID TEXT REFERENCES sidebar_items(id),
                        position INTEGER NOT NULL,
                        name TEXT,
                        color TEXT,
                        expanded INTEGER NOT NULL DEFAULT 1,
                        CHECK ((meetingID IS NULL AND name IS NOT NULL) OR
                               (meetingID IS NOT NULL AND name IS NULL AND color IS NULL))
                    );
                    CREATE INDEX sidebar_items_order ON sidebar_items(parentID, position, id);
                    INSERT INTO sidebar_items(id, meetingID, position)
                        SELECT upper(id), id, row_number() OVER (ORDER BY updatedAt DESC, upper(id)) FROM meetings;
                    CREATE TABLE pending_uncompressed_audio (relativePath TEXT PRIMARY KEY NOT NULL);
                    PRAGMA user_version = 13;
                    """, db: db)
            }
        }
    }

    private func readMeetings(db: OpaquePointer, legacy: Bool = false, recentOnly: Bool = false) throws -> [Meeting] {
        let updateColumn = legacy ? "createdAt" : "updatedAt"
        let orderColumn = recentOnly ? "createdAt" : updateColumn
        let limit = recentOnly ? " LIMIT 3" : ""
        let calendarColumns = legacy ? "NULL, NULL" : "ci.eventDate, ci.calendarName"
        let calendarJoin = legacy ? "" : "LEFT JOIN calendar_meeting_inputs ci ON ci.meetingID = m.id"
        let statement = try prepare("""
            SELECT m.id, m.name, \(legacy ? "NULL" : "m.description"), m.createdAt, m.\(updateColumn), \(calendarColumns) FROM meetings m
            \(calendarJoin)
            ORDER BY \(orderColumn) DESC, upper(id) ASC\(limit)
            """, db: db)
        defer { sqlite3_finalize(statement) }
        var meetings: [Meeting] = []
        var ids: Set<UUID> = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw MeetingStoreError.sqlite(code) }
            guard let idString = text(statement, column: 0), let name = text(statement, column: 1),
                  idString.utf8.count == 36, let id = UUID(uuidString: idString), ids.insert(id).inserted,
                  [SQLITE_FLOAT, SQLITE_INTEGER].contains(sqlite3_column_type(statement, 3)),
                  [SQLITE_FLOAT, SQLITE_INTEGER].contains(sqlite3_column_type(statement, 4)) else {
                throw MeetingStoreError.invalidRecord
            }
            meetings.append(try Meeting(id: id, name: name,
                description: text(statement, column: 2),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                calendarEventDate: sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                calendarName: text(statement, column: 6)))
        }
        guard !legacy, !meetings.isEmpty else { return meetings }
        let tagsByMeeting = try readTagsByMeeting(db: db)
        return try meetings.map { meeting in
            try Meeting(id: meeting.id, name: meeting.name, description: meeting.description,
                        tags: tagsByMeeting[meeting.id] ?? [], createdAt: meeting.createdAt, updatedAt: meeting.updatedAt,
                        calendarEventDate: meeting.calendarEventDate, calendarName: meeting.calendarName)
        }
    }

    private func readTagsByMeeting(db: OpaquePointer) throws -> [UUID: [Tag]] {
        let statement = try prepare("""
            SELECT mt.meetingID, t.id, t.name, t.color FROM meeting_tags mt
            JOIN tags t ON t.id = mt.tagID ORDER BY lower(t.name), t.id
            """, db: db)
        defer { sqlite3_finalize(statement) }
        var result: [UUID: [Tag]] = [:]
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return result }
            guard code == SQLITE_ROW,
                  let meetingID = text(statement, column: 0).flatMap(UUID.init(uuidString:)),
                  let id = text(statement, column: 1).flatMap(UUID.init(uuidString:)),
                  let name = text(statement, column: 2),
                  let color = text(statement, column: 3).flatMap(TagColor.init(rawValue:)) else {
                throw MeetingStoreError.invalidRecord
            }
            result[meetingID, default: []].append(try Tag(id: id, name: name, color: color))
        }
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
              let bytes = sqlite3_column_text(statement, column) else { return nil }
        return String(bytes: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, column))), encoding: .utf8)
    }

    private func transaction<T>(db: OpaquePointer, readOnly: Bool = false, _ operation: () throws -> T) throws -> T {
        try execute(readOnly ? "BEGIN" : "BEGIN IMMEDIATE", db: db)
        do {
            let result = try operation()
            try execute("COMMIT", db: db)
            return result
        } catch {
            try? execute("ROLLBACK", db: db)
            throw error
        }
    }

    private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) throws {
        try check(value.withCString { sqlite3_bind_text(statement, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) })
    }

    private func bind(_ value: String?, at index: Int32, to statement: OpaquePointer) throws {
        if let value { try bind(value, at: index, to: statement) }
        else { try check(sqlite3_bind_null(statement, index)) }
    }

    private func check(_ code: Int32) throws {
        guard code == SQLITE_OK else { throw MeetingStoreError.sqlite(code) }
    }

    private func finish(_ statement: OpaquePointer) throws {
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE else { throw MeetingStoreError.sqlite(code) }
    }

    private func exists(_ sql: String, id: UUID, db: OpaquePointer) throws -> Bool {
        let statement = try prepare(sql, db: db)
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, at: 1, to: statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW || result == SQLITE_DONE else { throw MeetingStoreError.sqlite(result) }
        return result == SQLITE_ROW
    }

    private func execute(_ sql: String, id: UUID, db: OpaquePointer) throws {
        let statement = try prepare(sql, db: db)
        defer { sqlite3_finalize(statement) }
        try bind(id.uuidString, at: 1, to: statement)
        try finish(statement)
    }

    private func execute(_ sql: String, db: OpaquePointer) throws {
        try check(sqlite3_exec(db, sql, nil, nil, nil))
    }

    private func prepare(_ sql: String, db: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else {
            if let statement { sqlite3_finalize(statement) }
            throw MeetingStoreError.sqlite(code)
        }
        return statement
    }
}

extension MeetingStore {
    func beginRecording(_ recording: Recording) throws {
        try withDatabase { db in
            let statement = try prepare("""
                INSERT INTO recordings (id, meetingID, startedAt, state)
                SELECT ?, id, ?, 'starting' FROM meetings WHERE upper(id) = ?
                """, db: db)
            defer { sqlite3_finalize(statement) }
            try bind(recording.id.uuidString, at: 1, to: statement)
            try check(sqlite3_bind_double(statement, 2, recording.startedAt.timeIntervalSince1970))
            try bind(recording.meetingID.uuidString, at: 3, to: statement)
            try finish(statement)
            guard sqlite3_changes(db) == 1 else { throw MeetingStoreError.notFound }
        }
    }

    func markRecordingStarted(_ id: UUID) throws {
        try withDatabase { db in
            let statement = try prepare("UPDATE recordings SET state = 'recording' WHERE id = ? AND state = 'starting'", db: db)
            defer { sqlite3_finalize(statement) }
            try bind(id.uuidString, at: 1, to: statement)
            try finish(statement)
            guard sqlite3_changes(db) == 1 else { throw MeetingStoreError.notFound }
        }
    }

    func registerSegment(_ segment: AudioSegment, duration: TimeInterval? = nil) throws {
        try withDatabase { db in
            let statement = try prepare("""
                INSERT INTO audio_segments (recordingID, source, startOffset, frameCount, relativePath, duration)
                VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(recordingID, source, startOffset) DO UPDATE SET duration = excluded.duration
                WHERE audio_segments.duration IS NULL AND excluded.duration IS NOT NULL
                """, db: db)
            defer { sqlite3_finalize(statement) }
            try bind(segment.recordingID.uuidString, at: 1, to: statement)
            try bind(segment.source.rawValue, at: 2, to: statement)
            try check(sqlite3_bind_int64(statement, 3, segment.startOffset))
            try check(sqlite3_bind_int64(statement, 4, segment.frameCount))
            try bind(segment.relativePath, at: 5, to: statement)
            if let duration, duration.isFinite, duration > 0 {
                try check(sqlite3_bind_double(statement, 6, duration))
            }
            try finish(statement)
        }
    }

    func audioSegments(for recordingID: UUID) throws -> [AudioSegment] {
        try withDatabase { db in
            let statement = try prepare("""
                SELECT source, startOffset, frameCount, relativePath FROM audio_segments
                WHERE recordingID = ? ORDER BY startOffset, source
                """, db: db)
            defer { sqlite3_finalize(statement) }
            try bind(recordingID.uuidString, at: 1, to: statement)

            var segments: [AudioSegment] = []
            while true {
                let code = sqlite3_step(statement)
                if code == SQLITE_DONE { return segments }
                guard code == SQLITE_ROW else { throw MeetingStoreError.sqlite(code) }
                guard let source = text(statement, column: 0).flatMap(AudioSegment.Source.init(rawValue:)),
                      let path = text(statement, column: 3), !path.isEmpty
                else { throw MeetingStoreError.invalidRecord }
                segments.append(AudioSegment(recordingID: recordingID, source: source,
                    startOffset: sqlite3_column_int64(statement, 1),
                    frameCount: sqlite3_column_int64(statement, 2), relativePath: path))
            }
        }
    }

    @discardableResult
    func finalizeRecording(_ id: UUID, endedAt: Date, interrupted: Bool) throws -> Bool {
        try withDatabase { db in
            try transaction(db: db) {
                let update = try prepare("""
                    UPDATE recordings SET state = ?, endedAt = max(startedAt, ?), duration = (
                        SELECT CASE WHEN count(duration) = count(*) THEN max(startOffset / 1e9 + duration) END
                        FROM audio_segments WHERE recordingID = recordings.id
                    )
                    WHERE id = ? AND state IN ('starting', 'recording')
                    AND EXISTS (SELECT 1 FROM audio_segments WHERE recordingID = recordings.id)
                    """, db: db)
                defer { sqlite3_finalize(update) }
                try bind(interrupted ? "interrupted" : "completed", at: 1, to: update)
                try check(sqlite3_bind_double(update, 2, endedAt.timeIntervalSince1970))
                try bind(id.uuidString, at: 3, to: update)
                try finish(update)
                if sqlite3_changes(db) == 1 { return true }

                let owners = try chatRows("""
                    SELECT meetingID FROM recordings WHERE id = ? AND state IN ('starting', 'recording')
                    """, [id.uuidString], db: db) { row in
                        text(row, column: 0).flatMap(UUID.init(uuidString:))
                    }
                if let owner = owners.first ?? nil,
                   try !screenCaptures(meetingID: owner, recordingID: id).isEmpty {
                    try chatWrite("""
                        INSERT INTO pending_recording_deletions (recordingID, meetingID)
                        VALUES (?, ?)
                        """, [id.uuidString, owner.uuidString], db: db)
                }
                let remove = try prepare("DELETE FROM recordings WHERE id = ? AND state IN ('starting', 'recording')", db: db)
                defer { sqlite3_finalize(remove) }
                try bind(id.uuidString, at: 1, to: remove)
                try finish(remove)
                return false
            }
        }
    }

    func deleteRecording(_ recording: Recording) throws {
        try withDatabase { db in
            try transaction(db: db) {
                try chatWrite("""
                    INSERT INTO pending_recording_deletions (recordingID, meetingID)
                    SELECT id, meetingID FROM recordings
                    WHERE upper(id) = ? AND upper(meetingID) = ? AND endedAt IS NOT NULL
                    """, [recording.id.uuidString, recording.meetingID.uuidString], db: db)
                guard sqlite3_changes(db) == 1 else {
                    if try exists("SELECT 1 FROM recordings WHERE upper(id) = ? AND endedAt IS NULL",
                                  id: recording.id, db: db) { throw MeetingStoreError.meetingRecording }
                    throw MeetingStoreError.notFound
                }
                try removeChatRecordingData(recording.id, db: db)
                try execute("DELETE FROM recordings WHERE upper(id) = ?", id: recording.id, db: db)
            }
        }
    }

    struct PendingRecordingDeletion: Sendable {
        let recordingID: UUID
        let meetingID: UUID
    }

    func pendingRecordingDeletions() throws -> [PendingRecordingDeletion] {
        try withDatabase { db in
            try chatRows("SELECT recordingID, meetingID FROM pending_recording_deletions", db: db) { row in
                guard let recordingID = text(row, column: 0).flatMap(UUID.init(uuidString:)),
                      let meetingID = text(row, column: 1).flatMap(UUID.init(uuidString:))
                else { throw MeetingStoreError.invalidRecord }
                return PendingRecordingDeletion(recordingID: recordingID, meetingID: meetingID)
            }
        }
    }

    func finishRecordingDeletion(_ id: UUID) throws {
        try withDatabase { db in
            try execute("DELETE FROM pending_recording_deletions WHERE upper(recordingID) = ?", id: id, db: db)
        }
    }

    func saveRecordingDuration(_ duration: TimeInterval, for id: UUID) throws {
        guard duration.isFinite, duration >= 0 else { throw MeetingStoreError.invalidRecord }
        try withDatabase { db in
            let statement = try prepare("UPDATE recordings SET duration = ? WHERE id = ? AND endedAt IS NOT NULL AND duration IS NULL", db: db)
            defer { sqlite3_finalize(statement) }
            try check(sqlite3_bind_double(statement, 1, duration))
            try bind(id.uuidString, at: 2, to: statement)
            try finish(statement)
        }
    }

    func recordings(for meetingID: UUID, includeActive: Bool = false) throws -> [Recording] {
        try readRecordings(meetingID: meetingID, includeActive: includeActive)
    }

    func unfinishedRecordings() throws -> [Recording] {
        try readRecordings(meetingID: nil)
    }

    private func readRecordings(meetingID: UUID?, includeActive: Bool = false) throws -> [Recording] {
        try withDatabase { db in
            let condition = meetingID == nil ? "endedAt IS NULL" : "upper(meetingID) = ? AND (endedAt IS NOT NULL OR state = 'recording' AND \(includeActive ? 1 : 0))"
            let statement = try prepare("""
                SELECT id, meetingID, startedAt, endedAt, state FROM recordings
                WHERE \(condition) ORDER BY startedAt, id
                """, db: db)
            defer { sqlite3_finalize(statement) }
            if let meetingID { try bind(meetingID.uuidString, at: 1, to: statement) }

            var recordings: [Recording] = []
            while true {
                let code = sqlite3_step(statement)
                if code == SQLITE_DONE { return recordings }
                guard code == SQLITE_ROW else { throw MeetingStoreError.sqlite(code) }
                guard let id = text(statement, column: 0).flatMap(UUID.init(uuidString:)),
                      let owner = text(statement, column: 1).flatMap(UUID.init(uuidString:)),
                      let state = text(statement, column: 4).flatMap(Recording.State.init(rawValue:))
                else { throw MeetingStoreError.invalidRecord }
                let end = sqlite3_column_type(statement, 3) == SQLITE_NULL
                    ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
                recordings.append(Recording(id: id, meetingID: owner,
                    startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                    endedAt: end, state: state))
            }
        }
    }
}

extension MeetingStore {
    private func createTranscriptionTables(_ db: OpaquePointer) throws {
        try execute("""
            CREATE TABLE transcript_jobs (
                inputID TEXT PRIMARY KEY NOT NULL REFERENCES recordings(id) ON DELETE CASCADE,
                status TEXT NOT NULL CHECK(status IN ('Pending', 'Transcribing', 'Complete')),
                modelID TEXT NOT NULL,
                modelVersion TEXT NOT NULL,
                lastError TEXT,
                updatedAt REAL NOT NULL
            );
            CREATE TABLE transcript_progress (
                inputID TEXT NOT NULL REFERENCES transcript_jobs(inputID) ON DELETE CASCADE,
                source TEXT NOT NULL CHECK(source IN ('me', 'other')),
                checkpoint INTEGER NOT NULL,
                processedThrough INTEGER NOT NULL,
                PRIMARY KEY (inputID, source)
            );
            CREATE TABLE transcript_segments (
                inputID TEXT NOT NULL REFERENCES transcript_jobs(inputID) ON DELETE CASCADE,
                source TEXT NOT NULL CHECK(source IN ('me', 'other')),
                checkpoint INTEGER NOT NULL,
                sequence INTEGER NOT NULL,
                startOffset INTEGER NOT NULL,
                endOffset INTEGER NOT NULL CHECK(endOffset >= startOffset),
                text TEXT NOT NULL,
                PRIMARY KEY (inputID, source, checkpoint, sequence)
            );
            CREATE INDEX transcript_reading_order ON transcript_segments(inputID, startOffset);
            """, db: db)
    }

    func resetTranscriptionQueue() throws {
        try withDatabase {
            try execute("""
                UPDATE transcript_jobs SET status = 'Pending', lastError = NULL, updatedAt = unixepoch()
                WHERE status = 'Transcribing' OR lastError IS NOT NULL
                """, db: $0)
        }
    }

    func retryDeferredTranscripts(unstartedOnly: Bool = false) throws {
        try withDatabase {
            let filter = unstartedOnly
                ? " AND NOT EXISTS (SELECT 1 FROM transcript_progress p WHERE p.inputID = transcript_jobs.inputID)" : ""
            try execute("UPDATE transcript_jobs SET lastError = NULL WHERE lastError IS NOT NULL" + filter, db: $0)
        }
    }

    private static let unprocessedAudio = """
        a.startOffset > coalesce((SELECT p.checkpoint FROM transcript_progress p
            WHERE p.inputID = a.recordingID AND p.source = a.source), -1)
        """

    func finishDrainedTranscripts() throws -> Bool {
        try withDatabase { db in
            try execute("""
                UPDATE transcript_jobs SET status = 'Complete', updatedAt = unixepoch()
                WHERE status != 'Complete' AND lastError IS NULL
                AND EXISTS (SELECT 1 FROM recordings r WHERE r.id = inputID AND r.endedAt IS NOT NULL)
                AND NOT EXISTS (SELECT 1 FROM audio_segments a WHERE a.recordingID = inputID
                    AND \(Self.unprocessedAudio))
                """, db: db)
            return sqlite3_changes(db) > 0
        }
    }

    func nextTranscriptionWork() throws -> TranscriptionWork? {
        try withDatabase { db in
            let statement = try prepare("""
                SELECT r.id, a.source, a.startOffset, a.frameCount, a.relativePath,
                    CASE WHEN has_progress.inputID IS NOT NULL THEN j.modelID END,
                    CASE WHEN has_progress.inputID IS NOT NULL THEN j.modelVersion END
                FROM audio_segments a JOIN recordings r ON r.id = a.recordingID
                LEFT JOIN transcript_jobs j ON j.inputID = r.id
                LEFT JOIN (SELECT DISTINCT inputID FROM transcript_progress) has_progress ON has_progress.inputID = r.id
                WHERE j.lastError IS NULL AND coalesce(j.status, 'Pending') != 'Complete'
                AND \(Self.unprocessedAudio)
                ORDER BY r.endedAt IS NOT NULL, r.startedAt, r.id, a.source, a.startOffset
                """, db: db)
            defer { sqlite3_finalize(statement) }
            var result = sqlite3_step(statement)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { throw MeetingStoreError.sqlite(result) }
            guard let id = text(statement, column: 0).flatMap(UUID.init(uuidString:)),
                  let source = text(statement, column: 1).flatMap(AudioSegment.Source.init(rawValue:)),
                  let path = text(statement, column: 4)
            else { throw MeetingStoreError.invalidRecord }
            let first = AudioSegment(recordingID: id, source: source, startOffset: sqlite3_column_int64(statement, 2),
                                     frameCount: sqlite3_column_int64(statement, 3), relativePath: path)
            let modelID = text(statement, column: 5)
            let modelVersion = text(statement, column: 6)
            var audioSegments = [first]
            var duration = Double(first.frameCount) / 48_000
            var previousEnd = first.startOffset + Int64((duration * 1e9).rounded())
            while duration < 10 {
                result = sqlite3_step(statement)
                guard result == SQLITE_ROW else { break }
                guard text(statement, column: 0).flatMap(UUID.init(uuidString:)) == id,
                      text(statement, column: 1) == source.rawValue,
                      let nextPath = text(statement, column: 4) else { break }
                let next = AudioSegment(recordingID: id, source: source,
                    startOffset: sqlite3_column_int64(statement, 2), frameCount: sqlite3_column_int64(statement, 3),
                    relativePath: nextPath)
                guard abs(next.startOffset - previousEnd) <= 250_000_000 else { break }
                audioSegments.append(next)
                let nextDuration = Double(next.frameCount) / 48_000
                duration += nextDuration
                previousEnd = next.startOffset + Int64((nextDuration * 1e9).rounded())
            }
            return TranscriptionWork(audio: first, audioSegments: audioSegments, modelID: modelID,
                                     modelVersion: modelVersion)
        }
    }

    enum TranscriptClaim { case removed, unchanged, changed }

    func claimTranscript(_ id: UUID, model: TranscriptionModel) throws -> TranscriptClaim {
        try withDatabase { db in
            try transaction(db: db) {
                guard try exists("SELECT 1 FROM recordings WHERE id = ?", id: id, db: db)
                else { return .removed }
                let pause = try prepare("""
                    UPDATE transcript_jobs SET status = 'Pending', updatedAt = unixepoch()
                    WHERE status = 'Transcribing' AND inputID != ?
                    """, db: db)
                defer { sqlite3_finalize(pause) }
                try bind(id.uuidString, at: 1, to: pause)
                try finish(pause)
                let statement = try prepare("""
                    INSERT INTO transcript_jobs(inputID, status, modelID, modelVersion, lastError, updatedAt)
                    VALUES (?, 'Transcribing', ?, ?, NULL, unixepoch())
                    ON CONFLICT(inputID) DO UPDATE SET status = 'Transcribing', updatedAt = unixepoch(),
                        modelID = excluded.modelID, modelVersion = excluded.modelVersion
                    WHERE status != 'Transcribing' OR modelID != excluded.modelID OR modelVersion != excluded.modelVersion
                    """, db: db)
                defer { sqlite3_finalize(statement) }
                try bind(id.uuidString, at: 1, to: statement)
                try bind(model.id, at: 2, to: statement)
                try bind(model.version, at: 3, to: statement)
                try finish(statement)
                return sqlite3_changes(db) > 0 ? .changed : .unchanged
            }
        }
    }

    func deferTranscript(_ id: UUID, error: String) throws {
        try withDatabase { db in
            let statement = try prepare("""
                UPDATE transcript_jobs SET status = 'Pending', lastError = ?, updatedAt = unixepoch()
                WHERE inputID = ?
                """, db: db)
            defer { sqlite3_finalize(statement) }
            try bind(error, at: 1, to: statement)
            try bind(id.uuidString, at: 2, to: statement)
            try finish(statement)
        }
    }

    func saveTranscript(_ audio: AudioSegment, result: TranscribedCheckpoint) throws {
        try saveTranscript([audio], result: result)
    }

    func saveTranscript(_ audioSegments: [AudioSegment], result: TranscribedCheckpoint) throws {
        guard let audio = audioSegments.first, let last = audioSegments.last else { return }
        try withDatabase { db in
            try transaction(db: db) {
                guard try exists("SELECT 1 FROM transcript_jobs WHERE inputID = ?", id: audio.recordingID, db: db)
                else { return }
                let insert = try prepare("INSERT OR REPLACE INTO transcript_segments VALUES (?, ?, ?, ?, ?, ?, ?)", db: db)
                defer { sqlite3_finalize(insert) }
                for (index, segment) in result.segments.enumerated() {
                    try check(sqlite3_reset(insert))
                    try bind(audio.recordingID.uuidString, at: 1, to: insert)
                    try bind(audio.source.rawValue, at: 2, to: insert)
                    try check(sqlite3_bind_int64(insert, 3, audio.startOffset))
                    try check(sqlite3_bind_int64(insert, 4, Int64(index)))
                    try check(sqlite3_bind_int64(insert, 5, segment.startOffset))
                    try check(sqlite3_bind_int64(insert, 6, segment.endOffset))
                    try bind(segment.text, at: 7, to: insert)
                    try finish(insert)
                }
                let progress = try prepare("""
                    INSERT INTO transcript_progress VALUES (?, ?, ?, ?)
                    ON CONFLICT(inputID, source) DO UPDATE SET checkpoint = excluded.checkpoint,
                        processedThrough = excluded.processedThrough WHERE checkpoint < excluded.checkpoint
                    """, db: db)
                defer { sqlite3_finalize(progress) }
                try bind(audio.recordingID.uuidString, at: 1, to: progress)
                try bind(audio.source.rawValue, at: 2, to: progress)
                try check(sqlite3_bind_int64(progress, 3, last.startOffset))
                try check(sqlite3_bind_int64(progress, 4, result.processedThrough))
                try finish(progress)
                let update = try prepare("UPDATE transcript_jobs SET updatedAt = unixepoch() WHERE inputID = ?", db: db)
                defer { sqlite3_finalize(update) }
                try bind(audio.recordingID.uuidString, at: 1, to: update)
                try finish(update)
            }
        }
    }

    func transcriptStatuses(for meetingID: UUID) throws -> [UUID: TranscriptStatus] {
        try withDatabase { db in
            let statement = try prepare("""
                SELECT j.inputID, j.status, j.lastError FROM transcript_jobs j
                JOIN recordings r ON r.id = j.inputID WHERE upper(r.meetingID) = ?
                """, db: db)
            defer { sqlite3_finalize(statement) }
            try bind(meetingID.uuidString, at: 1, to: statement)
            var statuses: [UUID: TranscriptStatus] = [:]
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { return statuses }
                guard result == SQLITE_ROW else { throw MeetingStoreError.sqlite(result) }
                guard let id = text(statement, column: 0).flatMap(UUID.init(uuidString:)),
                      let status = text(statement, column: 1).flatMap(TranscriptionStatus.init(rawValue:))
                else { throw MeetingStoreError.invalidRecord }
                statuses[id] = TranscriptStatus(status: status, error: text(statement, column: 2))
            }
        }
    }

    func transcriptPassages(for meetingID: UUID) throws -> [TranscriptPassage] {
        try withDatabase { try readTranscriptPassages(for: meetingID, db: $0) }
    }

    private func readTranscriptPassages(for meetingID: UUID,
                                        recordingID: UUID? = nil,
                                        window: ClosedRange<Int64>? = nil,
                                        db: OpaquePointer) throws -> [TranscriptPassage] {
        let statement = try prepare("""
            SELECT s.inputID, s.source, s.checkpoint, s.sequence, s.startOffset, s.endOffset, s.text
            FROM transcript_segments s JOIN recordings r ON r.id = s.inputID
            WHERE upper(r.meetingID) = ?
              AND (?2 IS NULL OR r.id = ?2)
              AND (?3 IS NULL OR s.endOffset >= ?3)
              AND (?4 IS NULL OR s.startOffset <= ?4)
            ORDER BY r.startedAt, r.id, s.startOffset, s.source, s.checkpoint, s.sequence
            """, db: db)
        defer { sqlite3_finalize(statement) }
        try bind(meetingID.uuidString, at: 1, to: statement)
        if let recordingID { try bind(recordingID.uuidString, at: 2, to: statement) }
        if let window {
            try check(sqlite3_bind_int64(statement, 3, window.lowerBound))
            try check(sqlite3_bind_int64(statement, 4, window.upperBound))
        }
        var passages: [TranscriptPassage] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return passages }
            guard result == SQLITE_ROW else { throw MeetingStoreError.sqlite(result) }
            guard let id = text(statement, column: 0).flatMap(UUID.init(uuidString:)),
                  let source = text(statement, column: 1).flatMap(AudioSegment.Source.init(rawValue:)),
                  let value = text(statement, column: 6)
            else { throw MeetingStoreError.invalidRecord }
            guard TranscriptPassage.hasWords(value) else { continue }
            passages.append(TranscriptPassage(inputID: id, source: source,
                checkpoint: sqlite3_column_int64(statement, 2), sequence: sqlite3_column_int64(statement, 3),
                startOffset: sqlite3_column_int64(statement, 4), endOffset: sqlite3_column_int64(statement, 5), text: value))
        }
    }
}

extension MeetingStore {
    func summarySnapshot(for meetingID: UUID) throws -> MeetingSummarySnapshot {
        try withDatabase { db in
            try transaction(db: db, readOnly: true) {
                let passages = try readTranscriptPassages(for: meetingID, db: db)
                let pending = try exists("""
                    SELECT 1 FROM recordings r LEFT JOIN transcript_jobs j ON j.inputID = r.id
                    WHERE upper(r.meetingID) = ? AND (r.endedAt IS NULL OR j.status IS NOT 'Complete')
                    """, id: meetingID, db: db)
                let statement = try prepare("""
                    SELECT text, model, transcriptRevision FROM meeting_summaries WHERE upper(meetingID) = ?
                    """, db: db)
                defer { sqlite3_finalize(statement) }
                try bind(meetingID.uuidString, at: 1, to: statement)
                let result = sqlite3_step(statement)
                let saved: MeetingSummary?
                if result == SQLITE_ROW {
                    guard let body = text(statement, column: 0), let model = text(statement, column: 1),
                          let revision = text(statement, column: 2) else { throw MeetingStoreError.invalidRecord }
                    saved = .init(text: body, model: model, transcriptRevision: revision)
                } else {
                    guard result == SQLITE_DONE else { throw MeetingStoreError.sqlite(result) }
                    saved = nil
                }
                var transcript = ""
                var revision = SHA256()
                var recording: UUID?
                var index = 0
                for passage in passages {
                    if recording != passage.inputID {
                        index += 1
                        recording = passage.inputID
                        transcript += "\nRecording \(index)\n"
                    }
                    let speaker = passage.source == .me ? "Me" : "Other"
                    let seconds = passage.startOffset / 1_000_000_000
                    let time = String(format: "%lld:%02lld", seconds / 60, seconds % 60)
                    transcript += "\(time) \(speaker): \(passage.text)\n"
                    revision.update(data: Data("\(passage.id):\(passage.startOffset):\(passage.endOffset):\(passage.text.utf8.count):".utf8))
                    revision.update(data: Data(passage.text.utf8))
                }
                let context = try summaryContext(for: meetingID, db: db)
                if !context.isEmpty {
                    revision.update(data: Data("\nMeeting context:\n".utf8))
                    revision.update(data: Data(context.utf8))
                }
                return .init(summary: saved, transcript: transcript, context: context,
                             transcriptRevision: revision.finalize().description, hasPendingAudio: pending)
            }
        }
    }

    private func summaryContext(for meetingID: UUID, db: OpaquePointer) throws -> String {
        let statement = try prepare("""
            SELECT m.name, m.description, ci.calendarName, ci.eventDate, ci.details
            FROM meetings m LEFT JOIN calendar_meeting_inputs ci ON ci.meetingID = m.id
            WHERE upper(m.id) = ?
            """, db: db)
        defer { sqlite3_finalize(statement) }
        try bind(meetingID.uuidString, at: 1, to: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return "" }
        guard result == SQLITE_ROW else { throw MeetingStoreError.sqlite(result) }

        let title = text(statement, column: 0)
        let description = text(statement, column: 1)
        let details = try text(statement, column: 4).map {
            try JSONDecoder().decode(CalendarEventDetails.self, from: Data($0.utf8))
        }
        let start = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil
            : Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
        let attendees = details?.attendees.joined(separator: ", ")
        let fields: [(String, String?, Int)] = [
            ("Meeting title", title, 200),
            ("Calendar title", details?.title == title ? nil : details?.title, 200),
            ("Calendar", text(statement, column: 2), 100),
            ("Scheduled start", start?.ISO8601Format(), 50),
            ("Scheduled end", details?.endDate?.ISO8601Format(), 50),
            ("Organizer", details?.organizer, 150),
            ("Invitees", attendees, 700),
            ("Meeting description", description, 1200),
            ("Calendar description", details?.notes == description ? nil : details?.notes, 1200)
        ]
        // Leave room for transcript chunks in the on-device model's context window.
        return fields.compactMap { label, value, limit in
            guard let value, !value.isEmpty else { return nil }
            return "\(label): \(String(decoding: value.utf8.prefix(limit), as: UTF8.self))"
        }.joined(separator: "\n")
    }

    func saveSummary(_ summary: MeetingSummary, for meetingID: UUID) throws {
        try withDatabase { db in
            let statement = try prepare("""
                INSERT INTO meeting_summaries (meetingID, text, model, transcriptRevision)
                SELECT id, ?, ?, ? FROM meetings WHERE upper(id) = ?
                ON CONFLICT(meetingID) DO UPDATE SET text = excluded.text, model = excluded.model,
                    transcriptRevision = excluded.transcriptRevision
                """, db: db)
            defer { sqlite3_finalize(statement) }
            try bind(summary.text, at: 1, to: statement)
            try bind(summary.model, at: 2, to: statement)
            try bind(summary.transcriptRevision, at: 3, to: statement)
            try bind(meetingID.uuidString, at: 4, to: statement)
            try finish(statement)
            guard sqlite3_changes(db) == 1 else { throw MeetingStoreError.notFound }
        }
    }
}

extension MeetingStore {
    func searchMeetings(_ query: SearchQuery) throws -> [SearchResult] {
        let needle = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty || !query.selectedTagIDs.isEmpty else { return [] }
        let pattern = "%" + needle
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "%"
        let tagIDs = query.selectedTagIDs.sorted { $0.uuidString < $1.uuidString }
        let textFilter = needle.isEmpty ? "" : """
            AND (m.name COLLATE NOCASE LIKE ? ESCAPE '\\'
                 OR coalesce(m.description, '') COLLATE NOCASE LIKE ? ESCAPE '\\'
                 OR EXISTS (SELECT 1 FROM transcript_segments s JOIN recordings r ON r.id = s.inputID
                            WHERE upper(r.meetingID) = upper(m.id) AND s.text COLLATE NOCASE LIKE ? ESCAPE '\\')
                 OR EXISTS (SELECT 1 FROM meeting_tags mt JOIN tags t ON t.id = mt.tagID
                            WHERE mt.meetingID = m.id AND t.name COLLATE NOCASE LIKE ? ESCAPE '\\'))
            """
        let selectedTagFilter = tagIDs.isEmpty ? "" : """
            AND (SELECT count(DISTINCT upper(tagID)) FROM meeting_tags
                 WHERE upper(meetingID) = upper(m.id) AND upper(tagID) IN (\(Array(repeating: "?", count: tagIDs.count).joined(separator: ",")))) = ?
            """
        let excerptColumn = needle.isEmpty ? "NULL" : """
            (SELECT s.text FROM transcript_segments s JOIN recordings r ON r.id = s.inputID
             WHERE upper(r.meetingID) = upper(m.id) AND s.text COLLATE NOCASE LIKE ? ESCAPE '\\'
             ORDER BY r.startedAt, r.id, s.startOffset, s.source, s.checkpoint, s.sequence LIMIT 1)
            """
        let sql = """
            SELECT m.id, m.name, m.description, m.createdAt, m.updatedAt, \(excerptColumn)
            FROM meetings m WHERE 1 = 1 \(textFilter) \(selectedTagFilter)
            ORDER BY m.updatedAt DESC, upper(m.id) ASC
            """
        return try withDatabase { db in
            let statement = try prepare(sql, db: db)
            defer { sqlite3_finalize(statement) }
            var parameter: Int32 = 1
            if !needle.isEmpty {
                try bind(pattern, at: parameter, to: statement)
                parameter += 1
                for _ in 0..<4 {
                    try bind(pattern, at: parameter, to: statement)
                    parameter += 1
                }
            }
            for id in tagIDs {
                try bind(id.uuidString, at: parameter, to: statement)
                parameter += 1
            }
            if !tagIDs.isEmpty {
                try check(sqlite3_bind_int64(statement, parameter, Int64(tagIDs.count)))
            }

            let tagsByMeeting = try readTagsByMeeting(db: db)
            var results: [SearchResult] = []
            while true {
                let code = sqlite3_step(statement)
                if code == SQLITE_DONE { return results }
                guard code == SQLITE_ROW,
                      let id = text(statement, column: 0).flatMap(UUID.init(uuidString:)),
                      let name = text(statement, column: 1),
                      [SQLITE_FLOAT, SQLITE_INTEGER].contains(sqlite3_column_type(statement, 3)),
                      [SQLITE_FLOAT, SQLITE_INTEGER].contains(sqlite3_column_type(statement, 4)) else {
                    throw MeetingStoreError.invalidRecord
                }
                let assignedTags = tagsByMeeting[id] ?? []
                let meeting = try Meeting(id: id, name: name, description: text(statement, column: 2),
                    tags: assignedTags,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)))
                let matchedTranscript = text(statement, column: 5)
                results.append(SearchResult(meeting: meeting, assignedTags: assignedTags,
                    transcriptExcerpt: matchedTranscript.map { Self.transcriptExcerpt($0, around: needle) }))
            }
        }
    }

    private static func transcriptExcerpt(_ text: String, around needle: String) -> String {
        let source = text as NSString
        let match = source.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive])
        let location = match.location == NSNotFound ? 0 : match.location
        let start = max(0, location - 54)
        let length = min(source.length - start, 180)
        let excerpt = source.substring(with: NSRange(location: start, length: length))
        return (start > 0 ? "…" : "") + excerpt + (start + length < source.length ? "…" : "")
    }
}

extension MeetingStore {
    private func createChatTables(_ db: OpaquePointer) throws {
        try execute("""
            ALTER TABLE transcript_jobs ADD COLUMN chatRevision INTEGER NOT NULL DEFAULT 0;
            CREATE TRIGGER chat_revision_insert AFTER INSERT ON transcript_segments BEGIN
                UPDATE transcript_jobs SET chatRevision = chatRevision + 1 WHERE inputID = NEW.inputID;
            END;
            CREATE TRIGGER chat_revision_update AFTER UPDATE ON transcript_segments BEGIN
                UPDATE transcript_jobs SET chatRevision = chatRevision + 1 WHERE inputID = NEW.inputID;
            END;
            CREATE TRIGGER chat_revision_delete AFTER DELETE ON transcript_segments BEGIN
                UPDATE transcript_jobs SET chatRevision = chatRevision + 1 WHERE inputID = OLD.inputID;
            END;
            CREATE TABLE chat_indexed (
                recordingID TEXT PRIMARY KEY NOT NULL REFERENCES recordings(id) ON DELETE CASCADE,
                revision INTEGER NOT NULL
            );
            CREATE TABLE chat_chunks (
                id INTEGER PRIMARY KEY,
                recordingID TEXT NOT NULL REFERENCES chat_indexed(recordingID) ON DELETE CASCADE,
                passageIDs TEXT NOT NULL,
                startOffset INTEGER NOT NULL CHECK(startOffset >= 0),
                endOffset INTEGER NOT NULL CHECK(endOffset >= startOffset)
            );
            CREATE INDEX chat_chunks_recording ON chat_chunks(recordingID);
            CREATE TABLE chat_conversations (
                id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL CHECK(length(trim(title)) > 0),
                scope TEXT, updatedAt REAL NOT NULL
            );
            CREATE TABLE chat_messages (
                id TEXT PRIMARY KEY NOT NULL,
                conversationID TEXT NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
                ordinal INTEGER NOT NULL CHECK(ordinal >= 0),
                role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
                body TEXT NOT NULL, status TEXT NOT NULL,
                requestID TEXT, citations TEXT NOT NULL DEFAULT '[]',
                UNIQUE(conversationID, ordinal),
                CHECK((role = 'user' AND requestID IS NULL AND status = 'complete' AND length(trim(body)) > 0)
                      OR (role = 'assistant' AND requestID IS NOT NULL))
            );
            CREATE TABLE chat_sources (
                messageID TEXT NOT NULL REFERENCES chat_messages(id) ON DELETE CASCADE,
                meetingID TEXT NOT NULL,
                PRIMARY KEY(messageID, meetingID)
            );
            CREATE INDEX chat_sources_meeting ON chat_sources(meetingID);
            PRAGMA user_version = 10;
            """, db: db)
    }

    func loadChatHistory(recovering: Bool = false) throws -> [ChatConversation] {
        try withDatabase { db in
            try transaction(db: db, readOnly: !recovering) {
                if recovering {
                    try execute("UPDATE chat_messages SET status = 'interrupted' WHERE status IN ('pending', 'streaming')", db: db)
                }
                let threads = try chatRows("SELECT id, title, scope, updatedAt FROM chat_conversations ORDER BY updatedAt DESC, id",
                                           db: db) { row -> ChatConversation in
                    guard let id = text(row, column: 0).flatMap(UUID.init(uuidString:)),
                          let title = text(row, column: 1) else { throw MeetingStoreError.invalidRecord }
                    return ChatConversation(id: id, title: title,
                        scope: text(row, column: 2).flatMap(UUID.init(uuidString:)),
                        updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(row, 3)))
                }
                return try threads.map { conversation in
                    var thread = conversation
                    thread.messages = try chatRows("""
                        SELECT m.id, m.role, m.body, m.status, m.requestID, m.citations,
                            (SELECT group_concat(s.meetingID) FROM chat_sources s WHERE s.messageID = m.id)
                        FROM chat_messages m WHERE m.conversationID = ? ORDER BY m.ordinal
                        """, [thread.id.uuidString], db: db) { row in
                        guard let id = text(row, column: 0).flatMap(UUID.init(uuidString:)),
                              let role = text(row, column: 1).flatMap(ChatMessage.Role.init(rawValue:)),
                              let body = text(row, column: 2),
                              let status = text(row, column: 3).flatMap(ChatMessage.Status.init(rawValue:)),
                              let citations = text(row, column: 5) else { throw MeetingStoreError.invalidRecord }
                        var message = ChatMessage(id: id, role: role, body: body, status: status,
                                                  requestID: text(row, column: 4).flatMap(UUID.init(uuidString:)))
                        message.citations = try JSONDecoder().decode([ChatCitation].self, from: Data(citations.utf8))
                        message.sourceIDs = Set((text(row, column: 6) ?? "").split(separator: ",")
                            .compactMap { UUID(uuidString: String($0)) })
                        return message
                    }
                    return thread
                }
            }
        }
    }

    func saveChat(_ thread: ChatConversation, changed: Int, create: Bool, retrying: Bool = false) throws {
        try withDatabase { db in
            try transaction(db: db) {
                let threadID = thread.id.uuidString
                let info = [thread.title, thread.scope?.uuidString, String(thread.updatedAt.timeIntervalSince1970), threadID]
                if create {
                    try chatWrite("INSERT INTO chat_conversations(title, scope, updatedAt, id) VALUES (?, ?, ?, ?)", info, db: db)
                } else {
                    try chatWrite("UPDATE chat_conversations SET title = ?, scope = ?, updatedAt = ? WHERE id = ?", info, db: db)
                    guard sqlite3_changes(db) == 1 else { return }
                }
                for (ordinal, value) in thread.messages.enumerated().suffix(changed) {
                    var message = value
                    let sources = message.sourceIDs.union(message.citations.map(\.meetingID))
                    let missingMeeting = try sources.contains { id in
                        try !exists("SELECT 1 FROM meetings WHERE upper(id) = ?", id: id, db: db)
                    }
                    let missingRecording = try message.citations.contains { citation in
                        try !exists("SELECT 1 FROM recordings WHERE upper(id) = ?", id: citation.recordingID, db: db)
                    }
                    if missingMeeting || missingRecording {
                        message.status = .sourceRemoved
                        message.body = ""
                        message.citations = []
                    }
                    try chatWrite("""
                        INSERT INTO chat_messages(id, conversationID, ordinal, role, body, status, requestID, citations)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET body = excluded.body, status = excluded.status,
                            citations = excluded.citations, requestID = excluded.requestID
                        WHERE (chat_messages.status IN ('pending', 'streaming') AND chat_messages.requestID = excluded.requestID)
                           OR (CAST(? AS INTEGER) = 1 AND chat_messages.status IN ('failed', 'interrupted', 'stopped'))
                        """, [message.id.uuidString, threadID, String(ordinal), message.role.rawValue,
                              message.body, message.status.rawValue, message.requestID?.uuidString,
                              try chatJSON(message.citations), retrying ? "1" : "0"], db: db)
                    guard sqlite3_changes(db) == 1 else { continue }
                    if retrying || message.status == .sourceRemoved {
                        try execute("DELETE FROM chat_sources WHERE messageID = ?", id: message.id, db: db)
                    }
                    if message.status != .sourceRemoved {
                        for id in sources {
                            try chatWrite("INSERT OR IGNORE INTO chat_sources VALUES (?, ?)",
                                          [message.id.uuidString, id.uuidString], db: db)
                        }
                    }
                }
            }
        }
    }

    func deleteChat(_ id: UUID) throws {
        try withDatabase { try execute("DELETE FROM chat_conversations WHERE id = ?", id: id, db: $0) }
    }

    private func removeChatRecordingData(_ id: UUID, db: OpaquePointer) throws {
        try execute("""
            UPDATE chat_messages SET body = '', status = 'sourceRemoved', citations = '[]'
            WHERE EXISTS (
                SELECT 1 FROM json_each(chat_messages.citations) citation
                WHERE upper(json_extract(citation.value, '$.recordingID')) = ?
            )
            """, id: id, db: db)
        try execute("""
            DELETE FROM chat_sources WHERE messageID IN (SELECT id FROM chat_messages WHERE status = 'sourceRemoved')
            """, db: db)
        if sqlite3_compileoption_used("ENABLE_FTS5") != 0,
           !(try chatRows("SELECT 1 FROM sqlite_master WHERE name = 'chat_fts'", db: db) { _ in true }).isEmpty {
            try execute("DELETE FROM chat_fts WHERE rowid IN (SELECT id FROM chat_chunks WHERE upper(recordingID) = ?)",
                        id: id, db: db)
        }
    }

    private func removeChatMeetingData(_ id: UUID, db: OpaquePointer) throws {
        try execute("""
            UPDATE chat_messages SET body = '', status = 'sourceRemoved', citations = '[]'
            WHERE id IN (SELECT messageID FROM chat_sources WHERE meetingID = ?)
            """, id: id, db: db)
        try execute("""
            DELETE FROM chat_sources WHERE messageID IN (SELECT id FROM chat_messages WHERE status = 'sourceRemoved')
            """, db: db)
        if sqlite3_compileoption_used("ENABLE_FTS5") != 0,
           !(try chatRows("SELECT 1 FROM sqlite_master WHERE name = 'chat_fts'", db: db) { _ in true }).isEmpty {
            try execute("""
                DELETE FROM chat_fts WHERE rowid IN (
                    SELECT c.id FROM chat_chunks c JOIN recordings r ON r.id = c.recordingID WHERE upper(r.meetingID) = ?
                )
                """, id: id, db: db)
        }
    }

    private func chatRows<T>(_ sql: String, _ parameters: [String?] = [], db: OpaquePointer,
                             read: (OpaquePointer) throws -> T) throws -> [T] {
        let statement = try prepare(sql, db: db)
        defer { sqlite3_finalize(statement) }
        for (index, parameter) in parameters.enumerated() {
            try bind(parameter, at: Int32(index + 1), to: statement)
        }
        var rows: [T] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return rows }
            guard code == SQLITE_ROW else { throw MeetingStoreError.sqlite(code) }
            rows.append(try read(statement))
        }
    }

    private func chatWrite(_ sql: String, _ parameters: [String?], db: OpaquePointer) throws {
        let statement = try prepare(sql, db: db)
        defer { sqlite3_finalize(statement) }
        for (index, parameter) in parameters.enumerated() {
            try bind(parameter, at: Int32(index + 1), to: statement)
        }
        try finish(statement)
    }

    private func chatJSON(_ value: some Encodable) throws -> String {
        try String(decoding: JSONEncoder().encode(value), as: UTF8.self)
    }
}

extension MeetingStore {
    func chatIndexAvailable() throws -> Bool {
        if didOpenChatIndex { return true }
        return try withDatabase { db in
            do {
                try execute("""
                    CREATE VIRTUAL TABLE IF NOT EXISTS chat_fts
                    USING fts5(body, tokenize = 'unicode61 remove_diacritics 2')
                    """, db: db)
            } catch {
                if String(cString: sqlite3_errmsg(db)).contains("no such module: fts5") { return false }
                throw error
            }
            try execute("DELETE FROM chat_fts WHERE rowid NOT IN (SELECT id FROM chat_chunks)", db: db)
            didOpenChatIndex = true
            return true
        }
    }

    func staleChatRecordings() throws -> [UUID] {
        guard try chatIndexAvailable() else { return [] }
        return try withDatabase { db in
            try chatRows("""
                SELECT r.id FROM recordings r JOIN transcript_jobs j ON j.inputID = r.id
                LEFT JOIN chat_indexed c ON c.recordingID = r.id
                WHERE r.endedAt IS NOT NULL AND j.status = 'Complete' AND c.revision IS NOT j.chatRevision
                ORDER BY r.startedAt DESC, r.id
                """, db: db) { row in
                guard let id = text(row, column: 0).flatMap(UUID.init(uuidString:)) else { throw MeetingStoreError.invalidRecord }
                return id
            }
        }
    }

    func chatIndexInput(_ id: UUID) throws -> (revision: Int64, passages: [TranscriptPassage])? {
        try withDatabase { db in
            try transaction(db: db, readOnly: true) {
                guard let revision = try chatRecordingRevision(id, db: db) else { return nil }
                let passages = try chatRows("""
                    SELECT source, checkpoint, sequence, startOffset, endOffset, text FROM transcript_segments
                    WHERE inputID = ? ORDER BY startOffset, source, checkpoint, sequence
                    """, [id.uuidString], db: db) { row in
                    guard let source = text(row, column: 0).flatMap(AudioSegment.Source.init(rawValue:)),
                          let body = text(row, column: 5) else { throw MeetingStoreError.invalidRecord }
                    return TranscriptPassage(inputID: id, source: source, checkpoint: sqlite3_column_int64(row, 1),
                        sequence: sqlite3_column_int64(row, 2), startOffset: sqlite3_column_int64(row, 3),
                        endOffset: sqlite3_column_int64(row, 4), text: body)
                }
                return (revision, passages)
            }
        }
    }

    func replaceChatIndex(_ id: UUID, revision: Int64, chunks: [TranscriptChunk]) throws {
        try withDatabase { db in
            try transaction(db: db) {
                guard try chatRecordingRevision(id, db: db) == revision else { return }
                let indexed = try chatRows("SELECT revision FROM chat_indexed WHERE recordingID = ?",
                                           [id.uuidString], db: db) { sqlite3_column_int64($0, 0) }.first
                guard indexed != revision else { return }
                try execute("DELETE FROM chat_fts WHERE rowid IN (SELECT id FROM chat_chunks WHERE recordingID = ?)",
                            id: id, db: db)
                try execute("DELETE FROM chat_indexed WHERE recordingID = ?", id: id, db: db)
                try chatWrite("INSERT INTO chat_indexed VALUES (?, ?)", [id.uuidString, String(revision)], db: db)
                for chunk in chunks {
                    try chatWrite("""
                        INSERT INTO chat_chunks(recordingID, passageIDs, startOffset, endOffset) VALUES (?, ?, ?, ?)
                        """, [id.uuidString, try chatJSON(chunk.passageIDs), String(chunk.startOffset),
                              String(chunk.endOffset)], db: db)
                    let rowID = sqlite3_last_insert_rowid(db)
                    try chatWrite("INSERT INTO chat_fts(rowid, body) VALUES (?, ?)", [String(rowID), chunk.body], db: db)
                }
            }
        }
    }

    func chatEvidence(terms: [String], scope: UUID?, candidates: [UUID] = [],
                      from: Date? = nil, until: Date? = nil) throws -> [ChatEvidence] {
        try readChatEvidence(match: MeetingChatRetrieval.match(terms), scope: scope, candidates: candidates, from: from, until: until)
    }

    private func readChatEvidence(match: String, scope: UUID?, candidates: [UUID] = [],
                                  from: Date? = nil, until: Date? = nil) throws -> [ChatEvidence] {
        guard !match.isEmpty, try chatIndexAvailable() else { return [] }
        let candidates = Array(candidates.prefix(12))
        let candidateFilter = candidates.isEmpty ? "" :
            "AND upper(r.meetingID) IN (\(Array(repeating: "?", count: candidates.count).joined(separator: ",")))"
        let start = from.map { String($0.timeIntervalSince1970) }
        let end = until.map { String($0.timeIntervalSince1970) }
        return try withDatabase { db in
            try chatRows("""
                SELECT r.meetingID, r.id, c.passageIDs, c.startOffset, j.chatRevision, m.name, f.body, c.endOffset
                FROM chat_fts f JOIN chat_chunks c ON c.id = f.rowid
                JOIN chat_indexed x ON x.recordingID = c.recordingID
                JOIN recordings r ON r.id = c.recordingID JOIN meetings m ON m.id = r.meetingID
                JOIN transcript_jobs j ON j.inputID = r.id
                LEFT JOIN calendar_meeting_inputs ci ON ci.meetingID = m.id
                WHERE chat_fts MATCH ? AND j.status = 'Complete' AND x.revision = j.chatRevision
                  AND (? IS NULL OR upper(r.meetingID) = ?)
                  AND (? IS NULL OR coalesce(ci.eventDate, r.startedAt) >= CAST(? AS REAL))
                  AND (? IS NULL OR coalesce(ci.eventDate, r.startedAt) < CAST(? AS REAL))
                  \(candidateFilter)
                ORDER BY bm25(chat_fts), r.startedAt DESC, c.startOffset LIMIT 6
                """, [match, scope?.uuidString, scope?.uuidString, start, start, end, end] + candidates.map(\.uuidString), db: db) { row in
                guard let meetingID = text(row, column: 0).flatMap(UUID.init(uuidString:)),
                      let recordingID = text(row, column: 1).flatMap(UUID.init(uuidString:)),
                      let ids = text(row, column: 2), let title = text(row, column: 5),
                      let body = text(row, column: 6) else { throw MeetingStoreError.invalidRecord }
                return ChatEvidence(title: title, body: body, citation: ChatCitation(meetingID: meetingID,
                    recordingID: recordingID, passageIDs: try JSONDecoder().decode([String].self, from: Data(ids.utf8)),
                    startOffset: sqlite3_column_int64(row, 3), revision: sqlite3_column_int64(row, 4)),
                    endOffset: sqlite3_column_int64(row, 7))
            }
        }
    }

    func chatTranscriptContext(around match: ChatEvidence, secondsBefore: Int, secondsAfter: Int,
                               byteLimit: Int) throws -> [ChatEvidence] {
        let anchor = match.citation
        guard anchor.screenCaptureID == nil, try isChatCitationCurrent(anchor) else { return [] }
        let before = Int64(min(180, max(0, secondsBefore))) * 1_000_000_000
        let after = Int64(min(180, max(0, secondsAfter))) * 1_000_000_000
        let end = max(anchor.startOffset, match.endOffset ?? anchor.startOffset)
        let window = max(0, anchor.startOffset - before)...(min(end, Int64.max - after) + after)
        let passages = try withDatabase { db in
            try readTranscriptPassages(for: anchor.meetingID, recordingID: anchor.recordingID, window: window, db: db)
        }
        let chunks = MeetingChatRetrieval.chunks(from: passages)
        // Keep the context nearest the match if the full window exceeds the tool budget.
        func distance(_ chunk: TranscriptChunk) -> Int64 {
            max(anchor.startOffset - chunk.endOffset, chunk.startOffset - end, 0)
        }
        var remaining = byteLimit
        var selected: [Int] = []
        for index in chunks.indices.sorted(by: { distance(chunks[$0]) < distance(chunks[$1]) }) {
            let bytes = chunks[index].body.utf8.count
            guard bytes <= remaining else { break }
            remaining -= bytes
            selected.append(index)
        }
        return selected.sorted().map { index in
            let chunk = chunks[index]
            return ChatEvidence(title: match.title, body: chunk.body,
                citation: ChatCitation(meetingID: anchor.meetingID, recordingID: anchor.recordingID,
                    passageIDs: chunk.passageIDs, startOffset: chunk.startOffset, revision: anchor.revision),
                endOffset: chunk.endOffset)
        }
    }

    func findTranscriptPassages(_ query: String) throws -> [ChatEvidence] {
        let terms = query.split { !$0.isLetter && !$0.isNumber }.prefix(8).map(String.init)
        let match = terms.map { "\"\($0)\"*" }.joined(separator: " AND ")
        let chunks = try readChatEvidence(match: match, scope: nil)
        guard !chunks.isEmpty else { return [] }
        return try withDatabase { db in
            var seen = Set<String>()
            return try chunks.compactMap { chunk in
                let original = chunk.citation
                let identifiers = original.passageIDs
                let placeholders = Array(repeating: "?", count: identifiers.count).joined(separator: ",")
                let passages = try chatRows("""
                    SELECT upper(inputID) || ':' || source || ':' || checkpoint || ':' || sequence, startOffset, text
                    FROM transcript_segments
                    WHERE inputID = ? AND upper(inputID) || ':' || source || ':' || checkpoint || ':' || sequence IN (\(placeholders))
                    ORDER BY startOffset, source, checkpoint, sequence
                    """, [original.recordingID.uuidString] + identifiers, db: db) { row in
                        (id: text(row, column: 0) ?? "", offset: sqlite3_column_int64(row, 1),
                         body: text(row, column: 2) ?? "")
                    }
                let passage = passages.first { $0.body.localizedStandardContains(query) } ??
                    passages.max { lhs, rhs in
                        terms.filter { lhs.body.localizedStandardContains($0) }.count <
                            terms.filter { rhs.body.localizedStandardContains($0) }.count
                    }
                guard let passage, seen.insert(passage.id).inserted else { return nil }
                let citation = ChatCitation(meetingID: original.meetingID, recordingID: original.recordingID,
                    passageIDs: [passage.id], startOffset: passage.offset, revision: original.revision)
                return ChatEvidence(title: chunk.title, body: Self.transcriptExcerpt(passage.body, around: query), citation: citation)
            }
        }
    }

    func chatMeetingCandidates(terms: [String], scope: UUID?, from: Date?, until: Date?) throws -> [ChatMeetingMatch] {
        let terms = MeetingChatRetrieval.terms(from: terms.joined(separator: " ")).prefix(16)
        let score = terms.isEmpty ? "1" : terms.map { _ in "chat_contains(metadata, ?)" }.joined(separator: " + ")
        let start = from.map { String($0.timeIntervalSince1970) }
        let end = until.map { String($0.timeIntervalSince1970) }
        return try withDatabase { db in
            try check(sqlite3_create_function_v2(db, "chat_contains", 2, SQLITE_UTF8 | SQLITE_DETERMINISTIC, nil,
                { context, _, values in
                    guard let values, let haystack = sqlite3_value_text(values[0]), let needle = sqlite3_value_text(values[1]) else {
                        sqlite3_result_int(context, 0)
                        return
                    }
                    let matched = String(cString: haystack).range(of: String(cString: needle),
                        options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    sqlite3_result_int(context, matched ? 1 : 0)
                }, nil, nil, nil))
            return try chatRows("""
                WITH candidates AS (
                    SELECT m.id, m.name, m.description, coalesce(ci.eventDate, m.createdAt) AS date, ci.details, ms.text AS summary,
                        (SELECT group_concat(t.name, char(10)) FROM meeting_tags mt JOIN tags t ON t.id = mt.tagID
                         WHERE mt.meetingID = m.id) AS tags
                    FROM meetings m LEFT JOIN calendar_meeting_inputs ci ON ci.meetingID = m.id
                    LEFT JOIN meeting_summaries ms ON ms.meetingID = m.id
                    WHERE (? IS NULL OR upper(m.id) = ?)
                      AND (? IS NULL OR coalesce(ci.eventDate, m.createdAt) >= CAST(? AS REAL))
                      AND (? IS NULL OR coalesce(ci.eventDate, m.createdAt) < CAST(? AS REAL))
                ), searchable AS (
                    SELECT *, name || ' ' || coalesce(description, '') || ' ' || coalesce(tags, '') || ' ' || coalesce(summary, '') || ' ' ||
                        CASE WHEN json_valid(details) THEN
                            coalesce(json_extract(details, '$.notes'), '') || ' ' ||
                            coalesce(json_extract(details, '$.attendees'), '') || ' ' ||
                            coalesce(json_extract(details, '$.organizer'), '')
                        ELSE '' END AS metadata
                    FROM candidates
                ), ranked AS (
                    SELECT id, name, description, date, details, tags, summary, \(score) AS score FROM searchable
                )
                SELECT id, name, description, date, details, tags, summary
                FROM ranked WHERE score > 0 ORDER BY score DESC, date DESC, id LIMIT 8
                """, [scope?.uuidString, scope?.uuidString, start, start, end, end] + terms.map(Optional.some), db: db) { row in
                    guard let id = text(row, column: 0).flatMap(UUID.init(uuidString:)),
                          let title = text(row, column: 1) else { throw MeetingStoreError.invalidRecord }
                    let invite = text(row, column: 4).flatMap {
                        try? JSONDecoder().decode(CalendarEventDetails.self, from: Data($0.utf8))
                    }
                    let notes = text(row, column: 2) ?? invite?.notes
                    let summaryExcerpt = text(row, column: 6).map { summary in
                        let keyword = terms.first { summary.localizedStandardContains($0) } ?? ""
                        return Self.transcriptExcerpt(summary, around: keyword)
                    }
                    return ChatMeetingMatch(id: id, title: String(title.prefix(200)),
                        date: Date(timeIntervalSince1970: sqlite3_column_double(row, 3)),
                        description: notes.map { String($0.prefix(240)) },
                        tags: (text(row, column: 5) ?? "").components(separatedBy: .newlines).filter { !$0.isEmpty },
                        invitees: (invite?.attendees ?? []) + [invite?.organizer].compactMap { $0 },
                        summaryExcerpt: summaryExcerpt)
                }
        }
    }

    func isChatCitationCurrent(_ citation: ChatCitation) throws -> Bool {
        if citation.screenCaptureID != nil { return try screenCaptureURL(for: citation) != nil }
        guard let first = citation.passageIDs.first else { return false }
        return try withDatabase { db in
            guard try chatRecordingRevision(citation.recordingID, db: db) == citation.revision else { return false }
            let rows = try chatRows("""
                SELECT 1 FROM transcript_segments s JOIN recordings r ON r.id = s.inputID
                WHERE r.id = ? AND upper(r.meetingID) = ?
                  AND upper(s.inputID) || ':' || s.source || ':' || s.checkpoint || ':' || s.sequence = ?
                  AND s.startOffset = ?
                """, [citation.recordingID.uuidString, citation.meetingID.uuidString, first,
                      String(citation.startOffset)], db: db) { _ in true }
            return !rows.isEmpty
        }
    }

    private func chatRecordingRevision(_ id: UUID, db: OpaquePointer) throws -> Int64? {
        try chatRows("""
            SELECT j.chatRevision FROM transcript_jobs j JOIN recordings r ON r.id = j.inputID
            WHERE r.id = ? AND r.endedAt IS NOT NULL AND j.status = 'Complete'
            """, [id.uuidString], db: db) { sqlite3_column_int64($0, 0) }.first
    }
}

extension MeetingStore {
    func sidebarItems() throws -> [SidebarItem] {
        try withDatabase { db in
            try chatRows("""
                SELECT id, parentID, name, color, expanded FROM sidebar_items
                ORDER BY parentID, position, id
                """, db: db) { row in
                guard let id = text(row, column: 0).flatMap(UUID.init(uuidString:)) else {
                    throw MeetingStoreError.invalidRecord
                }
                let folder = text(row, column: 2).map { name in
                    SidebarItem.Folder(name: name, color: text(row, column: 3).flatMap(TagColor.init(rawValue:)),
                                       expanded: sqlite3_column_int(row, 4) != 0)
                }
                return SidebarItem(id: id, parentID: text(row, column: 1).flatMap(UUID.init(uuidString:)), folder: folder)
            }
        }
    }

    func createSidebarFolder(_ id: UUID) throws {
        try withDatabase { db in
            try transaction(db: db) {
                try insertSidebarItem(id: id, meetingID: nil, name: "New Folder", db: db)
            }
        }
    }

    private func insertSidebarItem(id: UUID, meetingID: UUID?, name: String?, db: OpaquePointer) throws {
        try chatWrite("""
            INSERT INTO sidebar_items(id, meetingID, name, position)
            VALUES (?, ?, ?, (SELECT coalesce(min(position), 0) - 1 FROM sidebar_items WHERE parentID IS NULL))
            """, [id.uuidString, meetingID?.uuidString, name], db: db)
    }

    func renameSidebarFolder(_ id: UUID, name: String) throws {
        let name = try Meeting.normalizedName(name)
        try withDatabase { db in
            try chatWrite("UPDATE sidebar_items SET name = ? WHERE id = ? AND meetingID IS NULL",
                          [name, id.uuidString], db: db)
        }
    }

    func setSidebarFolderColor(_ id: UUID, color: TagColor?) throws {
        try withDatabase { db in
            try chatWrite("UPDATE sidebar_items SET color = ? WHERE id = ? AND meetingID IS NULL",
                          [color?.rawValue, id.uuidString], db: db)
        }
    }

    func setSidebarFolderExpanded(_ id: UUID, expanded: Bool) throws {
        try withDatabase { db in
            try chatWrite("UPDATE sidebar_items SET expanded = ? WHERE id = ? AND meetingID IS NULL",
                          [expanded ? "1" : "0", id.uuidString], db: db)
        }
    }

    func moveSidebarItem(_ id: UUID, to parent: UUID?, before sibling: UUID?) throws {
        try withDatabase { db in
            try transaction(db: db) {
                guard try exists("SELECT 1 FROM sidebar_items WHERE id = ?", id: id, db: db)
                else { throw SidebarMoveError.invalidTarget }
                if let parent {
                    guard try exists("SELECT 1 FROM sidebar_items WHERE id = ? AND meetingID IS NULL", id: parent, db: db)
                    else { throw SidebarMoveError.invalidTarget }
                    let cycle = try chatRows("""
                        WITH RECURSIVE ancestors(id, parentID) AS (
                            SELECT id, parentID FROM sidebar_items WHERE id = ?
                            UNION
                            SELECT s.id, s.parentID FROM sidebar_items s JOIN ancestors a ON s.id = a.parentID
                        ) SELECT 1 FROM ancestors WHERE id = ?
                        """, [parent.uuidString, id.uuidString], db: db) { _ in true }
                    guard cycle.isEmpty else { throw SidebarMoveError.nestingCycle }
                }
                guard sibling != id else { return }
                var order = try chatRows("""
                    SELECT id FROM sidebar_items WHERE parentID IS ? AND id != ? ORDER BY position, id
                    """, [parent?.uuidString, id.uuidString], db: db) { row in
                    guard let value = text(row, column: 0) else { throw MeetingStoreError.invalidRecord }
                    return value
                }
                let index: Int
                if let sibling {
                    guard let target = order.firstIndex(of: sibling.uuidString) else { throw SidebarMoveError.invalidTarget }
                    index = target
                } else {
                    index = order.count
                }
                order.insert(id.uuidString, at: index)
                try chatWrite("UPDATE sidebar_items SET parentID = ? WHERE id = ?",
                              [parent?.uuidString, id.uuidString], db: db)
                let positions = try chatJSON(order)
                try chatWrite("""
                    WITH positions AS (SELECT value AS id, key AS position FROM json_each(?))
                    UPDATE sidebar_items SET position = positions.position
                    FROM positions WHERE sidebar_items.id = positions.id
                    """, [positions], db: db)
                if let parent {
                    try execute("UPDATE sidebar_items SET expanded = 1 WHERE id = ?", id: parent, db: db)
                }
            }
        }
    }
}

extension MeetingStore {
    func compressibleRecordings(endedAfter date: Date?) throws -> [UUID] {
        try withDatabase { db in
            try chatRows("""
                SELECT r.id FROM recordings r JOIN transcript_jobs j ON j.inputID = r.id
                WHERE j.status = 'Complete' AND r.endedAt IS NOT NULL
                  AND (?1 IS NULL OR r.endedAt >= CAST(?1 AS REAL))
                  AND EXISTS (SELECT 1 FROM audio_segments a WHERE a.recordingID = r.id
                              AND a.relativePath LIKE '%.caf')
                ORDER BY r.endedAt, r.id
                """, [date.map { String($0.timeIntervalSince1970) }], db: db) { row in
                guard let id = text(row, column: 0).flatMap(UUID.init(uuidString:)) else {
                    throw MeetingStoreError.invalidRecord
                }
                return id
            }
        }
    }

    func replaceRecordingAudio(_ id: UUID, originals: [String], replacements: [String]) throws {
        guard !originals.isEmpty, originals.count == replacements.count else {
            throw MeetingStoreError.invalidRecord
        }
        try withDatabase { db in
            try transaction(db: db) {
                let eligible = try exists("""
                    SELECT 1 FROM recordings r JOIN transcript_jobs j ON j.inputID = r.id
                    WHERE r.id = ? AND r.endedAt IS NOT NULL AND j.status = 'Complete'
                    """, id: id, db: db)
                guard eligible else { throw MeetingStoreError.notFound }
                for (original, replacement) in zip(originals, replacements) {
                    try chatWrite("UPDATE audio_segments SET relativePath = ? WHERE recordingID = ? AND relativePath = ?",
                                  [replacement, id.uuidString, original], db: db)
                    guard sqlite3_changes(db) == 1 else { throw MeetingStoreError.notFound }
                    try chatWrite("INSERT INTO pending_uncompressed_audio VALUES (?)", [original], db: db)
                }
            }
        }
    }

    func pendingUncompressedAudio() throws -> [String] {
        try withDatabase { db in
            try chatRows("SELECT relativePath FROM pending_uncompressed_audio", db: db) { row in
                guard let path = text(row, column: 0) else { throw MeetingStoreError.invalidRecord }
                return path
            }
        }
    }

    func finishUncompressedAudioRemoval(_ paths: [String]) throws {
        guard !paths.isEmpty else { return }
        try withDatabase { db in
            try chatWrite("DELETE FROM pending_uncompressed_audio WHERE relativePath IN (SELECT value FROM json_each(?))",
                          [try chatJSON(paths)], db: db)
        }
    }
}
