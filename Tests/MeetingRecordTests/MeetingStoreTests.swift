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

    func testFreshDatabaseIsEmptyV8() async throws {
        let url = try temporaryURL()
        let meetings = try await MeetingStore(databaseURL: url).loadMeetings()
        XCTAssertTrue(meetings.isEmpty)
        XCTAssertEqual(try scalar("PRAGMA user_version", at: url), 8)
    }

    func testThirtyRecordsReopenUnicodeDuplicateNamesAndStableOrder() async throws {
        let url = try temporaryURL()
        _ = try await MeetingStore(databaseURL: url).loadMeetings()
        var expected: [Meeting] = []
        for i in 1...30 {
            let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", i))!
            let name = i < 3 ? "Reunião 日本語 español" : "Reunião \(i) " + String(repeating: "nome longo ", count: 20)
            expected.append(try Meeting(id: id, name: name, createdAt: Date(timeIntervalSince1970: Double(i / 2)), updatedAt: Date(timeIntervalSince1970: Double(i / 2))))
            try execute("INSERT INTO meetings(id, name, createdAt, updatedAt) VALUES ('\(id.uuidString)', '\(name)', \(i / 2), \(i / 2))", at: url)
        }
        expected.sort {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt
        }
        let first = try await MeetingStore(databaseURL: url).loadMeetings()
        let second = try await MeetingStore(databaseURL: url).loadMeetings()
        XCTAssertEqual(first, expected)
        XCTAssertEqual(second, expected)
    }

    func testHomeUsesCreationOrderAndPreservesV4Library() async throws {
        let url = try temporaryURL()
        let store = MeetingStore(databaseURL: url)
        var meetings: [Meeting] = []
        for index in 1...4 {
            meetings.append(try await store.createMeeting(id: UUID(), name: "Meeting \(index)"))
        }
        _ = try await store.renameMeeting(id: meetings[0].id, name: "Renamed first")
        try execute("""
            DROP TABLE meeting_tags;
            DROP TABLE tags;
            ALTER TABLE meetings DROP COLUMN description;
            DROP TABLE meeting_summaries;
            DROP TABLE pending_meeting_deletions;
            DROP TABLE calendar_meeting_inputs;
            PRAGMA user_version=4;
            """, at: url)

        let reopened = MeetingStore(databaseURL: url)
        let summary = try await reopened.loadHomeSummary()
        XCTAssertEqual(summary.meetings.map(\.id), meetings.suffix(3).reversed().map(\.id))
        XCTAssertEqual(summary.savedRecordingIDs, [])
        XCTAssertEqual(summary.completedTranscriptions, 0)
        let all = try await reopened.loadMeetings()
        XCTAssertEqual(all.first?.name, "Renamed first")
        XCTAssertEqual(try scalar("PRAGMA user_version", at: url), 8)
    }

    func testTranscriptionWorkBatchesAdjacentCheckpointsPerSource() async throws {
        let store = MeetingStore(databaseURL: try temporaryURL())
        let meeting = try await store.createMeeting(id: UUID(), name: "Batch")
        let recording = Recording(id: UUID(), meetingID: meeting.id, startedAt: Date(), endedAt: nil, state: .starting)
        try await store.beginRecording(recording)
        try await store.markRecordingStarted(recording.id)
        for (offset, source) in [(Int64(0), AudioSegment.Source.me), (Int64(5_000_000_000), .me),
                                 (Int64(0), .other), (Int64(5_000_000_000), .other)] {
            try await store.registerSegment(AudioSegment(recordingID: recording.id, source: source,
                startOffset: offset, frameCount: 240_000, relativePath: "\(source.rawValue)/\(offset).caf"))
        }
        let next = try await store.nextTranscriptionWork()
        let work = try XCTUnwrap(next)
        XCTAssertEqual(work.audioSegments.count, 2)
        XCTAssertEqual(work.audioSegments.map(\.source), [.me, .me])
        _ = try await store.claimTranscript(recording.id, model: .base)
        try await store.saveTranscript(work.audioSegments, result: TranscribedCheckpoint(processedThrough: 10_000_000_000,
            segments: [.init(startOffset: 1_000_000_000, endOffset: 2_000_000_000, text: "first"),
                       .init(startOffset: 6_000_000_000, endOffset: 7_000_000_000, text: "second")]))
        let passages = try await store.transcriptPassages(for: meeting.id)
        XCTAssertEqual(passages.map(\.text), ["first", "second"])
        let matches = try await store.searchMeetings(.init(text: "SECOND", selectedTagIDs: []))
        XCTAssertEqual(matches.map(\.id), [meeting.id])
        XCTAssertEqual(matches.first?.transcriptExcerpt, "second")
        let other = try await store.nextTranscriptionWork()
        let otherWork = try XCTUnwrap(other)
        XCTAssertEqual(otherWork.audioSegments.map(\.source), [.other, .other])
    }

    func testSearchCombinesSharedTagsAndMeetingText() async throws {
        let url = try temporaryURL()
        let store = MeetingStore(databaseURL: url)
        let first = try await store.createMeeting(id: UUID(), name: "Planning")
        let second = try await store.createMeeting(id: UUID(), name: "Follow up")
        let legacyID = second.id.uuidString.lowercased()
        try execute("UPDATE meetings SET id = '\(legacyID)' WHERE id = '\(second.id.uuidString)'", at: url)
        let work = try Tag(id: UUID(), name: "work", color: .blue)
        let oneOnOne = try Tag(id: UUID(), name: "1-1", color: .gold)
        try await store.saveMeetingTags(meetingID: first.id, selectedTagIDs: [work.id, oneOnOne.id],
                                        newTags: [work, oneOnOne])
        try await store.saveMeetingTags(meetingID: second.id, selectedTagIDs: [work.id], newTags: [])
        _ = try await store.updateMeeting(id: first.id, name: first.name, description: "  Budget at 50%  ",
                                          selectedTagIDs: [work.id, oneOnOne.id])

        let reopened = MeetingStore(databaseURL: url)
        let tagMatches = try await reopened.searchMeetings(.init(text: "WORK", selectedTagIDs: []))
        XCTAssertEqual(Set(tagMatches.map(\.id)), [first.id, second.id])
        let tagOnly = try await reopened.searchMeetings(.init(text: "", selectedTagIDs: [work.id, oneOnOne.id]))
        XCTAssertEqual(tagOnly.map(\.id), [first.id])
        let combined = try await reopened.searchMeetings(.init(text: "50%", selectedTagIDs: [work.id, oneOnOne.id]))
        XCTAssertEqual(combined.map(\.id), [first.id])
        XCTAssertEqual(combined.first?.meeting.description, "Budget at 50%")
        XCTAssertEqual(Set(combined.first?.assignedTags.map(\.id) ?? []), [work.id, oneOnOne.id])
        let rejected = try await reopened.searchMeetings(.init(text: "Follow", selectedTagIDs: [work.id, oneOnOne.id]))
        XCTAssertTrue(rejected.isEmpty)
    }

    func testMeetingEditSavesAllFieldsAndRollsBackIfLabelsFail() async throws {
        let url = try temporaryURL()
        let store = MeetingStore(databaseURL: url)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let meeting = try await store.createMeeting(id: UUID(), name: "Planning", description: "Old notes",
                                                    calendarEventDate: date, calendarName: "Work")
        let tag = try Tag(id: UUID(), name: "Follow Up", color: .blue)
        try await store.saveTag(tag, updating: false)

        let edited = try await store.updateMeeting(id: meeting.id, name: "  Review ", description: " ",
                                                   selectedTagIDs: [tag.id])
        XCTAssertEqual(edited.name, "Review")
        XCTAssertNil(edited.description)
        XCTAssertEqual(edited.tags, [tag])
        XCTAssertEqual(edited.calendarEventDate, date)
        XCTAssertEqual(edited.calendarName, "Work")

        do {
            _ = try await store.updateMeeting(id: meeting.id, name: "Unsaved", description: "Unsaved notes",
                                              selectedTagIDs: [UUID()])
            XCTFail("An unavailable label should fail the edit")
        } catch MeetingStoreError.notFound {}

        let persisted = try await MeetingStore(databaseURL: url).loadMeetings()
        XCTAssertEqual(persisted, [edited])
    }

    @MainActor
    func testSummaryWaitsForCompleteTranscriptAndTracksItsRevision() async throws {
        actor Calls {
            var prompts: [String] = []
            var count: Int { prompts.count }
            func next(prompt: String) -> Int { prompts.append(prompt); return count }
        }
        enum Failure: Error { case modelUnavailable }
        let url = try temporaryURL()
        let store = MeetingStore(databaseURL: url)
        let meeting = try await store.createMeeting(id: UUID(), name: "Summary owner")
        let other = try await store.createMeeting(id: UUID(), name: "Other meeting")
        let empty = try await store.summarySnapshot(for: meeting.id)
        XCTAssertFalse(empty.canGenerate)

        let recording = Recording(id: UUID(), meetingID: meeting.id, startedAt: Date(), endedAt: nil, state: .starting)
        try await store.beginRecording(recording)
        try await store.markRecordingStarted(recording.id)
        let audio = AudioSegment(recordingID: recording.id, source: .me, startOffset: 0,
                                 frameCount: 48_000, relativePath: "summary.caf")
        try await store.registerSegment(audio)
        _ = try await store.claimTranscript(recording.id, model: .base)
        try await store.saveTranscript(audio, result: .init(processedThrough: 1_000_000_000,
            segments: [.init(startOffset: 0, endOffset: 1_000_000_000, text: "We agreed to ship on Friday.")]))
        let recordingSnapshot = try await store.summarySnapshot(for: meeting.id)
        XCTAssertFalse(recordingSnapshot.canGenerate)
        _ = try await store.finalizeRecording(recording.id, endedAt: Date(), interrupted: false)
        let queued = try await store.summarySnapshot(for: meeting.id)
        XCTAssertFalse(queued.canGenerate)
        _ = try await store.finishDrainedTranscripts()

        let ready = try await store.summarySnapshot(for: meeting.id)
        XCTAssertTrue(ready.canGenerate)
        XCTAssertTrue(ready.transcript.contains("Me: We agreed to ship on Friday."))
        let calls = Calls()
        let coordinator = MeetingSummaryCoordinator(store: store) { _, _, prompt in
            guard await calls.next(prompt: prompt) == 1 else { throw Failure.modelUnavailable }
            return "Ship on Friday."
        }
        let beforeClick = await calls.count
        XCTAssertEqual(beforeClick, 0)
        let customPrompt = "Respond in Brazilian Portuguese using three bullets."
        coordinator.generate(for: meeting.id, prompt: customPrompt)
        coordinator.generate(for: meeting.id)
        for _ in 0..<100 where coordinator.generating.contains(meeting.id) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(coordinator.generating.contains(meeting.id))
        let afterClick = await calls.count
        XCTAssertEqual(afterClick, 1)
        let receivedPrompts = await calls.prompts
        XCTAssertEqual(receivedPrompts, [customPrompt])
        let reopened = MeetingStore(databaseURL: url)
        let saved = try await reopened.summarySnapshot(for: meeting.id)
        XCTAssertEqual(saved.summary?.text, "Ship on Friday.")
        XCTAssertFalse(saved.isOutdated)
        let unrelated = try await reopened.summarySnapshot(for: other.id)
        XCTAssertNil(unrelated.summary)
        coordinator.generate(for: meeting.id)
        for _ in 0..<100 where coordinator.generating.contains(meeting.id) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(coordinator.errors[meeting.id])
        let afterFailure = try await reopened.summarySnapshot(for: meeting.id)
        XCTAssertEqual(afterFailure.summary?.text, "Ship on Friday.")

        try execute("UPDATE transcript_segments SET text = 'Ship on Monday.'", at: url)
        let changed = try await reopened.summarySnapshot(for: meeting.id)
        XCTAssertTrue(changed.isOutdated)
        try await reopened.deleteMeeting(meeting.id)
        XCTAssertEqual(try scalar("SELECT count(*) FROM meeting_summaries", at: url), 0)
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
        try execute("CREATE TABLE sentinel(value TEXT); INSERT INTO sentinel VALUES ('preserve'); PRAGMA user_version=8", at: url)
        let original = try Data(contentsOf: url)
        do { _ = try await MeetingStore(databaseURL: url).loadMeetings(); XCTFail("Expected incompatible version") } catch {}
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(try scalar("PRAGMA user_version", at: url), 8)
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
