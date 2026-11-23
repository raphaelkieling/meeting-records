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
    @ObservedObject var recording: RecordingCoordinator
    @ObservedObject var transcription: TranscriptionCoordinator
    @State private var activeTab = MeetingTab.inputs
    private var store: MeetingStore { recording.store }

    private enum MeetingTab: String, CaseIterable {
        case inputs = "Inputs"
        case transcription = "Transcription"

        var icon: String {
            switch self {
            case .inputs: "tray"
            case .transcription: "text.bubble"
            }
        }
    }

    private var recordingMeetingID: UUID? {
        if case .recording(let id) = recording.state { id } else { nil }
    }

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
                recordingMeetingID: recordingMeetingID,
                navigate: { request(.navigate($0)) }, create: { request(.create) },
                rename: { request(.rename($0, .sidebar)) }, save: saveRename, cancel: cancelRename,
                retry: { Task { await loadMeetings() } }
            )
            Divider().ignoresSafeArea(.container, edges: .top)
            VStack(alignment: .leading, spacing: 20) {
                if let meeting = selectedMeeting {
                    InlineMeetingName(meeting: meeting, origin: .header, editor: $editor,
                                      isSaving: isSaving, begin: { request(.rename(meeting.id, .header)) },
                                      save: saveRename, cancel: cancelRename)
                        .font(.largeTitle.bold())
                    VStack(alignment: .leading, spacing: 0) {
                        meetingTabPicker
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 12)
                        if activeTab == .inputs {
                            InputsView(meetingID: meeting.id, store: store, revision: recording.revision,
                                       transcription: transcription,
                                       openSettings: { request(.navigate(.settings)) })
                                .id(meeting.id)
                        } else {
                            TranscriptionView(meetingID: meeting.id, store: store,
                                              recordingRevision: recording.revision, transcription: transcription)
                                .id(meeting.id)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .onTapGesture { if editor != nil { saveRename() } }
                    .overlay(alignment: .bottom) {
                        RecordingControl(state: recording.state, meetingID: meeting.id, levels: recording.levels,
                                         modelReady: transcription.isReady,
                                         openSettings: { request(.navigate(.settings)) }) {
                            recording.toggle(for: meeting.id)
                        }
                        .padding(.bottom, 12)
                    }
                } else {
                    Text(destination == .settings ? "Settings" : "Home").font(.largeTitle.bold())
                    if destination == .settings {
                        TranscriptionSettingsView(transcription: transcription)
                    } else {
                        Text("Your meeting workspace.").foregroundStyle(.secondary)
                    }
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
            .padding(.horizontal, 32)
            .padding(.bottom, selectedMeeting == nil ? 20 : 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .task {
            await recording.recover()
            await loadMeetings()
        }
        .onChange(of: selectedMeeting?.id) { _, _ in activeTab = .inputs }
        .alert("Recording", isPresented: Binding(get: { recording.error != nil },
                                                 set: { if !$0 { recording.error = nil } })) {
            Button("OK") { recording.error = nil }
        } message: {
            Text(recording.error ?? "")
        }
    }

    private var meetingTabPicker: some View {
        HStack(spacing: 2) {
            ForEach(MeetingTab.allCases, id: \.self) { tab in
                let selected = activeTab == tab
                Button {
                    activeTab = tab
                } label: {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(selected ? .primary : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.quaternary, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meeting views")
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
                    TextField("Meeting name", text: draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .focused($isFocused)
                        .disabled(isSaving)
                        .onKeyPress(.return) {
                            save()
                            return .handled
                        }
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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.background, in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(isFocused ? Color.accentColor : Color.secondary.opacity(0.3))
                                .allowsHitTesting(false)
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
            } else if origin == .header {
                name
                    .help(meeting.name + " — Double-click to rename")
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: begin)
                    .contextMenu { Button("Rename", action: begin) }
                    .accessibilityAction(named: Text("Rename"), begin)
            } else {
                name.help(meeting.name)
            }
        }
        .focusable(origin == .header && !isEditing)
        .focusedValue(\.renameMeeting, !isEditing && !isSaving ? begin : nil)
    }

    private var name: some View {
        Text(meeting.name)
            .lineLimit(origin == .sidebar ? 1 : 2)
            .truncationMode(.tail)
    }
}
