import AppKit
import AVFoundation
import CoreGraphics
import SwiftUI

struct RecordingPermissionsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Binding var microphoneAllowed: Bool?
    @State private var screenCaptureAllowed: Bool?
    @State private var requestingMicrophone = false
    private let appURL = Bundle.main.bundleURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recording Permissions").font(.headline)
            HStack {
                Label("Microphone", systemImage: "mic")
                Spacer()
                if microphoneAllowed == true {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if microphoneAllowed == false {
                    Button("Set Up Microphone") {
                        requestingMicrophone = true
                        Task {
                            defer { requestingMicrophone = false }
                            let status = await Task.detached {
                                AVCaptureDevice.authorizationStatus(for: .audio)
                            }.value
                            if status == .notDetermined {
                                microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
                            } else if status == .authorized {
                                microphoneAllowed = true
                            } else {
                                openPrivacyPane("Privacy_Microphone")
                            }
                        }
                    }
                    .disabled(requestingMicrophone)
                }
            }
            HStack {
                Label("Screen & System Audio", systemImage: "waveform")
                Spacer()
                if screenCaptureAllowed == true {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if screenCaptureAllowed == false {
                    Button("Open System Settings") { openPrivacyPane("Privacy_ScreenCapture") }
                }
            }
            if screenCaptureAllowed == false, appURL.pathExtension == "app" {
                HStack {
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)
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
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            async let microphone = Task.detached {
                AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            }.value
            async let screen = Task.detached { CGPreflightScreenCaptureAccess() }.value
            let allowed = await microphone
            guard !Task.isCancelled else { return }
            if !requestingMicrophone { microphoneAllowed = allowed }
            let screenAllowed = await screen
            guard !Task.isCancelled else { return }
            screenCaptureAllowed = screenAllowed
        }
    }

    private func openPrivacyPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        openURL(url)
    }
}
