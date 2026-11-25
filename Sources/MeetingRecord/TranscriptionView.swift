import SwiftUI

struct TranscriptionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let meetingID: UUID
    let store: MeetingStore
    let recordingRevision: Int
    @ObservedObject var transcription: TranscriptionCoordinator
    var citedPassageID: String?
    var citedPassageRevision: Int
    @State private var inputs: [Recording] = []
    @State private var statuses: [UUID: TranscriptStatus] = [:]
    @State private var error: String?
    @State private var hasLoaded = false
    @State private var hasMoreTranscriptionBelow = false

    let returnToChat: (() -> Void)?
    @StateObject private var playback = RecordingPlayback()
    @State private var rows: [Row] = []
    @State private var scrollTarget: String?
    @State private var query = ""
    @State private var showingFind = false
    @FocusState private var findFocused: Bool
    @State private var searchMatch: Int?
    @State private var searchMatches: [String] = []

    private enum Row: Identifiable {
        case header(Recording, Int)
        case passage(TranscriptPassage, canPlay: Bool)
        case capture(MeetingScreenCapture)

        var offset: Int64 {
            switch self {
            case .header: 0
            case .passage(let passage, _): passage.startOffset
            case .capture(let capture): capture.offset
            }
        }

        var id: String {
            switch self {
            case .header(let recording, _): "header-\(recording.id)"
            case .passage(let passage, _): passage.id
            case .capture(let capture): capture.id.uuidString
            }
        }
    }

    private struct ScrollRequest: Equatable {
        let revision: Int
        let id: String?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if playback.activeID != nil || returnToChat != nil { toolbar }
            if let error = playback.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            transcript
                .overlay(alignment: .topTrailing) {
                    if showingFind {
                        findPanel.padding(.top, 4).padding(.trailing, 10)
                    }
                }
        }
        .focusedSceneValue(\.findInTranscript, {
            showingFind = true
            findFocused = true
        })
        .onChange(of: query) { updateMatches(jump: true) }
        .onDisappear { playback.stop() }
    }

    private var findPanel: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Find in transcript…", text: $query)
                .textFieldStyle(.plain)
                .frame(width: 150)
                .focused($findFocused)
                .onSubmit { moveMatch(1) }
            Text(query.isEmpty ? "" : (searchMatch.map { "\($0 + 1) of \(searchMatches.count)" } ?? "No matches"))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .lineLimit(1).frame(width: 80, alignment: .center)
            Button("Previous Match", systemImage: "chevron.up") { moveMatch(-1) }
                .labelStyle(.iconOnly).disabled(searchMatches.isEmpty)
            Button("Next Match", systemImage: "chevron.down") { moveMatch(1) }
                .labelStyle(.iconOnly).disabled(searchMatches.isEmpty)
            Button("Close Find", systemImage: "xmark", action: closeFind)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.12)) }
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
        .onAppear { findFocused = true }
        .onExitCommand(perform: closeFind)
    }

    private func closeFind() {
        showingFind = false
        findFocused = false
        query = ""
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if playback.activeID != nil {
                Button("Stop Playback", systemImage: "stop.fill") { playback.stop() }
                    .labelStyle(.iconOnly)
            }
            if let returnToChat {
                Button("Back to Answer", systemImage: "arrow.left", action: returnToChat)
                    .buttonStyle(.link)
            }
        }
    }

    private var transcript: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let error { Text(error).foregroundStyle(.red) }
                ForEach(rows) { row in
                    switch row {
                    case .header(let input, let index):
                        let status = statuses[input.id]?.status ?? .pending
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Recording \(index + 1)").font(.headline)
                                Text(status.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                            if let error = statuses[input.id]?.error {
                                Text(error).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .id(row.id)
                    case .passage(let passage, let canPlay):
                        passageRow(passage, canPlay: canPlay).id(row.id)
                    case .capture(let capture):
                        ScreenCaptureThumbnail(capture: capture).id(row.id)
                    }
                }
            }
            .scrollTargetLayout()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .onGeometryChange(for: Bool.self) { geometry in
                guard let viewport = geometry.bounds(of: .scrollView) else { return false }
                return geometry.frame(in: .scrollView).maxY > viewport.height + 1
            } action: { hasMoreTranscriptionBelow = $0 }
        }
        .scrollPosition(id: $scrollTarget, anchor: .center)
        .task(id: ScrollRequest(revision: citedPassageRevision,
                                id: rows.contains { $0.id == citedPassageID } ? citedPassageID : nil)) {
            guard let citedPassageID, rows.contains(where: { $0.id == citedPassageID }) else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            scrollTarget = citedPassageID
        }
        .contentMargins(.all, EdgeInsets(top: 0, leading: 14, bottom: 92, trailing: 12), for: .scrollContent)
        .bottomScrollFade(hasMoreBelow: hasMoreTranscriptionBelow)
        .opacity(hasLoaded || error != nil ? 1 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: hasLoaded || error != nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if error == nil {
                if !hasLoaded {
                    ProgressView("Loading transcription…")
                        .transition(.opacity)
                } else if rows.isEmpty {
                    MeetingEmptyState("No transcription yet.", icon: "text.bubble",
                                      detail: context ?? "Transcripts appear here after your recordings are processed.")
                        .offset(y: -20)
                        .transition(.opacity)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: hasLoaded)
        .task(id: [recordingRevision, transcription.revision]) {
            do {
                let inputs = try await store.recordings(for: meetingID, includeActive: true)
                let rows = try await store.transcriptPassages(for: meetingID)
                let statuses = try await store.transcriptStatuses(for: meetingID)
                var timeline: [Row] = []
                let passagesByInput = Dictionary(grouping: rows, by: \.inputID)
                for (index, input) in inputs.enumerated() {
                    let captures = try await store.screenCaptures(meetingID: meetingID, recordingID: input.id)
                    let passages = passagesByInput[input.id, default: []]
                    let entries = passages.map { Row.passage($0, canPlay: input.endedAt != nil) } + captures.map(Row.capture)
                    if !entries.isEmpty {
                        timeline.append(.header(input, index))
                        timeline.append(contentsOf: entries.sorted { $0.offset < $1.offset })
                    }
                }
                guard !Task.isCancelled else { return }
                self.inputs = inputs
                self.rows = timeline
                updateMatches(jump: false)
                self.statuses = statuses
                error = nil
                hasLoaded = true
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "Could not load transcription. \(error.localizedDescription)"
            }
        }
    }

    private func passageRow(_ passage: TranscriptPassage, canPlay: Bool) -> some View {
        let timestamp = time(passage.startOffset / 1_000_000_000)
        let source = passage.source == .me ? "Me" : "Other"
        let selectedMatch = searchMatch.flatMap { searchMatches.indices.contains($0) ? searchMatches[$0] : nil }
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                if canPlay {
                    Button(timestamp) {
                        playback.play(passage.inputID, store: store, startOffset: passage.startOffset)
                    }
                    .buttonStyle(.link)
                    .help("Play from here")
                    .accessibilityLabel("Play from \(timestamp)")
                } else {
                    Text(timestamp)
                }
                Text("· \(source)")
                if passage.id == citedPassageID && canPlay {
                    Button("Play from here", systemImage: "play.fill") {
                        playback.play(passage.inputID, store: store, startOffset: passage.startOffset)
                    }
                    .buttonStyle(.link)
                    .padding(.leading, 6)
                }
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text(passage.text).textSelection(.enabled)
                .background(selectedMatch == passage.id ? Color.accentColor.opacity(0.15) : .clear,
                            in: RoundedRectangle(cornerRadius: 4))
        }
        .overlay(alignment: .leading) {
            if passage.id == citedPassageID {
                Circle().fill(Color.meetingAccent).frame(width: 8, height: 8)
                    .offset(x: -12).accessibilityLabel("Referenced passage")
            }
        }
    }

    private func updateMatches(jump: Bool) {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = searchMatch.flatMap { searchMatches.indices.contains($0) ? searchMatches[$0] : nil }
        searchMatches = term.isEmpty ? [] : rows.compactMap { row in
            guard case .passage(let passage, _) = row, passage.text.localizedStandardContains(term) else { return nil }
            return passage.id
        }
        searchMatch = previous.flatMap { searchMatches.firstIndex(of: $0) } ?? (searchMatches.isEmpty ? nil : 0)
        if jump, let searchMatch { scrollTarget = searchMatches[searchMatch] }
    }

    private func moveMatch(_ offset: Int) {
        guard let searchMatch else { return }
        let next = (searchMatch + offset + searchMatches.count) % searchMatches.count
        self.searchMatch = next
        scrollTarget = searchMatches[next]
    }

    private var context: String? {
        guard !inputs.isEmpty else { return nil }
        if let error = inputs.lazy.compactMap({ statuses[$0.id]?.error }).first { return error }
        if !transcription.isReady { return "Install a transcription model in Settings." }
        if inputs.contains(where: { statuses[$0.id]?.status == .transcribing }) {
            return "Transcribing saved audio…"
        }
        if inputs.contains(where: { statuses[$0.id]?.status != .complete }) { return "Audio is pending transcription." }
        return nil
    }

    private func time(_ seconds: Int64) -> String {
        String(format: "%lld:%02lld", seconds / 60, seconds % 60)
    }
}

extension View {
    func bottomScrollFade(hasMoreBelow: Bool) -> some View {
        scrollIndicators(.never, axes: .vertical)
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    if hasMoreBelow {
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 26)
                    }
                }
            }
    }
}
