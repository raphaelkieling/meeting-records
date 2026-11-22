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
        let url = try databaseURL ?? Self.defaultDatabaseURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        // Keep the connection scoped to this actor operation, including failed opens and retries.
        defer { if let handle { sqlite3_close(handle) } }
        guard result == SQLITE_OK, let db = handle else { throw MeetingStoreError.sqlite(result) }
        let versionStatement = try prepare("PRAGMA user_version", db: db)
        let versionStep = sqlite3_step(versionStatement)
        let version = sqlite3_column_int(versionStatement, 0)
        sqlite3_finalize(versionStatement)
        guard versionStep == SQLITE_ROW else { throw MeetingStoreError.sqlite(versionStep) }
        guard version == 0 || version == 1 else { throw MeetingStoreError.incompatibleVersion }
        if version == 0 {
            try execute("BEGIN IMMEDIATE", db: db)
            do {
                try execute("""
                    CREATE TABLE meetings (
                        id TEXT PRIMARY KEY NOT NULL,
                        name TEXT NOT NULL CHECK(length(trim(name)) > 0),
                        createdAt REAL NOT NULL
                    )
                    """, db: db)
                try execute("PRAGMA user_version = 1", db: db)
                try execute("COMMIT", db: db)
            } catch {
                try? execute("ROLLBACK", db: db)
                throw error
            }
        }
        let statement = try prepare("SELECT id, name, createdAt FROM meetings ORDER BY createdAt DESC, id ASC", db: db)
        defer { sqlite3_finalize(statement) }
        var meetings: [Meeting] = []
        var ids: Set<UUID> = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return meetings }
            guard code == SQLITE_ROW else { throw MeetingStoreError.sqlite(code) }
            guard sqlite3_column_type(statement, 0) == SQLITE_TEXT,
                  sqlite3_column_type(statement, 1) == SQLITE_TEXT,
                  [SQLITE_FLOAT, SQLITE_INTEGER].contains(sqlite3_column_type(statement, 2)),
                  let idText = sqlite3_column_text(statement, 0),
                  let nameText = sqlite3_column_text(statement, 1),
                  let idString = String(bytes: UnsafeBufferPointer(start: idText,
                      count: Int(sqlite3_column_bytes(statement, 0))), encoding: .utf8),
                  let name = String(bytes: UnsafeBufferPointer(start: nameText,
                      count: Int(sqlite3_column_bytes(statement, 1))), encoding: .utf8),
                  idString.utf8.count == 36,
                  let id = UUID(uuidString: idString), ids.insert(id).inserted else {
                throw MeetingStoreError.invalidRecord
            }
            meetings.append(try Meeting(id: id, name: name,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))))
        }
    }

    private func execute(_ sql: String, db: OpaquePointer) throws {
        let code = sqlite3_exec(db, sql, nil, nil, nil)
        guard code == SQLITE_OK else { throw MeetingStoreError.sqlite(code) }
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
