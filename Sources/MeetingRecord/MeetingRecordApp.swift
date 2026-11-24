import SwiftUI

extension Color {
    static let meetingAccent = Color(red: 0.71, green: 0.13, blue: 0.21)
}

@main
struct MeetingRecordApp: App {
    @StateObject private var recording = RecordingCoordinator()

    var body: some Scene {
        Window("Meeting Record", id: "main") {
            ContentView(recording: recording, transcription: recording.transcription)
                .frame(minWidth: 720, minHeight: 480)
                .accentColor(.meetingAccent)
                .tint(.meetingAccent)
                .focusEffectDisabled()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 700)
        .windowResizability(.contentMinSize)
        .commands { MeetingCommands() }
    }
}

private struct RenameMeetingKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct OpenCommandPaletteKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
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
    @FocusedValue(\.renameMeeting) private var rename
    @FocusedValue(\.openCommandPalette) private var openCommandPalette

    var body: some Commands {
        CommandMenu("Meeting") {
            Button("Search…") { openCommandPalette?() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(openCommandPalette == nil)
            Button("Rename Meeting") { rename?() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(rename == nil)
        }
    }
}
