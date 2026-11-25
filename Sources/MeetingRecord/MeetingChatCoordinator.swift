import Combine
import Foundation
import OSLog

@MainActor
final class MeetingChatCoordinator: ObservableObject {
    @Published var draft = ""
    @Published private(set) var activity: ChatActivity = .preparing
    @Published private(set) var current: ChatConversation
    @Published private(set) var unavailableReason: String?
    @Published private(set) var error: String?
    @Published private(set) var ready = false
    private(set) var indexAvailable = false
    private var savedHistory: [ChatConversation] = []
    private let store: MeetingStore
    private let local: ChatProducer
    private var active: Task<Void, Never>?
    private var pendingWrite: Task<Void, Never>?
    private var sendSearchDraft = false
    private var pendingNewChat = false
    private let clock = ContinuousClock()
    private let performance = Logger(subsystem: "com.meetingrecord.app", category: "ChatPerformance")

    init(store: MeetingStore) {
        self.store = store
        local = OnDeviceMeetingChat.producer(store: store)
        current = ChatConversation()
    }

    var history: [ChatConversation] { savedHistory }
    var isStreaming: Bool { current.messages.last?.status.isActive == true }
    var configurationMessage: String? {
        guard indexAvailable else { return unavailableReason }
        let model = AISettings.model(for: .chat)
        if model.usesOpenAI { return !OpenAIKey.hasConfiguredKey ? "Add an OpenAI API key in Settings → AI." : nil }
        return unavailableReason
    }
    var canSend: Bool { ready && indexAvailable && configurationMessage == nil && !isStreaming }

