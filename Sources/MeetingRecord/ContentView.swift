import SwiftUI

enum Destination: Hashable {
    case home, search, labels, settings, meeting(UUID)

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .search: "Search"
        case .labels: "Labels"
        case .settings: "Settings"
        case .meeting: "Meeting"
        }
    }
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
    case navigate(Destination), openRecent(UUID), openModelSettings, create, rename(UUID, RenameOrigin)
    case editTags(UUID), editDescription(UUID), delete(UUID)
}

private enum MeetingEditorSheet: Identifiable {
    case tags(Meeting), description(Meeting)

    var id: String {
        switch self {
        case .tags(let meeting): "tags-\(meeting.id.uuidString)"
        case .description(let meeting): "description-\(meeting.id.uuidString)"
        }
    }
}

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var homeRevision = 0
    @State private var recentMeetings: [Meeting]?
    @State private var homeError: String?
    @State private var recordedTime: TimeInterval?
    @State private var completedTranscriptions: Int?
    @State private var durationError: String?
    @State private var savedDurations: [UUID: TimeInterval] = [:]
    @State private var destination: Destination = .home
    @State private var linkedMeetingID: UUID?
    @State private var linkError: String?
    @State private var state: MeetingLoadState = .loading
    @State private var editor: RenameSession?
    @State private var isSaving = false
    @State private var pendingDeletion: Meeting?
    @State private var deletionError: String?
    @State private var mutationError: String?
    @State private var pendingAction: MeetingAction?
    @State private var creation: (id: UUID, name: String)?
    @State private var revealID: UUID?
    @State private var revealVersion = 0
    @ObservedObject var recording: RecordingCoordinator
    @ObservedObject var transcription: TranscriptionCoordinator
    @State private var revealLatestRecording = false
    @State private var activeTab = MeetingTab.transcription
    @State private var settingsSection: SettingsSection?
    @State private var meetingEditor: MeetingEditorSheet?
    private var store: MeetingStore { recording.store }

    private struct HomeLoadKey: Equatable {
        let meetings: Int
        let recordings: Int
        let transcriptions: Int
    }

    private var homeLoadKey: HomeLoadKey {
        HomeLoadKey(meetings: homeRevision, recordings: recording.revision,
                    transcriptions: transcription.completionRevision)
    }

    private enum MeetingTab: String, CaseIterable {
        case inputs = "Inputs"
        case transcription = "Transcription"
        case summary = "Summary"

        var icon: String {
            switch self {
            case .inputs: "tray"
            case .transcription: "text.bubble"
            case .summary: "sparkles"
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
                rename: { request(.rename($0, .sidebar)) },
                editTags: { request(.editTags($0)) },
                editDescription: { request(.editDescription($0)) },
                canDelete: { !isSaving && recording.canDelete($0) },
                delete: { request(.delete($0)) },
                save: saveRename, cancel: cancelRename,
                retry: { Task { await loadMeetings() } }
            )
            Divider().ignoresSafeArea(.container, edges: .top)
            VStack(alignment: .leading, spacing: 20) {
                if let meeting = selectedMeeting {
                    VStack(alignment: .leading, spacing: 6) {
                        InlineMeetingName(meeting: meeting, origin: .header, editor: $editor,
                                          isSaving: isSaving, begin: { request(.rename(meeting.id, .header)) },
                                          save: saveRename, cancel: cancelRename)
                            .font(.largeTitle.bold())
                        meetingMetadata(meeting)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        meetingTabPicker
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 12)
                        Group {
                            switch activeTab {
                            case .inputs:
                                InputsView(meetingID: meeting.id, store: store, revision: recording.revision,
                                           transcription: transcription, revealLatest: revealLatestRecording,
                                           openSettings: { request(.openModelSettings) })
                                    .id(meeting.id)
                            case .transcription:
                                TranscriptionView(meetingID: meeting.id, store: store,
                                                  recordingRevision: recording.revision, transcription: transcription)
                                    .id(meeting.id)
                            case .summary:
                                MeetingSummaryView(meetingID: meeting.id, store: store,
                                                   recordingRevision: recording.revision,
                                                   transcriptionRevision: transcription.revision,
                                                   isRecording: recording.state.meetingID == meeting.id,
                                                   summaries: recording.summaries)
                                    .id(meeting.id)
                            }
                        }
                        .id(activeTab)
                        .transition(.opacity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .onTapGesture { if editor != nil { saveRename() } }
                    .overlay(alignment: .bottom) {
                        RecordingControl(state: recording.state, meetingID: meeting.id, levels: recording.levels,
                                         modelReady: transcription.isReady,
                                         openSettings: { request(.openModelSettings) }) {
                            recording.toggle(for: meeting.id)
                        }
                        .padding(.bottom, 12)
                    }
                } else {
                    Text(destination.title)
                        .font(.largeTitle.bold())
                    if destination == .settings {
                        SettingsView(section: $settingsSection, transcription: transcription, recording: recording,
                                     deleteAll: deleteAllMeetingData)
                    } else if destination == .search {
                        SearchView(store: store,
                                   refreshKey: "\(homeRevision)-\(recording.revision)-\(transcription.revision)",
                                   openMeeting: { request(.navigate(.meeting($0))) })
                    } else if destination == .labels {
                        LabelsView(store: store, onChange: reloadMeetingLabels)
                    } else {
                        HomeView(meetings: recentMeetings, error: homeError,
                                 recordedTime: recordedTime, completedTranscriptions: completedTranscriptions,
                                 durationError: durationError,
                                 open: { request(.openRecent($0)) },
                                 retry: { homeRevision += 1 })
                            .task(id: homeLoadKey) { [key = homeLoadKey] in await loadHome(for: key) }
                    }
                    Spacer()
                }
                if let cleanupError = recording.cleanupError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Meeting files are pending deletion. \(cleanupError)")
                            .foregroundStyle(.red)
                        Button("Retry File Cleanup") {
                            Task { await recording.finishMeetingDeletions() }
                        }
                    }
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
        .task { await loadMeetings() }
        .task { await recording.recover() }
        .task { await recording.finishMeetingDeletions() }
        .onOpenURL { url in
            linkedMeetingID = MeetingLink.meetingID(from: url)
            linkError = linkedMeetingID == nil ? "This meeting link is invalid." : nil
        }
        .task(id: linkedMeetingID) {
            guard let id = linkedMeetingID else { return }
            if !meetings.contains(where: { $0.id == id }) { await loadMeetings() }
            guard !Task.isCancelled else { return }
            linkedMeetingID = nil
            if meetings.contains(where: { $0.id == id }) {
                request(.navigate(.meeting(id)))
            } else if case .failed(let message) = state {
                linkError = message
            } else {
                linkError = "This meeting is not in your local library."
            }
        }
        .alert("Could Not Open Meeting Link", isPresented: Binding(get: { linkError != nil },
                                                                   set: { if !$0 { linkError = nil } })) {
            Button("OK") { linkError = nil }
        } message: {
            Text(linkError ?? "")
        }
        .alert("Recording", isPresented: Binding(get: { recording.error != nil },
                                                 set: { if !$0 { recording.error = nil } })) {
            Button("OK") { recording.error = nil }
        } message: {
            Text(recording.error ?? "")
        }
        .alert("Delete Meeting?", isPresented: Binding(get: { pendingDeletion != nil },
                                                      set: { if !$0 { pendingDeletion = nil } }),
               presenting: pendingDeletion) { meeting in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteMeeting(meeting.id) }
        } message: { meeting in
            Text("Permanently delete “\(meeting.name)” and all its recordings, transcripts, and other attached content?")
        }
        .alert("Could Not Delete Meeting", isPresented: Binding(get: { deletionError != nil },
                                                               set: { if !$0 { deletionError = nil } })) {
            Button("OK") { deletionError = nil }
        } message: {
            Text(deletionError ?? "")
        }
        .sheet(item: $meetingEditor) { sheet in
            switch sheet {
            case .tags(let meeting):
                TagManagementView(meeting: meeting, store: store, onSave: reloadMeetingLabels)
            case .description(let meeting):
                MeetingDescriptionEditorView(meeting: meeting, store: store) { updated in merge(updated) }
            }
        }
    }

    private func meetingMetadata(_ meeting: Meeting) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let description = meeting.description {
                Button { request(.editDescription(meeting.id)) } label: {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .help("Edit Description")
                .accessibilityHint("Opens the full description for editing")
            } else {
                Button("Add a description…") { request(.editDescription(meeting.id)) }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if !meeting.tags.isEmpty {
                ViewThatFits(in: .horizontal) {
                    meetingLabelPills(meeting.tags)
                    ScrollView(.horizontal) {
                        meetingLabelPills(meeting.tags)
                    }
                    .scrollIndicators(.never)
                }
                .frame(maxWidth: 240, alignment: .trailing)
            }
        }
    }

    private func meetingLabelPills(_ tags: [Tag]) -> some View {
        HStack(spacing: 5) {
            ForEach(tags) { TagPill(tag: $0).lineLimit(1) }
        }
    }

    private var meetingTabPicker: some View {
        HStack(spacing: 2) {
            ForEach(MeetingTab.allCases, id: \.self) { tab in
                let selected = activeTab == tab
                let highlighted = selected && tab == .transcription
                Button {
                    if tab != .inputs { revealLatestRecording = false }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.06)) {
                        activeTab = tab
                    }
                } label: {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(highlighted ? Color.white : selected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(highlighted ? Color.meetingAccent : Color(nsColor: .controlBackgroundColor))
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
        case .navigate(let target):
            if case .meeting(let id) = target {
                openMeeting(id)
            } else {
                revealLatestRecording = false
                if target == .settings { settingsSection = nil }
                destination = target
            }
        case .openRecent(let id):
            if !meetings.contains(where: { $0.id == id }) {
                Task {
                    await loadMeetings()
                    if destination == .home && meetings.contains(where: { $0.id == id }) {
                        request(.openRecent(id))
                    }
                }
                return
            }
            openMeeting(id, revealLatest: true)
        case .openModelSettings:
            revealLatestRecording = false
            settingsSection = .models
            destination = .settings
        case .editTags(let id):
            if let meeting = meetings.first(where: { $0.id == id }) { meetingEditor = .tags(meeting) }
        case .editDescription(let id):
            if let meeting = meetings.first(where: { $0.id == id }) { meetingEditor = .description(meeting) }
        case .create: createMeeting()
        case .rename(let id, let origin):
            guard !recording.isDeleting(id),
                  let meeting = meetings.first(where: { $0.id == id }) else { return }
            if destination != .meeting(id) { openMeeting(id) }
            editor = RenameSession(id: id, origin: origin, draft: meeting.name)
        case .delete(let id):
            guard recording.canDelete(id) else { return }
            pendingDeletion = meetings.first(where: { $0.id == id })
        }
    }

    private func openMeeting(_ id: UUID, revealLatest: Bool = false) {
        revealLatestRecording = revealLatest
        activeTab = .transcription
        destination = .meeting(id)
    }

    private func deleteMeeting(_ id: UUID) {
        Task {
            do {
                try await recording.deleteMeeting(id)
            } catch {
                deletionError = error.localizedDescription
                return
            }
            if editor?.id == id {
                editor = nil
                pendingAction = nil
            }
            if destination == .meeting(id) {
                revealLatestRecording = false
                destination = .home
            }
            if revealID == id { revealID = nil }
            state = .loaded(meetings.filter { $0.id != id })
            homeRevision += 1
            await recording.finishMeetingDeletions()
        }
    }

    private func deleteAllMeetingData() {
        Task {
            do {
                try await recording.deleteAllMeetings()
                editor = nil
                pendingAction = nil
                revealID = nil
                state = .loaded([])
                homeRevision += 1
                await recording.finishMeetingDeletions()
            } catch {
                recording.error = "Could not delete all meeting data. \(error.localizedDescription)"
            }
        }
    }

    private func merge(_ meeting: Meeting) {
        state = .loaded((meetings.filter { $0.id != meeting.id } + [meeting]).sorted(by: Meeting.mostRecentFirst))
        revealID = meeting.id
        revealVersion += 1
        homeRevision += 1
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
                openMeeting(meeting.id)
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

    private func loadHome(for key: HomeLoadKey) async {
        let summary: MeetingStore.HomeSummary
        do {
            summary = try await store.loadHomeSummary()
        } catch {
            guard !Task.isCancelled, key == homeLoadKey else { return }
            homeError = error.localizedDescription
            return
        }
        guard !Task.isCancelled, key == homeLoadKey else { return }
        recentMeetings = summary.meetings
        completedTranscriptions = summary.completedTranscriptions
        homeError = nil
        let savedIDs = Set(summary.savedRecordingIDs)
        savedDurations = savedDurations.filter { savedIDs.contains($0.key) }

        do {
            let root = try await store.recordingRoot()
            var total: TimeInterval = 0
            for id in summary.savedRecordingIDs {
                if let duration = savedDurations[id] {
                    total += duration
                } else {
                    let segments = try await store.audioSegments(for: id)
                    let duration = try await RecordingPlayback.savedDuration(segments: segments, root: root)
                    guard !Task.isCancelled, key == homeLoadKey else { return }
                    savedDurations[id] = duration
                    total += duration
                }
            }
            guard !Task.isCancelled, key == homeLoadKey else { return }
            recordedTime = total
            durationError = nil
        } catch {
            guard !Task.isCancelled, key == homeLoadKey else { return }
            recordedTime = nil
            durationError = error.localizedDescription
        }
    }

    private func reloadMeetingLabels() {
        homeRevision += 1
        Task { await loadMeetings() }
    }

    private func loadMeetings() async {
        let revision = homeRevision
        if case .failed = state { state = .loading }
        do {
            let values = try await store.loadMeetings()
            guard !Task.isCancelled, revision == homeRevision else { return }
            state = .loaded(values)
        } catch {
            guard !Task.isCancelled, revision == homeRevision else { return }
            if case .loaded = state { return }
            state = .failed(error.localizedDescription)
        }
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
