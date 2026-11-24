import AVFoundation
import Combine
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case models = "Models"
    case summarization = "Summarization"
    case data = "Data"

    var id: Self { self }

    var icon: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .models: "waveform"
        case .summarization: "sparkles"
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
            Text("This permanently deletes every meeting, recording, transcript, and summary saved on this Mac.")
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
                    Text(option.rawValue).font(.body.weight(.medium))
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
        case .summarization:
            SummarizationSettings()
        case .data:
            VStack(alignment: .leading, spacing: 12) {
                Text("Permanently remove all meetings and their saved recordings, transcripts, and summaries from this Mac.")
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
                Text("Microphone Sensitivity").font(.headline)
                Text("Only microphone audio above this level is sent for transcription. The full recording is always saved.")
                    .foregroundStyle(.secondary)
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
                Text("Download a model to enable recording and local transcription.")
                    .foregroundStyle(.secondary)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

private struct SummarizationSettings: View {
    @AppStorage(SummaryModel.preferenceKey) private var model: SummaryModel = .appleIntelligence
    @AppStorage(OpenAISummaryKey.savedPreferenceKey) private var hasOpenAIKey = false
    @State private var draftKey = ""
    @State private var isChangingKey = false
    @State private var keyError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Model", selection: $model) {
                ForEach(SummaryModel.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            if model.usesOpenAI {
                VStack(alignment: .leading, spacing: 6) {
                    SecureField(hasOpenAIKey ? "Replace OpenAI API key" : "OpenAI API key", text: $draftKey)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                    HStack {
                        Button("Save Key") {
                            let key = draftKey
                            changeKey(saved: true) { try OpenAISummaryKey.save(key) }
                        }
                        .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if hasOpenAIKey {
                            Button("Remove Key") { changeKey(saved: false, action: OpenAISummaryKey.remove) }
                        }
                    }
                }
                .disabled(isChangingKey)
                if let keyError {
                    Text(keyError).font(.caption).foregroundStyle(.red)
                } else if hasOpenAIKey {
                    Label("API key saved in Keychain", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("OpenAI receives transcript text when you request a summary. API usage is billed separately from ChatGPT.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                AppleIntelligenceAvailability()
            }
        }
        .onDisappear { draftKey = "" }
        .onChange(of: model.usesOpenAI) { _, usesOpenAI in
            if !usesOpenAI { draftKey = "" }
        }
    }

    private func changeKey(saved: Bool, action: @escaping @Sendable () throws -> Void) {
        isChangingKey = true
        keyError = nil
        Task {
            defer { isChangingKey = false }
            do {
                try await Task.detached(operation: action).value
                hasOpenAIKey = saved
                draftKey = ""
            } catch {
                keyError = error.localizedDescription
            }
        }
    }
}

private struct AppleIntelligenceAvailability: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var availability: MeetingSummarizer.Availability?

    var body: some View {
        Group {
            if let availability {
                Text(availability.message ?? "Available on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await MeetingSummarizer.watchAvailability { availability = $0 }
        }
    }
}

