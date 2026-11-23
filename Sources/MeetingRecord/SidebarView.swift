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
    let rename: (UUID) -> Void
    let save: () -> Void
    let cancel: () -> Void
    let retry: () -> Void
    @FocusState private var focusedDestination: Destination?
    @State private var hasMoreMeetingsBelow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            navigationButton("Home", icon: "house", target: .home)
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
                        if let target { proxy.scrollTo(target) }
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
        .frame(width: 240)
        .frame(maxHeight: .infinity)
        .background(.background.secondary)
        .onAppear { focusedDestination = .home }
        .onMoveCommand { direction in
            guard editor == nil else { return }
            let meetings: [Meeting]
            if case .loaded(let values) = state { meetings = values } else { meetings = [] }
            let targets: [Destination] = [.home, .settings] + meetings.map { .meeting($0.id) }
            let index = targets.firstIndex(of: focusedDestination ?? .home) ?? 0
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
            Image(systemName: "text.bubble").accessibilityHidden(true)
            InlineMeetingName(meeting: meeting, origin: .sidebar, editor: $editor,
                              isSaving: isSaving, begin: { rename(meeting.id) }, save: save, cancel: cancel)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isRecording { RecordingIndicator() }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(destination == target ? Color.accentColor.opacity(0.16) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(focusedDestination == target && editor == nil ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture {
            if editor?.id != meeting.id {
                if editor == nil { focusedDestination = target }
                navigate(target)
            }
        }
        .focusable(editor == nil)
        .focused($focusedDestination, equals: target)
        .onKeyPress(.return) { guard editor == nil else { return .ignored }; navigate(target); return .handled }
        .onKeyPress(.space) { guard editor == nil else { return .ignored }; navigate(target); return .handled }
        .focusedValue(\.renameMeeting, editor == nil && !isSaving ? { rename(meeting.id) } : nil)
        .contextMenu { Button("Rename") { rename(meeting.id) } }
        .accessibilityElement(children: editor?.id == meeting.id ? .contain : .combine)
        .accessibilityLabel(editor?.id == meeting.id ? "" : meeting.name)
        .accessibilityValue(isRecording ? "Recording" : "")
        .accessibilityAddTraits(destination == target ? [.isSelected] : [])
        .accessibilityAction {
            if editor == nil { focusedDestination = target }
            navigate(target)
        }
        .accessibilityAction(named: Text("Rename")) { rename(meeting.id) }
        .onChange(of: editor == nil) { wasClosed, isClosed in
            if !wasClosed && isClosed && destination == target { focusedDestination = target }
        }
    }

    private func navigationButton(_ title: String, icon: String, target: Destination) -> some View {
        Button { navigate(target) } label: {
            Label(title, systemImage: icon)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(destination == target ? Color.accentColor.opacity(0.16) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(focusedDestination == target ? Color.accentColor : .clear, lineWidth: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focusedDestination, equals: target)
        .help(title)
        .accessibilityAddTraits(destination == target ? .isSelected : [])
    }
}
