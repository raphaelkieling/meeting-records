import Combine
import Foundation

@MainActor
final class MeetingChatCoordinator: ObservableObject {
    @Published private(set) var current: ChatConversation
    @Published private(set) var unavailableReason: String?
    @Published private(set) var error: String?
    @Published private(set) var ready = false
    private var indexAvailable = false
    private var savedHistory: [ChatConversation] = []
    private let store: MeetingStore
    private let local: ChatProducer
    private var active: Task<Void, Never>?
    private var pendingWrite: Task<Void, Never>?
    private var pendingQuestion: String?
    private var pendingNewChat = false
    private let clock = ContinuousClock()

    init(store: MeetingStore) {
        self.store = store
        local = OnDeviceMeetingChat.producer(store: store)
        current = ChatConversation()
    }

    var history: [ChatConversation] { savedHistory }
    var isStreaming: Bool { current.messages.last?.status.isActive == true }
    var configurationMessage: String? {
        guard indexAvailable else { return "Transcript search requires SQLite FTS5." }
        let model = SummaryModel(rawValue: UserDefaults.standard.string(forKey: "selectedMeetingChatModel") ?? "") ?? .appleIntelligence
        if model.usesOpenAI { return (try? OpenAIChatKey.load()) == nil ? "Add an OpenAI API key in Settings → Chat." : nil }
        return unavailableReason
    }
    var canSend: Bool { ready && configurationMessage == nil && !isStreaming }

    func activate() async {
        guard !ready else { return }
        do {
            let chats = try await store.loadChatHistory(recovering: true)
            let selected = SummaryModel(rawValue: UserDefaults.standard.string(forKey: "selectedMeetingChatModel") ?? "") ?? .appleIntelligence
            let availability = selected.usesOpenAI ? nil : OnDeviceMeetingChat.availabilityMessage()
            indexAvailable = try await store.chatIndexAvailable()
            try Task.checkCancellation()
            savedHistory = chats
            unavailableReason = !indexAvailable ? "Transcript search requires SQLite FTS5." : availability
            if !pendingNewChat {
                current = pendingQuestion == nil ? (chats.first ?? ChatConversation()) : ChatConversation(scope: nil)
            }
            pendingNewChat = false
        } catch is CancellationError {
            return
        } catch {
            self.error = "Could not open chat history. \(error.localizedDescription)"
        }
        ready = true
        resumePendingChat()
    }

    func startChat(with question: String) {
        stop()
        current = ChatConversation(scope: nil)
        pendingNewChat = true
        error = nil
        pendingQuestion = question
        resumePendingChat()
    }

    func resumePendingChat() {
        guard ready, let question = pendingQuestion else { return }
        guard canSend else {
            error = configurationMessage
            return
        }
        pendingQuestion = nil
        send(question)
    }

    func startNewChat(for meetingID: UUID) {
        stop()
        pendingQuestion = nil
        pendingNewChat = true
        current = ChatConversation(scope: meetingID)
        error = nil
    }

    func watchModelReadiness() async {
        guard SummaryModel(rawValue: UserDefaults.standard.string(forKey: "selectedMeetingChatModel") ?? "")?.usesOpenAI != true else { return }
        var latest = MeetingSummarizer.availability()
        await MeetingSummarizer.watchAvailability { [weak self] status in
            latest = status
            if let reason = status.message { self?.unavailableReason = reason }
        }
        guard !Task.isCancelled, latest == .ready else { return }
        do {
            indexAvailable = try await store.chatIndexAvailable()
            unavailableReason = indexAvailable ? nil : "Transcript search requires SQLite FTS5."
        } catch {
            unavailableReason = "Could not open transcript search. \(error.localizedDescription)"
        }
    }

    func refreshIndex() async {
        do { try await MeetingChatRetrieval.refresh(store) }
        catch is CancellationError {}
        catch { self.error = "Could not index transcripts. \(error.localizedDescription)" }
    }

    func newChat() {
        stop()
        current = ChatConversation(scope: current.scope)
        error = nil
    }

