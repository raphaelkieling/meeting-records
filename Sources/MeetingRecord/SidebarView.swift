import AppKit
import SwiftUI

struct SidebarView: View {
    let destination: Destination
    let state: MeetingLoadState
    @Binding var editor: RenameSession?
    let isSaving: Bool
    let canCreate: Bool
    let revealID: UUID?
    let revealVersion: Int
    let recordingMeetingID: UUID?
    let navigate: (Destination) -> Void
    let create: () -> Void
    let openSearch: () -> Void
    let rename: (UUID) -> Void
    let meetingActions: (Meeting) -> MeetingActions
    let save: () -> Void
    let cancel: () -> Void
    let retry: () -> Void
    private enum FocusTarget: Hashable { case destination(Destination), search }
    @FocusState private var focusedDestination: FocusTarget?
    @State private var hasMoreMeetingsBelow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            navigationButton("Home", icon: "house", target: .home)
            Button(action: openSearch) {
                HStack {
                    Label("Search", systemImage: "magnifyingglass")
                    Spacer()
                    Text("⌘K").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(focusedDestination == .search && editor == nil ? Color.primary.opacity(0.08) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable()
            .focused($focusedDestination, equals: .search)
            .onKeyPress(.return) { openSearch(); return .handled }
            .help("Search meetings, transcripts, tags, and commands")
            navigationButton("Chat", icon: "bubble.left.and.bubble.right", target: .chat)
            navigationButton("Labels", icon: "tag", target: .labels)
            navigationButton("Calendar", icon: "calendar", target: .calendar)
            navigationButton("Settings", icon: "gearshape", target: .settings)
            HStack {
                Text("Meetings").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(action: create) { Image(systemName: "plus").frame(width: 24, height: 24) }
                    .buttonStyle(.borderless)
                    .disabled(!canCreate)
                    .help("Add Meeting")
                    .accessibilityLabel("Add Meeting")
            }
            .padding(.top, 12).padding(.horizontal, 8)
            switch state {
            case .loading:
                ProgressView("Loading meetings…").controlSize(.small).padding(8)
                Spacer()
            case .failed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Could not load meetings").font(.callout)
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    Button("Try Again", action: retry)
                }.padding(8)
                Spacer()
            case .loaded(let meetings) where meetings.isEmpty:
                Text("No meetings yet").foregroundStyle(.secondary).padding(8)
                Spacer()
            case .loaded(let meetings):
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(meetings) { meeting in
                                meetingRow(meeting).id(Destination.meeting(meeting.id))
                            }
                        }
                        .padding(2)
                        .onGeometryChange(for: Bool.self) { geometry in
                            guard let viewport = geometry.bounds(of: .scrollView) else { return false }
                            return geometry.frame(in: .scrollView).maxY > viewport.height + 1
                        } action: { hasMoreMeetingsBelow = $0 }
                    }
                    .scrollIndicators(.never, axes: .vertical)
                    .mask {
                        VStack(spacing: 0) {
                            Rectangle()
                            if hasMoreMeetingsBelow {
                                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                                    .frame(height: 26)
                            }
                        }
                    }
                    .onChange(of: focusedDestination) { _, target in
                        if case .destination(let target) = target { proxy.scrollTo(target) }
                    }
                    .onChange(of: revealVersion) { _, _ in
                        if let revealID { proxy.scrollTo(Destination.meeting(revealID)) }
                    }
                    .onAppear {
                        if let revealID { proxy.scrollTo(Destination.meeting(revealID)) }
                    }
                }
            }
        }
        .padding(12)
        .padding(.top, 0)
        .frame(maxHeight: .infinity)
        .background(.background.secondary)
        .onAppear { focusedDestination = .destination(.home) }
        .onMoveCommand { direction in
            guard editor == nil else { return }
            let meetings: [Meeting]
            if case .loaded(let values) = state { meetings = values } else { meetings = [] }
            let targets: [FocusTarget] = [.destination(.home), .search, .destination(.chat),
                .destination(.labels), .destination(.calendar), .destination(.settings)] +
                meetings.map { .destination(.meeting($0.id)) }
            let index = targets.firstIndex(of: focusedDestination ?? .destination(.home)) ?? 0
            switch direction {
            case .down: focusedDestination = targets[min(index + 1, targets.count - 1)]
            case .up: focusedDestination = targets[max(index - 1, 0)]
            default: break
            }
        }
    }

    private func meetingRow(_ meeting: Meeting) -> some View {
        let target = Destination.meeting(meeting.id)
        let isRecording = recordingMeetingID == meeting.id
        return HStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .foregroundStyle(Color.meetingAccent)
                .accessibilityHidden(true)
            InlineMeetingName(meeting: meeting, origin: .sidebar, editor: $editor,
                              isSaving: isSaving, begin: { rename(meeting.id) }, save: save, cancel: cancel)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isRecording { RecordingIndicator() }
            if !meeting.tags.isEmpty {
                Image(systemName: "tag")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            if meeting.calendarEventDate != nil {
                Image(systemName: "calendar")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .help("Created from a calendar event")
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(rowBackground(for: target),
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            if editor?.id != meeting.id {
                if editor == nil { focusedDestination = .destination(target) }
                navigate(target)
            }
        }
        .focusable(editor == nil)
        .focused($focusedDestination, equals: .destination(target))
        .onKeyPress(.return) { guard editor == nil else { return .ignored }; navigate(target); return .handled }
        .onKeyPress(.space) { guard editor == nil else { return .ignored }; navigate(target); return .handled }
        .focusedValue(\.renameMeeting, editor == nil && !isSaving ? { rename(meeting.id) } : nil)
        .help(meeting.name)
        .contextMenu { meetingActions(meeting) }
        .accessibilityElement(children: editor?.id == meeting.id ? .contain : .combine)
        .accessibilityLabel(editor?.id == meeting.id ? "" : meeting.name)
        .accessibilityValue(accessibilityValue(for: meeting, isRecording: isRecording))
        .accessibilityAddTraits(destination == target ? [.isSelected] : [])
        .accessibilityAction {
            if editor == nil { focusedDestination = .destination(target) }
            navigate(target)
        }
        .accessibilityAction(named: Text("Rename")) { rename(meeting.id) }
        .accessibilityAction(named: Text("Edit Meeting")) { meetingActions(meeting).edit() }
        .accessibilityAction(named: Text("Copy Link as Markdown")) { meetingActions(meeting).copyLink() }
        .onChange(of: editor == nil) { wasClosed, isClosed in
            if !wasClosed && isClosed && destination == target { focusedDestination = .destination(target) }
        }
    }

    private func accessibilityValue(for meeting: Meeting, isRecording: Bool) -> String {
        var values: [String] = []
        if isRecording { values.append("Recording") }
        if !meeting.tags.isEmpty { values.append("Labels: \(meeting.tags.map(\.name).joined(separator: ", "))") }
        if meeting.calendarEventDate != nil { values.append("Calendar event attached") }
        return values.joined(separator: ", ")
    }

    private func navigationButton(_ title: String, icon: String, target: Destination) -> some View {
        Button { navigate(target) } label: {
            Label(title, systemImage: icon)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(rowBackground(for: target),
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focusedDestination, equals: .destination(target))
        .onKeyPress(.return) { navigate(target); return .handled }
        .help(title)
        .accessibilityAddTraits(isSelected(target) ? .isSelected : [])
    }

    private func isSelected(_ target: Destination) -> Bool {
        if case .label = destination { return target == .labels }
        return destination == target
    }

    private func rowBackground(for target: Destination) -> Color {
        if isSelected(target) { return Color.accentColor.opacity(0.16) }
        if focusedDestination == .destination(target) && editor == nil { return Color.primary.opacity(0.08) }
        return .clear
    }
}

struct SidebarSplitAutosave: NSViewRepresentable {
    func makeNSView(context: Context) -> SplitObserver { SplitObserver() }
    func updateNSView(_ view: SplitObserver, context: Context) {}

    final class SplitObserver: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                var ancestor = self?.superview
                while let view = ancestor {
                    if let split = view as? NSSplitView {
                        split.autosaveName = "MeetingRecord.MainSplit"
                        return
                    }
                    ancestor = view.superview
                }
            }
        }
    }
}
