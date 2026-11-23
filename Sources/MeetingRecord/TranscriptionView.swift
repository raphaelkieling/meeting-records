import SwiftUI

struct TranscriptionView: View {
    let meetingID: UUID
    let store: MeetingStore
    let recordingRevision: Int
    @ObservedObject var transcription: TranscriptionCoordinator
    @State private var inputs: [Recording] = []
    @State private var passages: [UUID: [TranscriptPassage]] = [:]
    @State private var statuses: [UUID: TranscriptStatus] = [:]
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let error {
                    Text(error).foregroundStyle(.red)
                } else if !passages.isEmpty {
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
            .background(alignment: .topLeading) {
                MeetingScrollbar().frame(width: 0, height: 0).accessibilityHidden(true)
            }
        }
        .contentMargins(.all, EdgeInsets(top: 0, leading: 0, bottom: 92, trailing: 12), for: .scrollContent)
        .contentMargins(.vertical, 6, for: .scrollIndicators)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if error == nil, passages.isEmpty {
                MeetingEmptyState("No transcription yet.", icon: "text.bubble", detail: context)
            }
        }
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

struct TranscriptionSettingsView: View {
    @ObservedObject var transcription: TranscriptionCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Transcription Models").font(.headline)
                if !transcription.isReady {
                    Text("Download a model to enable recording and local transcription.")
                        .foregroundStyle(.secondary)
                }
                ForEach(TranscriptionModel.catalog) { model in
                    modelRow(model)
                }
                if let error = transcription.error {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
                Divider()
                RecordingPermissionsView()
            }
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func modelRow(_ model: TranscriptionModel) -> some View {
        let installed = transcription.installed.contains(model.id)
        let selected = transcription.selected == model
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.name).font(.headline)
                    Text(ByteCountFormatter.string(fromByteCount: model.downloadSize, countStyle: .file))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if installed && selected {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else if installed {
                    Button("Use Model") { transcription.select(model) }
                } else {
                    Button("Download") { Task { await transcription.download(model) } }
                        .disabled(transcription.downloading != nil)
                }
            }
            if transcription.downloading == model {
                ProgressView(value: Double(transcription.downloadedBytes), total: Double(model.downloadSize)) {
                    Text("Downloading \(model.name)")
                } currentValueLabel: {
                    Text(ByteCountFormatter.string(fromByteCount: transcription.downloadedBytes, countStyle: .file))
                }
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}
