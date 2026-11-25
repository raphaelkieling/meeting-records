import AVFoundation
import Combine
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case models = "Transcription"
    case ai = "AI"
    case data = "Data"

    var id: Self { self }

    var icon: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .models: "waveform"
        case .ai: "sparkles"
        case .data: "externaldrive"
        }
    }
}

struct SettingsView: View {
    @Binding var section: SettingsSection?
    @ObservedObject var transcription: TranscriptionCoordinator
    @ObservedObject var recording: RecordingCoordinator
    let deleteAll: () -> Void
    @State private var hasMoreBelow = false
    @State private var confirmingDeleteAll = false
    @State private var recordingUsage = "Calculating…"

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(SettingsSection.allCases) { option in
                    sectionGroup(option)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
            .onGeometryChange(for: Bool.self) { geometry in
                guard let viewport = geometry.bounds(of: .scrollView) else { return false }
                return geometry.frame(in: .scrollView).maxY > viewport.height + 1
            } action: { hasMoreBelow = $0 }
        }
        .bottomScrollFade(hasMoreBelow: hasMoreBelow)
        .confirmationDialog("Delete All Meeting Data?", isPresented: $confirmingDeleteAll,
                            titleVisibility: .visible) {
            Button("Delete All Meeting Data", role: .destructive, action: deleteAll)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes every meeting, recording, transcript, summary, and chat saved on this Mac.")
        }
    }

    private func sectionGroup(_ option: SettingsSection) -> some View {
        let isExpanded = section == option
        return VStack(alignment: .leading, spacing: 0) {
            Button { section = isExpanded ? nil : option } label: {
                HStack(spacing: 10) {
                    Image(systemName: option.icon)
                        .foregroundStyle(Color.meetingAccent)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(option.rawValue).font(.headline)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable()
            .focusEffectDisabled()
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                Divider().padding(.horizontal, 14)
                sectionContent(option)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func sectionContent(_ option: SettingsSection) -> some View {
        switch option {
        case .general:
            GeneralSettings(recording: recording, transcription: transcription)
        case .models:
            TranscriptionModelSettings(transcription: transcription)
        case .ai:
            AISettingsView()
        case .data:
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Recording Storage") {
                    Text(recordingUsage)
                        .foregroundStyle(.secondary)
                }
                Text("Permanently remove all meetings and their saved recordings, transcripts, summaries, and chats from this Mac.")
                    .foregroundStyle(.secondary)
                Button("Delete All Meeting Data…", role: .destructive) {
                    confirmingDeleteAll = true
                }
                .disabled(recording.state != .idle)
                if recording.state != .idle {
                    Text("Stop the active recording before deleting meeting data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .task(id: recording.revision) {
                do {
                    let root = try await recording.store.recordingRoot()
                    repeat {
                        let bytes = try await RecordingStorage.bytesUsed(at: root)
                        try Task.checkCancellation()
                        let gigabytes = (Double(bytes) / 1_000_000_000)
                            .formatted(.number.precision(.fractionLength(3)))
                        recordingUsage = bytes > 0 && bytes < 1_000_000 ? "< 0.001 GB" : "\(gigabytes) GB"
                        guard case .recording = recording.state else { break }
                        try await Task.sleep(for: .seconds(10))
                    } while !Task.isCancelled
                } catch {
                    if !Task.isCancelled { recordingUsage = "Unavailable" }
                }
            }
        }
    }
}

private struct GeneralSettings: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var recording: RecordingCoordinator
    @ObservedObject var transcription: TranscriptionCoordinator
    @State private var currentLevel = 0.0
    @State private var microphones: [RecordingCapture.Microphone] = []
    @State private var microphoneListRevision = 0
    @State private var microphoneAllowed: Bool?
    @State private var isTestingMicrophone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RecordingPermissionsView(microphoneAllowed: $microphoneAllowed)
            if microphoneAllowed == true {
                Divider()
                Picker("Microphone Input", selection: Binding(get: { recording.microphoneID },
                                                               set: recording.selectMicrophone)) {
                    Text("System Default").tag("")
                    ForEach(microphones) { microphone in
                        Text(microphone.name).tag(microphone.id)
                    }
                    if !recording.microphoneID.isEmpty,
                       !microphones.contains(where: { $0.id == recording.microphoneID }) {
                        Text("Selected Microphone Unavailable").tag(recording.microphoneID)
                    }
                }
                .disabled(recording.state != .idle)
                SettingsHeading("Microphone Sensitivity")
                SettingsNote("This threshold only affects transcription. The full microphone recording is saved.")
                if isTestingMicrophone {
                    microphoneLevelMeter
                }
                Slider(value: Binding(get: { transcription.microphoneThreshold },
                                      set: { transcription.setMicrophoneThreshold($0) }), in: 0...1)
                    .accessibilityLabel("Microphone transcription threshold")
                    .accessibilityValue("\(Int(transcription.microphoneThreshold * 100)) percent")
                HStack {
                    Button(isTestingMicrophone ? "Stop Test" : "Test Microphone") {
                        isTestingMicrophone.toggle()
                        recording.setMicrophoneMetering(isTestingMicrophone)
                    }
                    Spacer()
                    Text("Threshold \(Int(transcription.microphoneThreshold * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: microphoneAllowed) { _, allowed in
            if allowed != true { stopMicrophoneTest() }
            microphoneListRevision += 1
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { microphoneListRevision += 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification).receive(on: RunLoop.main)) { _ in
            microphoneListRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification).receive(on: RunLoop.main)) { _ in
            microphoneListRevision += 1
        }
        .task(id: microphoneListRevision) {
            guard microphoneAllowed == true else { return }
            let devices = await Task.detached { RecordingCapture.microphones() }.value
            guard !Task.isCancelled else { return }
            microphones = devices
        }
        .onDisappear(perform: stopMicrophoneTest)
    }

    private var microphoneLevelMeter: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(.green).frame(width: geometry.size.width * currentLevel)
                Rectangle().fill(.primary).frame(width: 2)
                    .offset(x: geometry.size.width * transcription.microphoneThreshold)
            }
        }
        .frame(height: 8)
        .accessibilityLabel("Microphone input level")
        .accessibilityValue("\(Int(currentLevel * 100)) percent; threshold \(Int(transcription.microphoneThreshold * 100)) percent")
        .onReceive(recording.microphoneRMS) { currentLevel = $0 }
    }

    private func stopMicrophoneTest() {
        isTestingMicrophone = false
        currentLevel = 0
        recording.setMicrophoneMetering(false)
    }
}

