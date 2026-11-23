import AppKit
import AVFoundation
import SwiftUI

struct RecordingPermissionsView: View {
    @Environment(\.openURL) private var openURL
    private let appURL = Bundle.main.bundleURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recording Permissions").font(.headline)
            HStack {
                Label("Microphone", systemImage: "mic")
                Spacer()
                Button("Set Up Microphone") {
                    Task {
                        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined,
                           await AVCaptureDevice.requestAccess(for: .audio) { return }
                        openPrivacyPane("Privacy_Microphone")
                    }
                }
            }
            HStack {
                Label("Screen & System Audio", systemImage: "waveform")
                Spacer()
                Button("Open System Settings") { openPrivacyPane("Privacy_ScreenCapture") }
            }
            if appURL.pathExtension == "app" {
                HStack {
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                            .resizable().frame(width: 28, height: 28)
                        Text("Meeting Record")
                    }
                    .padding(8)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    .onDrag { NSItemProvider(object: appURL as NSURL) }
                    .accessibilityHint("Drag the application into the Screen and System Audio Recording list.")
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([appURL]) }
                }
                Text("Drag Meeting Record into the Screen & System Audio Recording list, or use + there to select the app. Reopen Meeting Record if macOS asks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func openPrivacyPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        openURL(url)
    }
}
