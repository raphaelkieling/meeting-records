import AppKit
import SwiftUI

enum Destination: Hashable {
    case home, chat, labels, calendar, settings, meeting(UUID), label(Tag)

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .chat: "Chat"
        case .labels: "Labels"
        case .label(let tag): "\(tag.name)"
        case .calendar: "Calendar"
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
    case edit(UUID), delete(UUID), showCommandPalette, recordNew
}

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchIndexRevision = 0
    @State private var homeRevision = 0
    @State private var recentMeetings: [Meeting]?
    @State private var homeError: String?
    @State private var recordedTime: TimeInterval?
    @State private var completedTranscriptions: Int?
    @State private var durationError: String?
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
    @State private var recordAfterCreating = false
    @State private var creation: (id: UUID, name: String)?
    @State private var revealID: UUID?
    @State private var revealVersion = 0
    @ObservedObject var recording: RecordingCoordinator
    @ObservedObject var transcription: TranscriptionCoordinator
    @State private var revealLatestRecording = false
    @State private var activeTab = MeetingTab.transcription
    @State private var settingsSection: SettingsSection?
    @State private var meetingEditor: Meeting?
    @State private var calendarFocusDate: Date?
    @State private var isCommandPalettePresented = false
    @State private var citedPassageID: String?
    @State private var citationReplyID: UUID?
    @State private var citationNavigationRevision = 0
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
        HSplitView {
            SidebarView(
                destination: destination, state: state, editor: $editor, isSaving: isSaving,
                canCreate: canCreate, revealID: revealID, revealVersion: revealVersion,
                recordingMeetingID: recordingMeetingID,
                navigate: { request(.navigate($0)) }, create: { request(.create) },
                openSearch: { request(.showCommandPalette) },
                rename: { request(.rename($0, .sidebar)) },
                meetingActions: meetingActions,
                save: saveRename, cancel: cancelRename,
                retry: { Task { await loadMeetings() } }
            )
            .frame(minWidth: 240, maxWidth: 440)
            .background(SidebarSplitAutosave())
            .layoutPriority(-1)
            VStack(alignment: .leading, spacing: 20) {
                if let meeting = selectedMeeting {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            InlineMeetingName(meeting: meeting, origin: .header, editor: $editor,
                                              isSaving: isSaving, begin: { request(.rename(meeting.id, .header)) },
                                              save: saveRename, cancel: cancelRename)
                                .font(.largeTitle.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .contextMenu { meetingActions(meeting) }

                            Menu { meetingActions(meeting) } label: {
                                Image(systemName: "ellipsis")
                                    .font(.body.weight(.semibold))
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .help("Meeting actions")
                            .accessibilityLabel("Meeting actions")
                        }
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
                                           calendarEventDate: meeting.calendarEventDate, calendarName: meeting.calendarName,
                                           transcription: transcription, revealLatest: revealLatestRecording,
                                           openSettings: { request(.openModelSettings) },
                                           openCalendar: { date in calendarFocusDate = date; destination = .calendar },
                                           deleteScreenCapture: recording.deleteScreenCapture,
                                           deleteRecording: recording.deleteRecording,
                                           removeCalendarLink: { try await removeCalendarLink(from: meeting.id) })
                                    .id(meeting.id)
                            case .transcription:
                                TranscriptionView(meetingID: meeting.id, store: store,
                                                  recordingRevision: recording.revision, transcription: transcription,
                                                  citedPassageID: citedPassageID,
                                                  citedPassageRevision: citationNavigationRevision,
                                                  returnToChat: citationReplyID == nil ? nil : { request(.navigate(.chat)) })
                                    .id(meeting.id)
                            case .summary:
                                MeetingSummaryView(meetingID: meeting.id, store: store,
                                                   meetingUpdatedAt: meeting.updatedAt,
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
                                         openSettings: { request(.openModelSettings) },
                                         captureScreen: recording.takeScreenCapture) {
                            recording.toggle(for: meeting.id)
                        }
                        .padding(.bottom, 12)
                    }
                } else {
                    Text(destination.title)
                        .font(.largeTitle.bold())
                    if destination == .chat {
                        MeetingChatView(chat: recording.chat, meetings: meetings,
                                        openAISettings: { settingsSection = .ai; destination = .settings },
                                        returnToMessage: citationReplyID,
                                        openCitation: openChatCitation,
                                        store: store, recordingRevision: recording.revision)
                    } else if destination == .settings {
                        SettingsView(section: $settingsSection, transcription: transcription, recording: recording,
                                     deleteAll: deleteAllMeetingData)
                    } else if case .label(let tag) = destination {
                        meetingsWithLabel(tag)
                    } else if destination == .labels {
                        LabelsView(store: store, onChange: reloadMeetingLabels)
                    } else if destination == .calendar {
                        CalendarView(initialDate: calendarFocusDate, createMeeting: createMeetingFromCalendar)
                    } else {
                        HomeView(meetings: recentMeetings, error: homeError,
                                 recordedTime: recordedTime, completedTranscriptions: completedTranscriptions,
                                 durationError: durationError,
                                 open: { request(.openRecent($0)) },
                                 retry: { homeRevision += 1 }, canRecord: canCreate && recording.state == .idle,
                                 record: { request(.recordNew) },
                                 openCalendar: { date in
                                     calendarFocusDate = date
                                     request(.navigate(.calendar))
                                 }, canCreateMeeting: canCreate,
                                 createMeeting: createMeetingFromCalendar)
                            .task(id: homeLoadKey) { [key = homeLoadKey] in await loadHome(for: key) }
                    }
                    if destination != .chat { Spacer() }
                }
                if let cleanupError = recording.cleanupError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Could not remove audio files. \(cleanupError)")
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
            .frame(minWidth: 470, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .task { await loadMeetings() }
        .task { await recording.recover() }
        .task(id: transcription.completionRevision, priority: .utility) {
            do {
                try await MeetingChatRetrieval.refresh(store)
                if !Task.isCancelled { searchIndexRevision &+= 1 }
            } catch {}
        }
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
        .alert("Screen Capture", isPresented: Binding(get: { recording.screenCaptureError != nil },
                                                      set: { if !$0 { recording.screenCaptureError = nil } })) {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("OK", role: .cancel) { recording.screenCaptureError = nil }
        } message: {
            Text(recording.screenCaptureError ?? "")
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
        .sheet(item: $meetingEditor) { meeting in
            MeetingEditorView(meeting: meeting, store: store, onSave: merge)
        }
        .disabled(isCommandPalettePresented)
        .accessibilityHidden(isCommandPalettePresented)
        .overlay {
            if isCommandPalettePresented {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .onTapGesture { isCommandPalettePresented = false }
                        .accessibilityHidden(true)

                    CommandPaletteView(meetings: meetings, store: store, indexRevision: searchIndexRevision,
                                       commands: paletteCommands, activate: activatePaletteItem,
                                       startChat: startChatFromSearch, dismiss: { isCommandPalettePresented = false })
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(nsColor: .textBackgroundColor))
                                .onTapGesture {}
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
                        .padding(.top, 24)
                }
            }
        }
        .focusedSceneValue(\.openCommandPalette, { request(.showCommandPalette) })
    }

    private var paletteCommands: [PaletteCommand] {
        [
            PaletteCommand(title: "Open Settings", icon: "gearshape", keywords: ["preferences"]) {
                request(.navigate(.settings))
            },
            PaletteCommand(title: "Go to Home", icon: "house", keywords: []) {
                request(.navigate(.home))
            },
            PaletteCommand(title: "Open Labels", icon: "tag", keywords: ["tags"]) {
                request(.navigate(.labels))
            },
            PaletteCommand(title: "Open Calendar", icon: "calendar", keywords: []) {
                request(.navigate(.calendar))
            },
            PaletteCommand(title: "New Meeting", icon: "plus", keywords: ["create", "add"]) {
                request(.create)
            },
        ]
    }

    private func activatePaletteItem(_ item: PaletteItem) {
        isCommandPalettePresented = false
        switch item {
        case .meeting(let meeting): request(.navigate(.meeting(meeting.id)))
        case .tag(let tag): request(.navigate(.label(tag)))
        case .transcript(let hit):
            Task {
                if !(await openPassage(hit.citation)) {
                    linkError = "This transcript passage is no longer available."
                }
            }
        case .command(let command): command.run()
        }
    }

    private func startChatFromSearch(_ question: String) {
        recording.chat.startChat(with: question)
        request(.navigate(.chat))
    }

    private func meetingsWithLabel(_ tag: Tag) -> some View {
        let taggedMeetings = meetings.filter { $0.tags.contains { $0.id == tag.id } }
        return Group {
            if taggedMeetings.isEmpty {
                MeetingEmptyState("No Meetings With This Label", icon: "tag",
                                  detail: "Meetings with this label will appear here.")
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(taggedMeetings) { meeting in
                            Button {
                                request(.navigate(.meeting(meeting.id)))
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "text.bubble")
                                        .foregroundStyle(Color.meetingAccent)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(meeting.name)
                                        if let description = meeting.description {
                                            Text(description).font(.callout).foregroundStyle(.secondary)
                                        }
                                    }
                                    .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .accessibilityHidden(true)
                                }
                                .padding(10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func meetingActions(_ meeting: Meeting) -> MeetingActions {
        MeetingActions(meeting: meeting, canEdit: !isSaving && !recording.isDeleting(meeting.id),
                       canDelete: !isSaving && recording.canDelete(meeting.id),
                       openChat: { openChat(for: meeting.id) },
                       edit: { request(.edit(meeting.id)) }, delete: { request(.delete(meeting.id)) })
    }

    private func openChat(for meetingID: UUID) {
        recording.chat.startNewChat(for: meetingID)
        request(.navigate(.chat))
    }

    private func meetingMetadata(_ meeting: Meeting) -> some View {
        HStack(spacing: 12) {
            Text(meeting.description ?? "No description")
                .font(.callout)
                .foregroundStyle(meeting.description == nil ? .tertiary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

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
        .frame(height: 22)
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
        case .showCommandPalette:
            if meetingEditor == nil && pendingDeletion == nil { isCommandPalettePresented = true }
        case .edit(let id):
            guard !recording.isDeleting(id) else { return }
            meetingEditor = meetings.first { $0.id == id }
        case .create: createMeeting()
        case .recordNew: createMeeting(recordImmediately: true)
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
        citedPassageID = nil
        citationReplyID = nil
        revealLatestRecording = revealLatest
        activeTab = .transcription
        destination = .meeting(id)
    }

    private func openChatCitation(_ citation: ChatCitation, replyID: UUID) async -> Bool {
        if citation.screenCaptureID != nil {
            guard let url = try? await store.screenCaptureURL(for: citation) else { return false }
            return NSWorkspace.shared.open(url)
        }
        return await openPassage(citation, replyID: replyID)
    }

    private func openPassage(_ citation: ChatCitation, replyID: UUID? = nil) async -> Bool {
        guard (try? await store.isChatCitationCurrent(citation)) == true,
              let passage = citation.passageIDs.first else { return false }
        revealLatestRecording = false
        activeTab = .transcription
        destination = .meeting(citation.meetingID)
        citedPassageID = passage
        citationReplyID = replyID
        citationNavigationRevision &+= 1
        return true
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

    private func removeCalendarLink(from meetingID: UUID) async throws {
        let updated = try await store.removeCalendarLink(from: meetingID)
        recording.summaries.cancel(for: meetingID)
        state = .loaded(meetings.map { $0.id == meetingID ? updated : $0 }.sorted(by: Meeting.mostRecentFirst))
        homeRevision += 1
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

    private func createMeeting(recordImmediately: Bool = false) {
        guard canCreate else { return }
        if creation == nil {
            recordAfterCreating = recordImmediately
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
                if recordAfterCreating, recording.state == .idle { recording.toggle(for: meeting.id) }
                recordAfterCreating = false
            } catch { mutationError = error.localizedDescription }
            isSaving = false
        }
    }

    private func createMeetingFromCalendar(details: CalendarEventDetails, calendarDate: Date, calendarName: String) {
        guard canCreate else { return }
        isSaving = true
        mutationError = nil
        Task {
            do {
                let meeting = try await store.createMeeting(id: UUID(), name: details.title, description: details.notes,
                                                            calendarEventDate: calendarDate, calendarName: calendarName,
                                                            calendarDetails: details)
                merge(meeting)
                openMeeting(meeting.id)
                destination = .meeting(meeting.id)
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
        recordedTime = summary.recordedTime
        durationError = nil
        guard !summary.missingDurationIDs.isEmpty else { return }
        do {
            let root = try await store.recordingRoot()
            var total = summary.recordedTime
            for id in summary.missingDurationIDs {
                try Task.checkCancellation()
                let segments = try await store.audioSegments(for: id)
                do {
                    let duration = segments.isEmpty ? 0 : try await RecordingPlayback.savedDuration(segments: segments, root: root)
                    try Task.checkCancellation()
                    try await store.saveRecordingDuration(duration, for: id)
                    total += duration
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled, key == homeLoadKey else { return }
                    durationError = "Some saved audio is unavailable. The total excludes those recordings."
                }
            }
            guard !Task.isCancelled, key == homeLoadKey else { return }
            recordedTime = total
        } catch {
            guard !Task.isCancelled, key == homeLoadKey else { return }
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
                        .lineLimit(origin == .header ? 1 : nil)
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
                        .padding(.vertical, origin == .header ? 0 : 4)
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
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