private struct TranscriptionModelSettings: View {
    @ObservedObject var transcription: TranscriptionCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !transcription.isReady {
                SettingsNote("Download a model to transcribe recordings on this Mac.")
            }
            VStack(spacing: 0) {
                ForEach(TranscriptionModel.catalog) { model in
                    modelRow(model)
                    if model != TranscriptionModel.catalog.last { Divider() }
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            if let error = transcription.error {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            }
        }
    }

    private func modelRow(_ model: TranscriptionModel) -> some View {
        let installed = transcription.installed.contains(model.id)
        let selected = transcription.selected == model
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.name)
                Text(ByteCountFormatter.string(fromByteCount: model.downloadSize, countStyle: .file))
                    .font(.caption).foregroundStyle(.secondary)
                if model.isNemotron {
                    Text("Recommended").font(.caption.weight(.medium)).foregroundStyle(Color.meetingAccent)
                }
                Spacer()
                if installed && selected {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else if installed {
                    Button("Use Model") { transcription.select(model) }
                } else {
                    Button("Download") { Task { await transcription.download(model) } }
                        .disabled(!transcription.canDownload)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

struct AppleIntelligenceAvailability: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var availability: MeetingSummarizer.Availability?

    var body: some View {
        Group {
            if let availability {
                SettingsNote(availability.message ?? "Apple Intelligence is available on this Mac.")
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await MeetingSummarizer.watchAvailability { availability = $0 }
        }
    }
}


struct SettingsHeading: View {
    private let title: LocalizedStringKey
    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title).font(.headline).accessibilityAddTraits(.isHeader)
    }
}

struct SettingsNote: View {
    private let message: String
    init(_ message: String) { self.message = message }

    var body: some View {
        Text(message).font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsPromptEditor: View {
    @Binding var text: String
    let label: LocalizedStringKey
    let height: CGFloat

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.35))
                    .allowsHitTesting(false)
            }
            .accessibilityLabel(Text(label))
    }
}