    func activate() async {
        guard !ready else { return }
        do {
            let chats = try await store.loadChatHistory(recovering: true)
            let availability = OnDeviceMeetingChat.availabilityMessage()
            indexAvailable = try await store.chatIndexAvailable()
            try Task.checkCancellation()
            savedHistory = chats
            unavailableReason = !indexAvailable ? "Transcript search requires SQLite FTS5." : availability
            if !pendingNewChat { current = chats.first ?? ChatConversation() }
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
        resetChat(scope: nil)
        draft = question
        sendSearchDraft = true
        resumePendingChat()
    }

    private func resumePendingChat() {
        guard ready, sendSearchDraft else { return }
        sendSearchDraft = false
        if canSend { submitDraft() }
    }

    func startNewChat(for meetingID: UUID) {
        resetChat(scope: meetingID)
    }

    func watchModelReadiness() async {
        guard !AISettings.model(for: .chat).usesOpenAI else { return }
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

    func newChat() { resetChat(scope: current.scope) }

    private func resetChat(scope: UUID?) {
        stop()
        draft = ""
        sendSearchDraft = false
        pendingNewChat = !ready
        current = ChatConversation(scope: scope)
        error = nil
    }

    func select(_ id: UUID) {
        guard id != current.id, history.contains(where: { $0.id == id }) else { return }
        stop()
        guard let thread = history.first(where: { $0.id == id }) else { return }
        draft = ""
        sendSearchDraft = false
        current = thread
        error = nil
    }

    func setScope(_ id: UUID?) {
        guard current.scope != id else { return }
        stop()
        current.scope = id
        if !current.messages.isEmpty { publish() }
    }

    func submitDraft(thinkLonger: Bool = false) {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, canSend else { return }
        draft = ""
        send(question, thinkLonger: thinkLonger, retry: false)
    }

    func canRetry(_ message: ChatMessage) -> Bool {
        canSend && current.messages.last?.id == message.id &&
            [.failed, .interrupted, .stopped].contains(message.status)
    }

    func retry(_ message: ChatMessage, thinkLonger: Bool) {
        guard canRetry(message), let question = current.messages.dropLast().last, question.role == .user else { return }
        send(question.body, thinkLonger: thinkLonger, retry: true)
    }

    private func send(_ question: String, thinkLonger: Bool, retry: Bool) {
        let thread = current.id
        let requestID = UUID()
        let isNew = current.messages.isEmpty
        let scope = current.scope
        let prior = current.messages.dropLast(retry ? 2 : 0).filter { message in
            guard message.status == .complete else { return false }
            return scope == nil || message.sourceIDs.allSatisfy { $0 == scope }
        }.suffix(6)
        let request = ChatRequest(question: question, scope: scope, priorMessages: Array(prior), thinkLonger: thinkLonger)
        if isNew { current.title = String(question.prefix(55)) }
        error = nil
        activity = .preparing
        if retry, let previous = current.messages.last {
            current.messages[current.messages.count - 1] = ChatMessage(id: previous.id, role: .assistant,
                status: .pending, requestID: requestID)
        } else {
            current.messages.append(ChatMessage(role: .user, body: question, status: .complete))
            current.messages.append(ChatMessage(role: .assistant, status: .pending, requestID: requestID))
        }
        publish(changed: retry ? 1 : 2, create: isNew, retrying: retry)

        let producer = AISettings.model(for: .chat).usesOpenAI ? OpenAIChat.producer(store: store) : local
        let started = clock.now
        active = Task {
            var lastSave = started
            var loggedFirstText = false
            var lastRender: ContinuousClock.Instant?
            var buffered: ChatUpdate?
            var sources = Set<UUID>()
            do {
                for try await update in producer(request) {
                    try Task.checkCancellation()
                    guard current.id == thread, current.messages.last?.requestID == requestID, isStreaming else { return }
                    sources.formUnion(update.sourceIDs)
                    if let phase = update.activity {
                        activity = phase
                        if !update.sourceIDs.isEmpty {
                            current.messages[current.messages.count - 1].sourceIDs.formUnion(update.sourceIDs)
                        }
                        continue
                    }
                    buffered = update
                    let now = clock.now
                    if !loggedFirstText, !update.text.isEmpty {
                        let elapsed = started.duration(to: now).components
                        let milliseconds = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
                        performance.debug("First chat text after \(milliseconds, format: .fixed(precision: 1), privacy: .public) ms")
                        loggedFirstText = true
                    }
                    if lastRender.map({ $0.duration(to: now) >= .milliseconds(45) }) ?? true {
                        apply(update, sources: sources)
                        buffered = nil
                        lastRender = now
                    }
                    if lastSave.duration(to: now) >= .milliseconds(750) {
                        publish(changed: 1)
                        lastSave = now
                    }
                }
                try Task.checkCancellation()
                guard current.id == thread, current.messages.last?.requestID == requestID else { return }
                if let buffered { apply(buffered, sources: sources) }
                finish(.complete)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, current.id == thread, current.messages.last?.requestID == requestID else { return }
                if let buffered { apply(buffered, sources: sources) }
                self.error = error.localizedDescription
                finish(.failed)
            }
        }
    }

    private func apply(_ update: ChatUpdate, sources: Set<UUID>) {
        let index = current.messages.count - 1
        var message = current.messages[index]
        message.body = update.text
        message.status = .streaming
        message.citations = update.citations
        message.sourceIDs.formUnion(sources)
        current.messages[index] = message
        activity = .writing
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
        removeMessages { !$0.sourceIDs.isDisjoint(with: ids) }
    }

    func recordingDeleted(_ id: UUID) {
        removeMessages { $0.citations.contains { $0.recordingID == id } }
    }

    private func removeMessages(where hasRemovedSource: (ChatMessage) -> Bool) {
        stop()
        for thread in savedHistory.indices {
            for index in savedHistory[thread].messages.indices
            where hasRemovedSource(savedHistory[thread].messages[index]) {
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

    private func publish(changed: Int = 0, create: Bool = false, retrying: Bool = false) {
        current.updatedAt = .now
        savedHistory.removeAll { $0.id == current.id }
        savedHistory.insert(current, at: 0)
        let thread = current
        enqueue { try await $0.saveChat(thread, changed: changed, create: create, retrying: retrying) }
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
