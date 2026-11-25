import SwiftUI

extension Color {
    static let meetingAccent = Color(red: 0.71, green: 0.13, blue: 0.21)
}

@main
struct MeetingRecordApp: App {
    @NSApplicationDelegateAdaptor(RecordingMenuBar.self) private var menuBar
    @AppStorage("didDismissSetup") private var didDismissSetup = false
    @State private var showingSetup = false

    private var recording: RecordingCoordinator { menuBar.recording }

    var body: some Scene {
        Window("Meeting Record", id: "main") {
            ContentView(recording: recording, transcription: recording.transcription)
                .frame(minWidth: 720, minHeight: 480)
                .accentColor(.meetingAccent)
                .tint(.meetingAccent)
                .focusEffectDisabled()
                .onAppear {
                    if !didDismissSetup { showingSetup = true }
                }
                .sheet(isPresented: $showingSetup, onDismiss: finishSetup) {
                    FirstLaunchSetupView(transcription: recording.transcription, close: finishSetup)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 700)
        .windowResizability(.contentMinSize)
        .commands { MeetingCommands() }
    }

    private func finishSetup() {
        didDismissSetup = true
        showingSetup = false
    }
}

private struct RenameMeetingKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct OpenCommandPaletteKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct FindInTranscriptKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var findInTranscript: (() -> Void)? {
        get { self[FindInTranscriptKey.self] }
        set { self[FindInTranscriptKey.self] = newValue }
    }

    var renameMeeting: (() -> Void)? {
        get { self[RenameMeetingKey.self] }
        set { self[RenameMeetingKey.self] = newValue }
    }

    var openCommandPalette: (() -> Void)? {
        get { self[OpenCommandPaletteKey.self] }
        set { self[OpenCommandPaletteKey.self] = newValue }
    }
}

private struct MeetingCommands: Commands {
    @FocusedValue(\.findInTranscript) private var findInTranscript
    @FocusedValue(\.renameMeeting) private var rename
    @FocusedValue(\.openCommandPalette) private var openCommandPalette

    var body: some Commands {
        CommandMenu("Meeting") {
            Button("Search…") { openCommandPalette?() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(openCommandPalette == nil)
            Button("Find in Transcript…") { findInTranscript?() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(findInTranscript == nil)
            Button("Rename Meeting") { rename?() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(rename == nil)
        }
    }
}
