import AppKit
import SwiftUI

struct FirstLaunchSetupView: View {
    @ObservedObject var transcription: TranscriptionCoordinator
    let close: () -> Void

    @State private var step = Step.welcome
    @State private var microphoneAllowed: Bool?

    private enum Step: Int, CaseIterable {
        case welcome, recording, transcription

        var title: String {
            switch self {
            case .welcome: "Welcome to Meeting Record"
            case .recording: "Set Up Recording"
            case .transcription: "Set Up Transcription"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                if step == .welcome {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 76, height: 76)
                        .accessibilityHidden(true)
                }
                Text(step.title)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                switch step {
                case .welcome:
                    Text("Record meetings, read transcripts, and find what was said. Your recordings and transcriptions are stored on this Mac.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .recording:
                    Text("Allow access to your microphone and the Mac’s system audio. Meeting Record saves them as separate tracks.")
                        .foregroundStyle(.secondary)
                    RecordingPermissionsView(microphoneAllowed: $microphoneAllowed, showsHeading: false)
                case .transcription:
                    Text("You can record right away. Download a model to transcribe saved audio on this Mac, even offline.")
                        .foregroundStyle(.secondary)
                    modelCard
                }
            }
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .leading)

            Divider()

            HStack(spacing: 8) {
                Text("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let previous = Step(rawValue: step.rawValue - 1) {
                    Button("Back") { step = previous }
                }
                if let next = Step(rawValue: step.rawValue + 1) {
                    Button("Set Up Later", role: .cancel, action: close)
                        .keyboardShortcut(.cancelAction)
                    Button("Continue") { step = next }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done", action: close)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 500)
        .tint(.meetingAccent)
        .onExitCommand(perform: close)
    }

    private var modelCard: some View {
        let model = TranscriptionModel.nemotron
        return VStack(alignment: .leading, spacing: 10) {
            if transcription.isReady {
                Label("\(transcription.selected.name) is active.", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
            } else {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.name).font(.callout.weight(.semibold))
                        Text("Recommended · \(ByteCountFormatter.string(fromByteCount: model.downloadSize, countStyle: .file))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if transcription.installed.contains(model.id) {
                        Button("Use Model") { transcription.select(model) }
                    } else if transcription.downloading == nil {
                        Button("Download Model") {
                            Task { await transcription.download(model) }
                        }
                        .disabled(!transcription.canDownload)
                    }
                }
                if let downloading = transcription.downloading {
                    ProgressView(value: Double(transcription.downloadedBytes), total: Double(downloading.downloadSize)) {
                        Text("Downloading \(downloading.name)")
                    } currentValueLabel: {
                        Text(ByteCountFormatter.string(fromByteCount: transcription.downloadedBytes, countStyle: .file))
                    }
                }
            }
            if let error = transcription.error {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            Text("You can manage models and recording permissions in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }
}
