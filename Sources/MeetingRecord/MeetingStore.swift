import Foundation
import CryptoKit
import SQLite3

actor MeetingStore {
    private let databaseURL: URL?

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
        let savedRecordingIDs: [UUID]
        let completedTranscriptions: Int
    }

    func loadHomeSummary() throws -> HomeSummary {
        try withDatabase { db in
            try transaction(db: db, readOnly: true) {
                let meetings = try readMeetings(db: db, recentOnly: true)
                let statement = try prepare("""
                    SELECT r.id, j.status = 'Complete'
                    FROM recordings r LEFT JOIN transcript_jobs j ON j.inputID = r.id
                    WHERE r.endedAt IS NOT NULL
                    ORDER BY r.startedAt, r.id
                    """, db: db)
                defer { sqlite3_finalize(statement) }
                var ids: [UUID] = []
                var completed = 0
                while true {
                    let result = sqlite3_step(statement)
                    if result == SQLITE_DONE {
                        return HomeSummary(meetings: meetings, savedRecordingIDs: ids,
                                           completedTranscriptions: completed)
                    }
                    guard result == SQLITE_ROW else { throw MeetingStoreError.sqlite(result) }
                    guard let id = text(statement, column: 0).flatMap(UUID.init(uuidString:))
                    else { throw MeetingStoreError.invalidRecord }
                    ids.append(id)
                    completed += Int(sqlite3_column_int(statement, 1))
                }
            }
        }
    }

    func createMeeting(id: UUID, name: String, description: String? = nil,
                       calendarEventDate: Date? = nil, calendarName: String? = nil) throws -> Meeting {
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
                if let calendarEventDate, let calendarName {
                    let source = try prepare("INSERT INTO calendar_meeting_inputs(meetingID, eventDate, calendarName) VALUES (?, ?, ?)", db: db)
                    defer { sqlite3_finalize(source) }
                    try bind(id.uuidString, at: 1, to: source)
                    try check(sqlite3_bind_double(source, 2, calendarEventDate.timeIntervalSince1970))
                    try bind(calendarName, at: 3, to: source)
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
                    try execute("DELETE FROM recordings WHERE upper(meetingID) = ?", id: id, db: db)
                    try execute("DELETE FROM meetings WHERE upper(id) = ?", id: id, db: db)
                    try execute("INSERT INTO pending_meeting_deletions VALUES (?)", id: id, db: db)
                }
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
        guard (0...8).contains(version) else { throw MeetingStoreError.incompatibleVersion }
        return version
    }

    private func ensureSchema(db: OpaquePointer) throws {
        guard try schemaVersion(db: db) < 8 else { return }
        try transaction(db: db) {
            let version = try schemaVersion(db: db)
            guard version < 8 else { return }
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

    func registerSegment(_ segment: AudioSegment) throws {
        try withDatabase { db in
            let statement = try prepare("""
                INSERT INTO audio_segments (recordingID, source, startOffset, frameCount, relativePath)
                VALUES (?, ?, ?, ?, ?) ON CONFLICT(recordingID, source, startOffset) DO NOTHING
                """, db: db)
            defer { sqlite3_finalize(statement) }
            try bind(segment.recordingID.uuidString, at: 1, to: statement)
            try bind(segment.source.rawValue, at: 2, to: statement)
            try check(sqlite3_bind_int64(statement, 3, segment.startOffset))
            try check(sqlite3_bind_int64(statement, 4, segment.frameCount))
            try bind(segment.relativePath, at: 5, to: statement)
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
                    UPDATE recordings SET state = ?, endedAt = max(startedAt, ?)
                    WHERE id = ? AND state IN ('starting', 'recording')
                    AND EXISTS (SELECT 1 FROM audio_segments WHERE recordingID = recordings.id)
                    """, db: db)
                defer { sqlite3_finalize(update) }
                try bind(interrupted ? "interrupted" : "completed", at: 1, to: update)
                try check(sqlite3_bind_double(update, 2, endedAt.timeIntervalSince1970))
                try bind(id.uuidString, at: 3, to: update)
                try finish(update)
                if sqlite3_changes(db) == 1 { return true }

                let remove = try prepare("DELETE FROM recordings WHERE id = ? AND state IN ('starting', 'recording')", db: db)
                defer { sqlite3_finalize(remove) }
                try bind(id.uuidString, at: 1, to: remove)
                try finish(remove)
                return false
            }
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
                    INSERT INTO transcript_jobs VALUES (?, 'Transcribing', ?, ?, NULL, unixepoch())
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

    private func readTranscriptPassages(for meetingID: UUID, db: OpaquePointer) throws -> [TranscriptPassage] {
        let statement = try prepare("""
            SELECT s.inputID, s.source, s.checkpoint, s.sequence, s.startOffset, s.endOffset, s.text
            FROM transcript_segments s JOIN recordings r ON r.id = s.inputID
            WHERE upper(r.meetingID) = ?
            ORDER BY r.startedAt, r.id, s.startOffset, s.source, s.checkpoint, s.sequence
            """, db: db)
        defer { sqlite3_finalize(statement) }
        try bind(meetingID.uuidString, at: 1, to: statement)
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
                return .init(summary: saved, transcript: transcript,
                             transcriptRevision: revision.finalize().description, hasPendingAudio: pending)
            }
        }
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
