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
    @State private var passages: [UUID: [TranscriptPassage]] = [:]
    @State private var statuses: [UUID: TranscriptStatus] = [:]
    @State private var error: String?
    @State private var hasLoaded = false
    @State private var hasMoreTranscriptionBelow = false

    var body: some View {
        ScrollViewReader { proxy in
            transcript
                .task(id: "\(citedPassageRevision)-\(hasLoaded)") {
                    guard hasLoaded, let citedPassageID else { return }
                    for _ in 0..<30 {
                        guard !Task.isCancelled else { return }
                        if passages.values.contains(where: { $0.contains(where: { $0.id == citedPassageID }) }) {
                            await Task.yield()
                            guard !Task.isCancelled else { return }
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                proxy.scrollTo(citedPassageID, anchor: .center)
                            }
                            return
                        }
                        try? await Task.sleep(for: .milliseconds(40))
                    }
                }
        }
    }

    private var transcript: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let error {
                    Text(error).foregroundStyle(.red)
                }
                if !passages.isEmpty {
                    ForEach(Array(inputs.enumerated()), id: \.element.id) { index, input in
                        let rows = passages[input.id] ?? []
                        let status = statuses[input.id]?.status ?? .pending
                        Section {
                            ForEach(rows) { passage in
                                let seconds = passage.startOffset / 1_000_000_000
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(time(seconds)) · \(passage.source == .me ? "Me" : "Other")")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    Text(passage.text).textSelection(.enabled)
                                }
                                .overlay(alignment: .leading) {
                                    if passage.id == citedPassageID {
                                        Circle().fill(Color.meetingAccent).frame(width: 8, height: 8)
                                            .offset(x: -12)
                                            .accessibilityLabel("Referenced passage")
                                    }
                                }
                                .id(passage.id)
                            }
                        } header: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Recording \(index + 1)").font(.headline)
                                    Text(status.rawValue).font(.caption).foregroundStyle(.secondary)
                                }
                                if let error = statuses[input.id]?.error {
                                    Text(error).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .onGeometryChange(for: Bool.self) { geometry in
                guard let viewport = geometry.bounds(of: .scrollView) else { return false }
                return geometry.frame(in: .scrollView).maxY > viewport.height + 1
            } action: { hasMoreTranscriptionBelow = $0 }
        }
        .contentMargins(.all, EdgeInsets(top: 0, leading: 0, bottom: 92, trailing: 12), for: .scrollContent)
        .bottomScrollFade(hasMoreBelow: hasMoreTranscriptionBelow)
        .opacity(hasLoaded || error != nil ? 1 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: hasLoaded || error != nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if error == nil {
                if !hasLoaded {
                    ProgressView("Loading transcription…")
                        .transition(.opacity)
                } else if passages.isEmpty {
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
                guard !Task.isCancelled else { return }
                self.inputs = inputs
                passages = Dictionary(grouping: rows, by: \.inputID)
                self.statuses = statuses
                error = nil
                hasLoaded = true
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "Could not load transcription. \(error.localizedDescription)"
            }
        }
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
