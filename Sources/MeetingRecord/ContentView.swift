import SwiftUI

enum Destination: Hashable {
    case home, settings, meeting(UUID)
}

enum MeetingLoadState {
    case loading, loaded([Meeting]), failed(String)
}

enum RenameOrigin { case sidebar, header }

struct RenameSession {
    let id: UUID
    let origin: RenameOrigin
    var draft: String
    var error: String?
}

private enum MeetingAction {
    case navigate(Destination), create, rename(UUID, RenameOrigin)
}

struct ContentView: View {
    @State private var destination: Destination = .home
    @State private var state: MeetingLoadState = .loading
    @State private var editor: RenameSession?
    @State private var isSaving = false
    @State private var mutationError: String?
    @State private var pendingAction: MeetingAction?
    @State private var creation: (id: UUID, name: String)?
    @State private var revealID: UUID?
    @State private var revealVersion = 0
    private let store = MeetingStore()

    private var meetings: [Meeting] {
        if case .loaded(let values) = state { values } else { [] }
    }

    private var selectedMeeting: Meeting? {
        if case .meeting(let id) = destination { meetings.first { $0.id == id } } else { nil }
    }

    private var canCreate: Bool {
        if case .loaded = state { !isSaving } else { false }
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                destination: destination, state: state, editor: $editor, isSaving: isSaving,
                canCreate: canCreate, revealID: revealID, revealVersion: revealVersion,
                navigate: { request(.navigate($0)) }, create: { request(.create) },
                rename: { request(.rename($0, .sidebar)) }, save: saveRename, cancel: cancelRename,
                retry: { Task { await loadMeetings() } }
            )
            Divider()
            VStack(alignment: .leading, spacing: 20) {
                if let meeting = selectedMeeting {
                    InlineMeetingName(meeting: meeting, origin: .header, editor: $editor,
                                      isSaving: isSaving, begin: { request(.rename(meeting.id, .header)) },
                                      save: saveRename, cancel: cancelRename)
                        .font(.largeTitle.bold())
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Button {} label: {
                                Label("Transcription", systemImage: "text.alignleft")
                                    .labelStyle(.titleAndIcon)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                            .accessibilityLabel("Transcription")
                            .accessibilityValue("Selected tab")
                            .accessibilityAddTraits(.isSelected)
                            Spacer()
                        }
                        .padding(.bottom, 12)
                        Divider()
                        Text("No transcription yet.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 20)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .onTapGesture { if editor != nil { saveRename() } }
                } else {
                    Text(destination == .settings ? "Settings" : "Home").font(.largeTitle.bold())
                    Text(destination == .settings ? "Settings will appear here." : "Your meeting workspace.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                if let mutationError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(mutationError).foregroundStyle(.red).textSelection(.enabled)
                        HStack {
                            Button("Try Again") { request(.create) }.disabled(isSaving)
                            Button("Dismiss") { self.mutationError = nil; creation = nil }.disabled(isSaving)
                        }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .task { await loadMeetings() }
    }

    private func request(_ action: MeetingAction) {
        if isSaving {
            if editor != nil { pendingAction = action }
            return
        }
        if editor != nil {
            pendingAction = action
            saveRename()
        } else {
            perform(action)
        }
    }

    private func perform(_ action: MeetingAction) {
        switch action {
        case .navigate(let target): destination = target
        case .create: createMeeting()
        case .rename(let id, let origin):
            guard let meeting = meetings.first(where: { $0.id == id }) else { return }
            destination = .meeting(id)
            editor = RenameSession(id: id, origin: origin, draft: meeting.name)
        }
    }

    private func merge(_ meeting: Meeting) {
        state = .loaded((meetings.filter { $0.id != meeting.id } + [meeting]).sorted(by: Meeting.mostRecentFirst))
        revealID = meeting.id
        revealVersion += 1
    }

    private func createMeeting() {
        guard canCreate else { return }
        if creation == nil {
            let adjective = ["Quiet", "Bright", "Clear", "Fresh", "Calm", "Open"].randomElement()!
            let noun = ["River", "Meadow", "Forest", "Sky", "Ocean", "Summit"].randomElement()!
            creation = (UUID(), "\(adjective) \(noun)")
        }
        guard let creation else { return }
        isSaving = true
        mutationError = nil
        Task {
            do {
                let meeting = try await store.createMeeting(id: creation.id, name: creation.name)
                merge(meeting)
                destination = .meeting(meeting.id)
                self.creation = nil
            } catch { mutationError = error.localizedDescription }
            isSaving = false
        }
    }

    private func saveRename() {
        guard let session = editor, !isSaving else { return }
        do { _ = try Meeting.normalizedName(session.draft) }
        catch { editor?.error = error.localizedDescription; return }
        isSaving = true
        editor?.error = nil
        Task {
            do {
                let meeting = try await store.renameMeeting(id: session.id, name: session.draft)
                merge(meeting)
                editor = nil
                isSaving = false
                let action = pendingAction
                pendingAction = nil
                if let action { perform(action) }
            } catch {
                editor?.error = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func cancelRename() {
        guard !isSaving else { return }
        editor = nil
        pendingAction = nil
    }

    private func loadMeetings() async {
        state = .loading
        do { state = .loaded(try await store.loadMeetings()) }
        catch { state = .failed(error.localizedDescription) }
    }
}

struct InlineMeetingName: View {
    let meeting: Meeting
    let origin: RenameOrigin
    @Binding var editor: RenameSession?
    let isSaving: Bool
    let begin: () -> Void
    let save: () -> Void
    let cancel: () -> Void
    @FocusState private var isFocused: Bool

    private var isEditing: Bool { editor?.id == meeting.id && editor?.origin == origin }
    private var draft: Binding<String> {
        Binding(get: { editor?.draft ?? meeting.name }, set: { value in
            guard editor?.draft != value else { return }
            editor?.draft = value
            editor?.error = nil
        })
    }

    var body: some View {
        Group {
            if isEditing {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Meeting name", text: draft)
                        .textFieldStyle(.roundedBorder)
                        .focused($isFocused)
                        .disabled(isSaving)
                        .onSubmit(save)
                        .onExitCommand(perform: cancel)
                        .accessibilityLabel("Meeting name")
                        .help("Enter to save. Escape to cancel.")
                        .task {
                            await Task.yield()
                            isFocused = true
                        }
                        .onChange(of: isFocused) { _, focused in
                            if !focused && !isSaving {
                                Task { @MainActor in
                                    await Task.yield()
                                    if isEditing && !isFocused && !isSaving { save() }
                                }
                            }
                        }
                    if let error = editor?.error {
                        Text(error).font(.caption).foregroundStyle(.red)
                        HStack {
                            Button("Try Again", action: save)
                            Button("Cancel", action: cancel)
                        }.font(.caption)
                    }
                }
                .onChange(of: editor?.error) { _, error in if error != nil { isFocused = true } }
            } else {
                Text(meeting.name)
                    .lineLimit(origin == .sidebar ? 1 : 2)
                    .truncationMode(.tail)
                    .help(meeting.name + " — Double-click to rename")
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: begin)
                    .contextMenu { Button("Rename", action: begin) }
                    .accessibilityAction(named: Text("Rename"), begin)
            }
        }
        .focusable(origin == .header && !isEditing)
        .focusedValue(\.renameMeeting, !isEditing && !isSaving ? begin : nil)
    }
}
