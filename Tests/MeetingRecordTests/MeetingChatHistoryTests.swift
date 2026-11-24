import XCTest
@testable import MeetingRecord

final class MeetingChatHistoryTests: XCTestCase {
    func testHistoryRecoversPartialReplyAndClearsDependentAnswersOnDeletion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("meetings.sqlite")
        let store = MeetingStore(databaseURL: url)
        let meeting = try await store.createMeeting(id: UUID(), name: "Private meeting")
        let other = try await store.createMeeting(id: UUID(), name: "Another meeting")
        let user = ChatMessage(role: .user, body: "What happened?", status: .complete)
        var assistant = ChatMessage(role: .assistant, body: "Private detail", status: .streaming, requestID: UUID())
        assistant.sourceIDs = [meeting.id, other.id]
        let thread = ChatConversation(title: user.body, messages: [user, assistant])
        try await store.saveChat(thread, changed: 2, create: true)
        let restarted = MeetingStore(databaseURL: url)
        let history = try await restarted.loadChatHistory(recovering: true)
        XCTAssertEqual(history.first?.messages.last?.status, .interrupted)
        XCTAssertEqual(history.first?.messages.last?.body, assistant.body)

        try await restarted.deleteMeeting(meeting.id)
        try await restarted.saveChat(thread, changed: 1, create: false)
        let invalidated = try await restarted.loadChatHistory()
        XCTAssertEqual(invalidated.first?.messages.last?.status, .sourceRemoved)
        XCTAssertEqual(invalidated.first?.messages.last?.body, "")
        XCTAssertEqual(invalidated.first?.messages.last?.sourceIDs, [])
        XCTAssertEqual(invalidated.first?.messages.first?.body, user.body)

        try await restarted.deleteChat(thread.id)
        try await restarted.saveChat(thread, changed: 1, create: false)
        let final = try await restarted.loadChatHistory()
        XCTAssertTrue(final.isEmpty)
    }
}
