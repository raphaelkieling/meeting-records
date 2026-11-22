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

    private func withDatabase<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        let url = try databaseURL ?? Self.defaultDatabaseURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        defer { if let handle { sqlite3_close(handle) } }
        guard result == SQLITE_OK, let db = handle else { throw MeetingStoreError.sqlite(result) }
        try ensureSchema(db: db)
        return try operation(db)
    }

    private func ensureSchema(db: OpaquePointer) throws {
        let statement = try prepare("PRAGMA user_version", db: db)
        let step = sqlite3_step(statement)
        let version = sqlite3_column_int(statement, 0)
        sqlite3_finalize(statement)
        guard step == SQLITE_ROW else { throw MeetingStoreError.sqlite(step) }
        guard (0...2).contains(version) else { throw MeetingStoreError.incompatibleVersion }
        guard version < 2 else { return }
        try transaction(db: db) {
            if version == 0 {
                try execute("""
                    CREATE TABLE meetings (
                        id TEXT PRIMARY KEY NOT NULL,
                        name TEXT NOT NULL CHECK(length(trim(name)) > 0),
                        createdAt REAL NOT NULL,
                        updatedAt REAL NOT NULL
                    )
                    """, db: db)
            } else {
                // Validate before altering the schema so invalid historical data leaves no partial upgrade.
                _ = try readMeetings(db: db, legacy: true)
                try execute("ALTER TABLE meetings ADD COLUMN updatedAt REAL NOT NULL DEFAULT 0", db: db)
                try execute("UPDATE meetings SET updatedAt = createdAt", db: db)
            }
            try execute("PRAGMA user_version = 2", db: db)
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
