import XCTest
@testable import MeetingRecord

final class MeetingChatRetrievalTests: XCTestCase {
    func testIndexRanksScopesReplacesAndDeletesSources() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MeetingStore(databaseURL: directory.appendingPathComponent("meetings.sqlite"))
        let indexAvailable = try await store.chatIndexAvailable()
        XCTAssertTrue(indexAvailable)
        let meeting = try await store.createMeeting(id: UUID(), name: "Release planning")
        let id = UUID()
        try await store.beginRecording(Recording(id: id, meetingID: meeting.id, startedAt: .now,
                                                 endedAt: nil, state: .starting))
        try await store.markRecordingStarted(id)
        let audio = AudioSegment(recordingID: id, source: .other, startOffset: 0,
                                 frameCount: 48_000, relativePath: "chat.caf")
        try await store.registerSegment(audio)
        _ = try await store.claimTranscript(id, model: .base)
        func checkpoint(_ text: String) -> TranscribedCheckpoint {
            .init(processedThrough: 1_000_000_000,
                  segments: [.init(startOffset: 0, endOffset: 1_000_000_000, text: text)])
        }
        try await store.saveTranscript(audio, result: checkpoint("A decisão de João foi validar o PIX antes de aprovar o piloto."))
        _ = try await store.finalizeRecording(id, endedAt: .now, interrupted: false)
        _ = try await store.finishDrainedTranscripts()
        try await MeetingChatRetrieval.refresh(store)
        let metadataHits = try await store.chatMeetingCandidates(terms: ["PIX"], scope: nil, from: nil, until: nil)
        XCTAssertTrue(metadataHits.isEmpty)
        let topicHits = try await store.chatEvidence(terms: ["PIX"], scope: nil)
        XCTAssertEqual(topicHits.first?.citation.meetingID, meeting.id)
        XCTAssertTrue(topicHits.first?.body.contains("validar o PIX antes") == true)

        let hits = try await store.chatEvidence(terms: ["decisao", "joao"], scope: meeting.id)
        let citation = try XCTUnwrap(hits.first?.citation)
        XCTAssertEqual(citation.recordingID, id)
        let current = try await store.isChatCitationCurrent(citation)
        XCTAssertTrue(current)
        let passageHits = try await store.findTranscriptPassages("decisao de joa")
        XCTAssertEqual(passageHits.first?.citation, citation)
        XCTAssertTrue(passageHits.first?.body.contains("João") == true)
        let scoped = try await store.chatEvidence(terms: ["joao"], scope: UUID())
        XCTAssertTrue(scoped.isEmpty)

        try await store.saveTranscript(audio, result: checkpoint("We scheduled the beta."))
        let stale = try await store.isChatCitationCurrent(citation)
        XCTAssertFalse(stale)
        try await MeetingChatRetrieval.refresh(store)
        let replaced = try await store.chatEvidence(terms: ["joao"], scope: nil)
        let beta = try await store.chatEvidence(terms: ["beta"], scope: nil)
        XCTAssertTrue(replaced.isEmpty)
        XCTAssertEqual(beta.count, 1)
        try await store.deleteMeeting(meeting.id)
        let deleted = try await store.chatEvidence(terms: ["beta"], scope: nil)
        XCTAssertTrue(deleted.isEmpty)
    }

    func testModelCanOnlyCiteRetrievedEvidence() {
        XCTAssertEqual(MeetingChatRetrieval.citationNumbers(in: "Decisão [2]. [99] [2] [1]", count: 2), [2, 1])
    }

    func testMeetingSearchFindsTermsInSavedSummary() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MeetingStore(databaseURL: directory.appendingPathComponent("meetings.sqlite"))
        let meeting = try await store.createMeeting(id: UUID(), name: "Release planning")
        let anotherMeeting = try await store.createMeeting(id: UUID(), name: "Team sync")
        let summary = String(repeating: "Release planning notes. ", count: 20) + "Validate instant payments before the pilot."
        try await store.saveSummary(.init(text: summary, model: "test", transcriptRevision: "fixture"), for: meeting.id)

        let candidates = try await store.chatMeetingCandidates(terms: ["instant payments"], scope: nil, from: nil, until: nil)
        XCTAssertEqual(candidates.map(\.id), [meeting.id])
        XCTAssertTrue(candidates.first?.summaryExcerpt?.contains("Validate instant payments") == true)
        let scoped = try await store.chatMeetingCandidates(terms: ["instant payments"], scope: anotherMeeting.id, from: nil, until: nil)
        XCTAssertTrue(scoped.isEmpty)
        let recent = try await store.chatMeetingCandidates(terms: [], scope: nil, from: nil, until: nil)
        XCTAssertEqual(Set(recent.map(\.id)), [meeting.id, anotherMeeting.id])
        XCTAssertNil(recent.first { $0.id == anotherMeeting.id }?.summaryExcerpt)
    }

    func testChunkLimitsPreserveUnicodeAndSourceIdentity() {
        let id = UUID()
        let passage = TranscriptPassage(inputID: id, source: .me, checkpoint: 0, sequence: 0,
            startOffset: 0, endOffset: 1_000_000_000, text: String(repeating: "Olá, João! 🧑🏽‍💻 ", count: 220))
        let chunks = MeetingChatRetrieval.chunks(from: [passage])
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.body.utf8.count <= 1_440 && $0.passageIDs == [passage.id] })
        let reconstructed = chunks.flatMap { $0.body.utf8.dropFirst(4) }
        XCTAssertTrue(reconstructed.elementsEqual(passage.text.utf8))
        let query = MeetingChatRetrieval.match((0..<30).map { "term\($0)" } + ["\" OR *"])
        XCTAssertEqual(query.components(separatedBy: " OR ").count, 16)
        XCTAssertFalse(query.contains("*"))
    }
}