    func select(_ id: UUID) {
        guard id != current.id, history.contains(where: { $0.id == id }) else { return }
        stop()
        guard let thread = history.first(where: { $0.id == id }) else { return }
        current = thread
        error = nil
    }

    func setScope(_ id: UUID?) {
        guard current.scope != id else { return }
        stop()
        current.scope = id
        if !current.messages.isEmpty { publish() }
    }

    func send(_ input: String) {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, canSend else { return }
        let thread = current.id
        let requestID = UUID()
        let isNew = current.messages.isEmpty
        let scope = current.scope
        let prior = current.messages.filter { message in
            guard message.status == .complete else { return false }
            return scope == nil || message.sourceIDs.allSatisfy { $0 == scope }
        }.suffix(6)
        let request = ChatRequest(question: question, scope: scope, priorMessages: Array(prior))
        if isNew { current.title = String(question.prefix(55)) }
        error = nil
        current.messages.append(ChatMessage(role: .user, body: question, status: .complete))
        current.messages.append(ChatMessage(role: .assistant, status: .pending, requestID: requestID))
        publish(changed: 2, create: isNew)

        let selectedModel = SummaryModel(rawValue: UserDefaults.standard.string(forKey: "selectedMeetingChatModel") ?? "") ?? .appleIntelligence
        let producer = selectedModel.usesOpenAI ? OpenAIChat.producer(store: store) : local
        active = Task {
            var lastSave = clock.now
            do {
                for try await update in producer(request) {
                    try Task.checkCancellation()
                    guard current.id == thread, current.messages.last?.requestID == requestID, isStreaming else { return }
                    let index = current.messages.count - 1
                    current.messages[index].body = update.text
                    current.messages[index].status = .streaming
                    current.messages[index].citations = update.citations
                    current.messages[index].sourceIDs.formUnion(update.sourceIDs)
                    if lastSave.duration(to: clock.now) >= .milliseconds(750) {
                        publish(changed: 1)
                        lastSave = clock.now
                    }
                }
                guard !Task.isCancelled, current.id == thread, current.messages.last?.requestID == requestID else { return }
                finish(.complete)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, current.id == thread, current.messages.last?.requestID == requestID else { return }
                self.error = error.localizedDescription
                finish(.failed)
            }
        }
    }

    func stop() {
        active?.cancel()
        active = nil
        if isStreaming { finish(.stopped) }
    }

    func deleteConversation(_ id: UUID) {
        if id == current.id { stop() }
        savedHistory.removeAll { $0.id == id }
        enqueue { try await $0.deleteChat(id) }
        if current.id == id { current = history.first ?? ChatConversation() }
    }

    func meetingsDeleted(_ ids: Set<UUID>) {
        stop()
        for thread in savedHistory.indices {
            for index in savedHistory[thread].messages.indices
            where !savedHistory[thread].messages[index].sourceIDs.isDisjoint(with: ids) {
                var message = savedHistory[thread].messages[index]
                message.body = ""
                message.status = .sourceRemoved
                message.citations = []
                message.sourceIDs = []
                savedHistory[thread].messages[index] = message
            }
        }
        if let thread = savedHistory.first(where: { $0.id == current.id }) { current = thread }
    }

    private func finish(_ status: ChatMessage.Status) {
        guard isStreaming else { return }
        current.messages[current.messages.count - 1].status = status
        active = nil
        publish(changed: 1)
    }

    private func publish(changed: Int = 0, create: Bool = false) {
        current.updatedAt = .now
        savedHistory.removeAll { $0.id == current.id }
        savedHistory.insert(current, at: 0)
        let thread = current
        enqueue { try await $0.saveChat(thread, changed: changed, create: create) }
    }

    private func enqueue(_ write: @escaping @Sendable (MeetingStore) async throws -> Void) {
        let previous = pendingWrite
        let store = self.store
        pendingWrite = Task { [weak self] in
            await previous?.value
            do { try await write(store) }
            catch { self?.error = "Could not save chat history. \(error.localizedDescription)" }
        }
    }
}
