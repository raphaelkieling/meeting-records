import XCTest
import SQLite3
@testable import MeetingRecord

final class MeetingStoreTests: XCTestCase {
    private func temporaryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("meetings.sqlite")
    }

    private func execute(_ sql: String, at url: URL) throws {
        var db: OpaquePointer?
        let result = sqlite3_open(url.path, &db)
        defer { sqlite3_close(db) }
        guard result == SQLITE_OK else { throw MeetingStoreError.sqlite(result) }
        let code = sqlite3_exec(db, sql, nil, nil, nil)
        guard code == SQLITE_OK else { throw MeetingStoreError.sqlite(code) }
    }

    private func scalar(_ sql: String, at url: URL) throws -> Int32 {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw MeetingStoreError.sqlite(SQLITE_CANTOPEN) }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw MeetingStoreError.sqlite(SQLITE_ERROR)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw MeetingStoreError.sqlite(SQLITE_ERROR) }
        return sqlite3_column_int(statement, 0)
    }

    func testFreshDatabaseIsEmptyV3() async throws {
        let url = try temporaryURL()
        let meetings = try await MeetingStore(databaseURL: url).loadMeetings()
        XCTAssertTrue(meetings.isEmpty)
        XCTAssertEqual(try scalar("PRAGMA user_version", at: url), 3)
    }

    func testThirtyRecordsReopenUnicodeDuplicateNamesAndStableOrder() async throws {
        let url = try temporaryURL()
        _ = try await MeetingStore(databaseURL: url).loadMeetings()
        var expected: [Meeting] = []
        for i in 1...30 {
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", i))!
            let name = i < 3 ? "Reunião 日本語 español" : "Reunião \(i) " + String(repeating: "nome longo ", count: 20)
            expected.append(try Meeting(id: id, name: name, createdAt: Date(timeIntervalSince1970: Double(i / 2)), updatedAt: Date(timeIntervalSince1970: Double(i / 2))))
            try execute("INSERT INTO meetings VALUES ('\(id.uuidString)', '\(name)', \(i / 2), \(i / 2))", at: url)
        }
        expected.sort {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt
        }
        let first = try await MeetingStore(databaseURL: url).loadMeetings()
        let second = try await MeetingStore(databaseURL: url).loadMeetings()
        XCTAssertEqual(first, expected)
        XCTAssertEqual(second, expected)
    }

    func testOpenFailureCanRetrySameStoreAfterDirectoryRepair() async throws {
        let url = try temporaryURL()
        let blocked = url.deletingLastPathComponent().appendingPathComponent("blocked")
        try Data("occupied".utf8).write(to: blocked)
        let store = MeetingStore(databaseURL: blocked.appendingPathComponent("meetings.sqlite"))
        do { _ = try await store.loadMeetings(); XCTFail("Expected open failure") } catch {}
        XCTAssertEqual(try String(contentsOf: blocked, encoding: .utf8), "occupied")
        try FileManager.default.removeItem(at: blocked)
        let meetings = try await store.loadMeetings()
        XCTAssertTrue(meetings.isEmpty)
    }

    func testFutureVersionIsPreservedByteForByte() async throws {
        let url = try temporaryURL()
        try execute("CREATE TABLE sentinel(value TEXT); INSERT INTO sentinel VALUES ('preserve'); PRAGMA user_version=4", at: url)
        let original = try Data(contentsOf: url)
        do { _ = try await MeetingStore(databaseURL: url).loadMeetings(); XCTFail("Expected incompatible version") } catch {}
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(try scalar("PRAGMA user_version", at: url), 4)
    }

    func testInitializationFailureRollsBackWithoutChangingExistingSchema() async throws {
        let url = try temporaryURL()
        try execute("CREATE TABLE meetings(existing TEXT); INSERT INTO meetings VALUES ('keep')", at: url)
        let original = try Data(contentsOf: url)
        do { _ = try await MeetingStore(databaseURL: url).loadMeetings(); XCTFail("Expected table conflict") } catch {}
        XCTAssertEqual(try scalar("PRAGMA user_version", at: url), 0)
        XCTAssertEqual(try scalar("SELECT count(*) FROM meetings WHERE existing='keep'", at: url), 1)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testMalformedV1SchemaFailsWithoutErasingData() async throws {
        let url = try temporaryURL()
        try execute("CREATE TABLE meetings(wrong TEXT); INSERT INTO meetings VALUES ('keep'); PRAGMA user_version=1", at: url)
        let original = try Data(contentsOf: url)
        do { _ = try await MeetingStore(databaseURL: url).loadMeetings(); XCTFail("Expected schema error") } catch {}
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testInvalidRecordsNeverBecomeSuccessfulEmptyResult() async throws {
        for row in ["'bad-id', 'valid', 1", "'00000000-0000-0000-0000-000000000001' || char(0) || 'invalid', 'valid', 1", "'00000000-0000-0000-0000-000000000001', CAST(X'FF' AS TEXT), 1", "'00000000-0000-0000-0000-000000000001', '   ', 1", "'00000000-0000-0000-0000-000000000001', 'valid', NULL", "'00000000-0000-0000-0000-000000000001', 'valid', 'invalid'"] {
            let url = try temporaryURL()
            try execute("CREATE TABLE meetings(id TEXT, name TEXT, createdAt REAL); PRAGMA user_version=1; INSERT INTO meetings VALUES (\(row))", at: url)
            let original = try Data(contentsOf: url)
            do { _ = try await MeetingStore(databaseURL: url).loadMeetings(); XCTFail("Expected invalid record") } catch {}
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }

    func testDebugDirectoryResolutionRejectsRelativeOrEmptyOverride() throws {
        #if DEBUG
        for value in ["", "relative/path"] {
            XCTAssertThrowsError(try MeetingStore.defaultDatabaseURL(environment: ["MEETING_RECORD_DATA_DIR": value]))
        }
        let url = try MeetingStore.defaultDatabaseURL(environment: ["MEETING_RECORD_DATA_DIR": "/tmp/meeting-record-isolated"])
        XCTAssertEqual(url.path, "/tmp/meeting-record-isolated/meetings.sqlite")
        #else
        let actual = try MeetingStore.defaultDatabaseURL(environment: ["MEETING_RECORD_DATA_DIR": "/tmp/ignored"])
        XCTAssertNotEqual(actual.path, "/tmp/ignored/meetings.sqlite")
        #endif
    }
}
