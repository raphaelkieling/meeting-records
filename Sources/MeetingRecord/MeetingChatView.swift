import SwiftUI

struct MeetingChatView: View {
    @ObservedObject var chat: MeetingChatCoordinator
    let meetings: [Meeting]
    let openAISettings: () -> Void
    let returnToMessage: UUID?
    let openCitation: (ChatCitation, UUID) async -> Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var composerFocused: Bool
    @State private var thinkLonger = false
    @State private var followsBottom = true
    @State private var pendingDeletion: UUID?
    @State private var unavailableCitations: Set<String> = []
    @State private var hasMoreChatBelow = false

    var body: some View {
        VStack(spacing: 10) {
            header
            if chat.ready {
                if chat.current.messages.isEmpty {
                    MeetingEmptyState("Start a conversation", icon: "bubble.left.and.bubble.right",
                                      detail: "Ask a question about your meetings.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    conversation
                }
                composer
            } else {
                ProgressView("Opening chat…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await chat.activate()
            if !chat.draft.isEmpty || (chat.current.scope != nil && chat.current.messages.isEmpty) {
                composerFocused = true
            }
            await chat.watchModelReadiness()
        }
        .confirmationDialog("Delete this conversation?", isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("Delete Conversation", role: .destructive) {
                if let id = pendingDeletion { chat.deleteConversation(id) }
                pendingDeletion = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Picker("Meeting Scope", selection: Binding(get: { chat.current.scope }, set: chat.setScope)) {
                Text("All Meetings").tag(nil as UUID?)
                ForEach(meetings) { Text($0.name).tag(Optional($0.id)) }
                if let id = chat.current.scope, !meetings.contains(where: { $0.id == id }) {
                    Text("Meeting Unavailable").tag(Optional(id))
                }
            }
            .labelsHidden()
            .accessibilityLabel("Meeting Scope")
            .frame(maxWidth: 260)
            Spacer()
            Menu {
                Picker("Conversation", selection: Binding(get: { Optional(chat.current.id) }, set: {
                    if let id = $0 { chat.select(id) }
                })) {
                    if !chat.history.contains(where: { $0.id == chat.current.id }) {
                        Text("New Chat").tag(Optional(chat.current.id))
                    }
                    ForEach(chat.history) { Text($0.title).tag(Optional($0.id)) }
                }
                Divider()
                if chat.history.contains(where: { $0.id == chat.current.id }) {
                    Button("Delete Conversation", role: .destructive) { pendingDeletion = chat.current.id }
                }
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .fixedSize()
            Button("New Chat", systemImage: "plus") {
                chat.newChat()
                thinkLonger = false
                composerFocused = true
            }
            .fixedSize()
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(chat.current.messages) { message in
                        messageRow(message).id(message.id)
                            .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 6)))
                    }
                }
                .frame(maxWidth: 680)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.17), value: chat.current.messages.count)
                Color.clear.frame(height: 1).id("chat-end")
                    .onGeometryChange(for: Bool.self) { geometry in
                        guard let viewport = geometry.bounds(of: .scrollView) else { return true }
                        return geometry.frame(in: .scrollView).maxY <= viewport.height + 32
                    } action: { followsBottom = $0 }
            }
            .contentMargins(.all, EdgeInsets(top: 0, leading: 0, bottom: 72, trailing: 12), for: .scrollContent)
            .onGeometryChange(for: Bool.self) { geometry in
                guard let viewport = geometry.bounds(of: .scrollView) else { return false }
                return geometry.frame(in: .scrollView).maxY > viewport.height + 1
            } action: { hasMoreChatBelow = $0 }
            .bottomScrollFade(hasMoreBelow: hasMoreChatBelow)
            .onChange(of: chat.current.id, initial: true) {
                followsBottom = true
                if let returnToMessage, chat.current.messages.contains(where: { $0.id == returnToMessage }) {
                    proxy.scrollTo(returnToMessage, anchor: .center)
                }
                else { proxy.scrollTo("chat-end", anchor: .bottom) }
            }
            .onChange(of: chat.current.messages.count) {
                if followsBottom { proxy.scrollTo("chat-end", anchor: .bottom) }
            }
            .onChange(of: chat.current.messages.last?.body) {
                if followsBottom { proxy.scrollTo("chat-end", anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        if message.role == .user {
            Text(verbatim: message.body)
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(Color.meetingAccent, in: RoundedRectangle(cornerRadius: 14))
                .padding(.leading, 36)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if message.status.isActive, message.body.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).accessibilityHidden(true)
                        Text(chat.activity.label).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !message.body.isEmpty {
                    ChatMarkdownView(markdown: message.body).equatable()
                    if message.status.isActive {
                        Text(chat.activity.label).font(.caption).foregroundStyle(.secondary)
                    }
                }
                switch message.status {
                case .stopped: Text("Stopped").foregroundStyle(.secondary).font(.caption)
                case .failed: Text("Reply failed").foregroundStyle(.secondary).font(.caption)
                case .interrupted: Text("Interrupted").foregroundStyle(.secondary).font(.caption)
                case .sourceRemoved: Text("Source meeting deleted").foregroundStyle(.secondary).font(.caption)
                default: EmptyView()
                }
                if chat.canRetry(message) {
                    Button("Retry", systemImage: "arrow.clockwise") {
                        followsBottom = true
                        chat.retry(message, thinkLonger: thinkLonger)
                    }
                    .buttonStyle(.link)
                }
                ForEach(message.citations) { citation in
                    let title = meetings.first(where: { $0.id == citation.meetingID })?.name
                    if let title, !unavailableCitations.contains(citation.id) {
                        Button {
                            Task { if !(await openCitation(citation, message.id)) { unavailableCitations.insert(citation.id) } }
                        } label: {
                            Label("\(title) · \(citation.timestamp)", systemImage: "text.bubble")
                        }
                        .buttonStyle(.link)
                    } else {
                        Text("Source unavailable").foregroundStyle(.secondary).font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 24)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let reason = chat.configurationMessage {
                HStack {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                    if chat.indexAvailable {
                        Button("Open AI Settings", action: openAISettings).buttonStyle(.link)
                    }
                }
            } else if let error = chat.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            VStack(alignment: .leading, spacing: 8) {
                TextField("Ask about your meetings", text: $chat.draft, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(1...6).focused($composerFocused)
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) { return .ignored }
                        send(); return .handled
                    }
                HStack {
                    if AISettings.model(for: .chat).usesOpenAI {
                        Toggle("Think Longer", systemImage: "brain", isOn: $thinkLonger)
                            .toggleStyle(.button)
                            .controlSize(.small)
                            .help("Use more reasoning for the next answer.")
                    }
                    Spacer()
                    if chat.isStreaming {
                        Button(action: chat.stop) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(.black, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Stop")
                    } else {
                        Button(action: send) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.meetingAccent, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain).disabled(!canSubmit).opacity(canSubmit ? 1 : 0.45)
                        .accessibilityLabel("Send")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 9)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 4)
        }
    }

    private func send() {
        guard canSubmit else { return }
        followsBottom = true
        chat.submitDraft(thinkLonger: thinkLonger)
        thinkLonger = false
    }

    private var canSubmit: Bool {
        guard chat.canSend, !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let scope = chat.current.scope else { return true }
        return meetings.contains { $0.id == scope }
    }
}
