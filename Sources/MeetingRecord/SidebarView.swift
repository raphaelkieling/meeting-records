import AppKit
import SwiftUI

struct SidebarView: View {
    let store: MeetingStore
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
    private enum FocusTarget: Hashable { case destination(Destination), folder(UUID), search }
    private enum DropPosition: Equatable {
        case row(UUID, SidebarDropArea)
        case rootEnd
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedFolderName: UUID?
    @State private var sidebarItems: [SidebarItem] = []
    @State private var sidebarRequest = UUID()
    @State private var changingSidebar = false
    @State private var pendingLayoutWrite: Task<Void, Never>?
    @State private var folderBeingRenamed: UUID?
    @State private var folderName = ""
    @State private var sidebarError: String?
    @State private var dropPosition: DropPosition?
    @State private var draggedItemID: UUID?
    @State private var invalidDropTargets: Set<UUID> = []
    @State private var dropFrames: [SidebarDropRow: CGRect] = [:]
    @State private var sidebarViewport = CGSize.zero
    @State private var dragScrollDirection = 0
    @State private var dragPointer = DragPointer()

    private final class DragPointer {
        var location = CGPoint.zero
    }

    private var meetings: [Meeting] {
        if case .loaded(let values) = state { values } else { [] }
    }

    private var visibleItems: [(item: SidebarItem, depth: Int)] {
        let groups = Dictionary(grouping: sidebarItems, by: \.parentID)
        var stack = (groups[nil] ?? []).reversed().map { (item: $0, depth: 0) }
        var result: [(item: SidebarItem, depth: Int)] = []
        while let row = stack.popLast() {
            result.append(row)
            if row.item.folder?.expanded == true {
                stack.append(contentsOf: (groups[row.item.id] ?? []).reversed().map {
                    (item: $0, depth: row.depth + 1)
                })
            }
        }
        return result
    }
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
                Button(action: createFolder) { Image(systemName: "folder.badge.plus").frame(width: 24, height: 24) }
                    .buttonStyle(.borderless)
                    .disabled(!canCreate || changingSidebar || folderBeingRenamed != nil)
                    .help("Add Folder")
                    .accessibilityLabel("Add Folder")
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
            case .loaded(let meetings):
                let meetingByID = Dictionary(uniqueKeysWithValues: meetings.map { ($0.id, $0) })
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if let sidebarError {
                                Text(sidebarError).font(.caption).foregroundStyle(.red).padding(8)
                            }
                            if sidebarItems.isEmpty, meetings.isEmpty {
                                Text("No meetings yet").foregroundStyle(.secondary).padding(8)
                            }
                            ForEach(visibleItems, id: \.item.id) { row in
                                let item = row.item
                                if item.folder != nil || meetingByID[item.id] != nil {
                                    Group {
                                        if let folder = item.folder {
                                            folderRow(item, folder: folder)
                                        } else if let meeting = meetingByID[item.id] {
                                            meetingRow(meeting).id(Destination.meeting(meeting.id))
                                        }
                                    }
                                    .padding(.leading, indentation(for: row.depth))
                                    .padding(.vertical, 2)
                                    .overlay(alignment: .top) {
                                        insertionLine(at: .row(item.id, .before), depth: row.depth)
                                    }
                                    .overlay(alignment: .bottom) {
                                        insertionLine(at: .row(item.id, .after), depth: row.depth)
                                    }
                                    .opacity(draggedItemID == item.id ? 0.45 : 1)
                                    .sidebarDropFrame(.item(item.id))
                                    .id(item.id)
                                }
                            }
                            if !sidebarItems.isEmpty {
                                Rectangle().fill(.clear).frame(height: 36)
                                    .overlay(alignment: .top) { insertionLine(at: .rootEnd, depth: 0) }
                                    .sidebarDropFrame(.rootEnd)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(2)
                        .onGeometryChange(for: Bool.self) { geometry in
                            guard let viewport = geometry.bounds(of: .scrollView) else { return false }
                            return geometry.frame(in: .scrollView).maxY > viewport.height + 1
                        } action: { hasMoreMeetingsBelow = $0 }
                    }
                    .scrollIndicators(.never, axes: .vertical)
                    .coordinateSpace(name: SidebarDropFrames.coordinateSpace)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { sidebarViewport = $0 }
                    .onPreferenceChange(SidebarDropFrames.self) { frames in
                        dropFrames = frames
                        if draggedItemID != nil { updateDropPosition(at: dragPointer.location) }
                    }
                    .simultaneousGesture(sidebarDrag)
                    .onExitCommand { if draggedItemID != nil { finishDrag() } }
                    .task(id: dragScrollDirection) {
                        let direction = dragScrollDirection
                        guard direction != 0 else { return }
                        while !Task.isCancelled, draggedItemID != nil {
                            if let id = nextScrollItem(in: direction) {
                                proxy.scrollTo(id, anchor: direction < 0 ? .top : .bottom)
                            }
                            do { try await Task.sleep(for: .milliseconds(130)) }
                            catch { return }
                        }
                    }
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
                        switch target {
                        case .destination(let target): proxy.scrollTo(target)
                        case .folder(let id): proxy.scrollTo(id)
                        default: break
                        }
                    }
                    .onChange(of: revealVersion) { _, _ in
                        if let revealID { proxy.scrollTo(Destination.meeting(revealID)) }
                    }
                    .onAppear {
                        if let revealID { proxy.scrollTo(Destination.meeting(revealID)) }
                    }
                    .task(id: folderBeingRenamed) {
                        guard let id = folderBeingRenamed else { return }
                        proxy.scrollTo(id)
                        await Task.yield()
                        if !Task.isCancelled { focusedFolderName = id }
                    }
                }
            }
        }
        .padding(12)
        .padding(.top, 0)
        .frame(maxHeight: .infinity)
        .background(.background.secondary)
        .task(id: Set(meetings.map(\.id))) { await refreshSidebar() }
        .onChange(of: focusedFolderName) { previous, next in
            if let previous, next == nil, folderBeingRenamed == previous { saveFolderName() }
        }
        .onAppear { focusedDestination = .destination(.home) }
        .onMoveCommand { direction in
            guard editor == nil, folderBeingRenamed == nil else { return }
            let meetingIDs = Set(meetings.map(\.id))
            let targets: [FocusTarget] = [.destination(.home), .search, .destination(.chat),
                .destination(.labels), .destination(.calendar), .destination(.settings)] +
                visibleItems.compactMap { row -> FocusTarget? in
                    if row.item.folder != nil { return .folder(row.item.id) }
                    return meetingIDs.contains(row.item.id) ? .destination(.meeting(row.item.id)) : nil
                }
            let index = targets.firstIndex(of: focusedDestination ?? .destination(.home)) ?? 0
            switch direction {
            case .down: focusedDestination = targets[min(index + 1, targets.count - 1)]
            case .up: focusedDestination = targets[max(index - 1, 0)]
            default: break
            }
        }
    }

    private func indentation(for depth: Int) -> CGFloat { CGFloat(min(depth, 8)) * 12 }

    private func refreshSidebar() async {
        guard pendingLayoutWrite == nil else { return }
        let request = UUID()
        sidebarRequest = request
        do {
            let items = try await store.sidebarItems()
            guard !Task.isCancelled, sidebarRequest == request else { return }
            if Dictionary(grouping: sidebarItems, by: \.parentID) != Dictionary(grouping: items, by: \.parentID) {
                withAnimation(layoutAnimation) { sidebarItems = items }
            }
        } catch {
            if !Task.isCancelled, sidebarRequest == request { sidebarError = error.localizedDescription }
        }
    }

    private func changeSidebar(_ operation: @escaping () async throws -> Void, then: (() -> Void)? = nil) {
        guard !changingSidebar else { return }
        let previous = pendingLayoutWrite
        changingSidebar = true
        Task {
            defer { changingSidebar = false }
            await previous?.value
            sidebarError = nil
            do {
                try await operation()
                await refreshSidebar()
                then?()
            } catch {
                sidebarError = error.localizedDescription
            }
        }
    }

    private var layoutAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.12)
    }

    private func applyLayout(_ items: [SidebarItem], save: @escaping () async throws -> Void) {
        let previous = pendingLayoutWrite
        let request = UUID()
        sidebarRequest = request
        if previous == nil { sidebarError = nil }
        withAnimation(layoutAnimation) {
            sidebarItems = items
            dropPosition = nil
        }
        pendingLayoutWrite = Task {
            await previous?.value
            do { try await save() }
            catch { sidebarError = error.localizedDescription }
            guard sidebarRequest == request else { return }
            pendingLayoutWrite = nil
            await refreshSidebar()
        }
    }

    private func toggleFolder(_ id: UUID) {
        guard !changingSidebar, let index = sidebarItems.firstIndex(where: { $0.id == id }),
              let folder = sidebarItems[index].folder else { return }
        let expanded = !folder.expanded
        var items = sidebarItems
        items[index].folder?.expanded = expanded
        applyLayout(items) { try await store.setSidebarFolderExpanded(id, expanded: expanded) }
    }

    private func createFolder() {
        let id = UUID()
        changeSidebar({ try await store.createSidebarFolder(id) }) {
            beginFolderRename(id, name: "New Folder")
        }
    }

    private func beginFolderRename(_ id: UUID, name: String) {
        folderName = name
        folderBeingRenamed = id
    }

    private func saveFolderName() {
        guard let id = folderBeingRenamed else { return }
        let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        folderBeingRenamed = nil
        if !name.isEmpty { changeSidebar { try await store.renameSidebarFolder(id, name: name) } }
    }

    private func folderRow(_ item: SidebarItem, folder: SidebarItem.Folder) -> some View {
        let color = folder.color?.folderColor ?? .primary
        let icon = "folder.fill"
        let target = FocusTarget.folder(item.id)
        return Group {
            if folderBeingRenamed == item.id {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundStyle(color).accessibilityHidden(true)
                    TextField("Folder Name", text: $folderName)
                        .focused($focusedFolderName, equals: item.id)
                        .onSubmit(saveFolderName)
                        .onExitCommand { folderBeingRenamed = nil }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
            } else {
                Button {
                    toggleFolder(item.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(folder.expanded ? 90 : 0))
                            .font(.caption2).frame(width: 10).foregroundStyle(.secondary).accessibilityHidden(true)
                        Image(systemName: icon).foregroundStyle(color).accessibilityHidden(true)
                        Text(folder.name).lineLimit(1).foregroundStyle(color)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .background(dropPosition == .row(item.id, .inside) ? Color.accentColor.opacity(0.23)
                                : focusedDestination == target ? Color.primary.opacity(0.08) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .focusable()
                .focused($focusedDestination, equals: target)
                .onKeyPress(.return) {
                    toggleFolder(item.id)
                    return .handled
                }
                .accessibilityValue(folder.expanded ? "Expanded" : "Collapsed")
                .contextMenu {
                    Button("Rename Folder", systemImage: "pencil") { beginFolderRename(item.id, name: folder.name) }
                    Menu("Folder Color", systemImage: "paintpalette") {
                        Button("Default") { changeSidebar { try await store.setSidebarFolderColor(item.id, color: nil) } }
                        ForEach(TagColor.allCases, id: \.self) { color in
                            Button {
                                changeSidebar { try await store.setSidebarFolderColor(item.id, color: color) }
                            } label: {
                                Label {
                                    Text(color.folderColorName)
                                } icon: {
                                    Image(nsImage: color.folderColorSwatch(isSelected: folder.color == color))
                                        .renderingMode(.original)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var sidebarDrag: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(SidebarDropFrames.coordinateSpace))
            .onChanged { value in
                guard !changingSidebar, editor == nil, folderBeingRenamed == nil else { return }
                if draggedItemID == nil {
                    guard let (row, _) = dropFrame(at: value.startLocation), case .item(let id) = row else { return }
                    beginDrag(id)
                }
                dragPointer.location = value.location
                updateDropPosition(at: value.location)
                updateDragScrolling(at: value.location)
            }
            .onEnded { value in
                guard draggedItemID != nil else { return }
                updateDropPosition(at: value.location)
                let destination = dropPosition
                switch destination {
                case .row(let id, let area):
                    if let target = sidebarItems.first(where: { $0.id == id }) {
                        moveDraggedItem(to: area.destination(on: target, in: sidebarItems))
                    }
                case .rootEnd:
                    moveDraggedItem(to: (parent: nil, before: nil))
                case nil:
                    break
                }
                finishDrag()
            }
    }

    private func beginDrag(_ id: UUID) {
        let children = Dictionary(grouping: sidebarItems, by: \.parentID)
        var descendants: Set<UUID> = []
        var pending = [id]
        while let item = pending.popLast() {
            if descendants.insert(item).inserted {
                pending.append(contentsOf: (children[item] ?? []).map(\.id))
            }
        }
        invalidDropTargets = descendants
        draggedItemID = id
    }

    private func finishDrag() {
        draggedItemID = nil
        invalidDropTargets = []
        dropPosition = nil
        dragScrollDirection = 0
    }

    private func dropFrame(at point: CGPoint) -> (SidebarDropRow, CGRect)? {
        guard CGRect(origin: .zero, size: sidebarViewport).contains(point) else { return nil }
        return dropFrames.first { $0.value.contains(point) }.map { ($0.key, $0.value) }
    }

    private func updateDropPosition(at point: CGPoint) {
        var proposal: DropPosition?
        if let (row, frame) = dropFrame(at: point) {
            switch row {
            case .item(let id):
                if !invalidDropTargets.contains(id), let item = sidebarItems.first(where: { $0.id == id }) {
                    let area = SidebarDropArea(y: point.y - frame.minY, height: frame.height, isFolder: item.folder != nil)
                    proposal = .row(id, area)
                }
            case .rootEnd:
                proposal = .rootEnd
            }
        }
        if dropPosition != proposal { dropPosition = proposal }
    }

    private func updateDragScrolling(at point: CGPoint) {
        let edge: CGFloat = 22
        var direction = 0
        if (0...sidebarViewport.width).contains(point.x) {
            if point.y < edge { direction = -1 }
            else if point.y > sidebarViewport.height - edge { direction = 1 }
        }
        if dragScrollDirection != direction { dragScrollDirection = direction }
    }

    private func nextScrollItem(in direction: Int) -> UUID? {
        let rows = visibleItems.map(\.item.id)
        let insideViewport = rows.indices.filter { index in
            guard let frame = dropFrames[.item(rows[index])] else { return false }
            return frame.maxY > 0 && frame.minY < sidebarViewport.height
        }
        guard let edge = direction < 0 ? insideViewport.first : insideViewport.last else { return nil }
        let next = edge + direction
        return rows.indices.contains(next) ? rows[next] : nil
    }

    private func insertionLine(at position: DropPosition, depth: Int) -> some View {
        Capsule().fill(Color.accentColor).frame(height: 2)
            .padding(.leading, indentation(for: depth))
            .opacity(dropPosition == position ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func moveDraggedItem(to destination: (parent: UUID?, before: UUID?)?) {
        guard let id = draggedItemID, let destination, !changingSidebar else { return }
        var layout = sidebarItems
        do {
            try layout.moveSidebarItem(id, to: destination.parent, before: destination.before)
            applyLayout(layout) {
                try await store.moveSidebarItem(id, to: destination.parent, before: destination.before)
            }
        } catch {
            sidebarError = error.localizedDescription
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
