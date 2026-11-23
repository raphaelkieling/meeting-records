import Foundation
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

    func createMeeting(id: UUID, name: String) throws -> Meeting {
        let name = try Meeting.normalizedName(name)
        return try withDatabase { db in
            try transaction(db: db) {
                let meetings = try readMeetings(db: db)
                if let existing = meetings.first(where: { $0.id == id }) { return existing }
                let time = try nextUpdate(after: meetings)
                let meeting = try Meeting(id: id, name: name, createdAt: time, updatedAt: time)
                let statement = try prepare("INSERT INTO meetings(id, name, createdAt, updatedAt) VALUES (?, ?, ?, ?)", db: db)
                defer { sqlite3_finalize(statement) }
                try bind(id.uuidString, at: 1, to: statement)
                try bind(name, at: 2, to: statement)
                try check(sqlite3_bind_double(statement, 3, time.timeIntervalSince1970))
                try check(sqlite3_bind_double(statement, 4, time.timeIntervalSince1970))
                try finish(statement)
                return meeting
            }
        }
    }

    func renameMeeting(id: UUID, name: String) throws -> Meeting {
        let name = try Meeting.normalizedName(name)
        return try withDatabase { db in
            try transaction(db: db) {
                let meetings = try readMeetings(db: db)
                guard let existing = meetings.first(where: { $0.id == id }) else { throw MeetingStoreError.notFound }
                guard existing.name != name else { return existing }
                let meeting = try Meeting(id: id, name: name, createdAt: existing.createdAt,
                                          updatedAt: nextUpdate(after: meetings))
                let statement = try prepare("UPDATE meetings SET name = ?, updatedAt = ? WHERE upper(id) = ?", db: db)
                defer { sqlite3_finalize(statement) }
                try bind(name, at: 1, to: statement)
                try check(sqlite3_bind_double(statement, 2, meeting.updatedAt.timeIntervalSince1970))
                try bind(id.uuidString, at: 3, to: statement)
                try finish(statement)
                guard sqlite3_changes(db) == 1 else { throw MeetingStoreError.notFound }
                return meeting
            }
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
        guard (0...3).contains(version) else { throw MeetingStoreError.incompatibleVersion }
        return version
    }

    private func ensureSchema(db: OpaquePointer) throws {
        guard try schemaVersion(db: db) < 3 else { return }
        try transaction(db: db) {
            let version = try schemaVersion(db: db)
            guard version < 3 else { return }
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
            try execute("PRAGMA user_version = 3", db: db)
        }
    }

    private func readMeetings(db: OpaquePointer, legacy: Bool = false) throws -> [Meeting] {
        let updateColumn = legacy ? "createdAt" : "updatedAt"
        let statement = try prepare("SELECT id, name, createdAt, \(updateColumn) FROM meetings ORDER BY \(updateColumn) DESC, upper(id) ASC", db: db)
        defer { sqlite3_finalize(statement) }
        var meetings: [Meeting] = []
        var ids: Set<UUID> = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return meetings }
            guard code == SQLITE_ROW else { throw MeetingStoreError.sqlite(code) }
            guard let idString = text(statement, column: 0), let name = text(statement, column: 1),
                  idString.utf8.count == 36, let id = UUID(uuidString: idString), ids.insert(id).inserted,
                  [SQLITE_FLOAT, SQLITE_INTEGER].contains(sqlite3_column_type(statement, 2)),
                  [SQLITE_FLOAT, SQLITE_INTEGER].contains(sqlite3_column_type(statement, 3)) else {
                throw MeetingStoreError.invalidRecord
            }
            meetings.append(try Meeting(id: id, name: name,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))))
        }
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
              let bytes = sqlite3_column_text(statement, column) else { return nil }
        return String(bytes: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, column))), encoding: .utf8)
    }

    private func transaction<T>(db: OpaquePointer, _ operation: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE", db: db)
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

    private func check(_ code: Int32) throws {
        guard code == SQLITE_OK else { throw MeetingStoreError.sqlite(code) }
    }

    private func finish(_ statement: OpaquePointer) throws {
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE else { throw MeetingStoreError.sqlite(code) }
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

    func recordings(for meetingID: UUID) throws -> [Recording] {
        try readRecordings(meetingID: meetingID)
    }

    func unfinishedRecordings() throws -> [Recording] {
        try readRecordings(meetingID: nil)
    }

    private func readRecordings(meetingID: UUID?) throws -> [Recording] {
        try withDatabase { db in
            let condition = meetingID == nil ? "endedAt IS NULL" : "upper(meetingID) = ? AND endedAt IS NOT NULL"
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
