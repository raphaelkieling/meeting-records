import Foundation

struct ChatConversation: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    var scope: UUID?
    var updatedAt: Date
    var messages: [ChatMessage]

    init(id: UUID = UUID(), title: String = "New Chat", scope: UUID? = nil,
         updatedAt: Date = .now, messages: [ChatMessage] = []) {
        self.id = id
        self.title = title
        self.scope = scope
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

struct ChatMessage: Identifiable, Codable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }

    enum Status: String, Codable, Sendable {
        case pending, streaming, complete, stopped, failed, interrupted, sourceRemoved

        var isActive: Bool { self == .pending || self == .streaming }
    }

    let id: UUID
    let role: Role
    var body: String
    var status: Status
    let requestID: UUID?
    var citations: [ChatCitation] = []
    var sourceIDs: Set<UUID> = []

    init(id: UUID = UUID(), role: Role, body: String = "", status: Status, requestID: UUID? = nil) {
        self.id = id
        self.role = role
        self.body = body
        self.status = status
        self.requestID = requestID
    }
}

struct ChatCitation: Identifiable, Codable, Sendable, Hashable {
    let meetingID: UUID
    let recordingID: UUID
    let passageIDs: [String]
    let startOffset: Int64
    let revision: Int64

    var screenCaptureID: UUID? = nil

    var id: String { "\(recordingID):\(revision):\(screenCaptureID?.uuidString ?? passageIDs.first ?? "")" }

    var timestamp: String { Self.timestamp(at: startOffset) }

    static func timestamp(at offset: Int64) -> String {
        let seconds = offset / 1_000_000_000
        return String(format: "%lld:%02lld", seconds / 60, seconds % 60)
    }
}

struct ChatRequest: Sendable {
    let question: String
    let scope: UUID?
    let priorMessages: [ChatMessage]
    var thinkLonger = false
}

enum ChatActivity: Sendable {
    case preparing, searching, writing

    var label: String {
        switch self {
        case .preparing: "Preparing answer…"
        case .searching: "Searching meetings…"
        case .writing: "Writing answer…"
        }
    }
}

struct ChatUpdate: Sendable {
    let text: String
    var citations: [ChatCitation] = []
    var sourceIDs: Set<UUID> = []
    var activity: ChatActivity?
}

typealias ChatProducer = @Sendable (ChatRequest) -> AsyncThrowingStream<ChatUpdate, Error>

func chatStream(
    _ produce: @escaping @Sendable (AsyncThrowingStream<ChatUpdate, Error>.Continuation) async throws -> Void
) -> AsyncThrowingStream<ChatUpdate, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                try await produce(continuation)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
