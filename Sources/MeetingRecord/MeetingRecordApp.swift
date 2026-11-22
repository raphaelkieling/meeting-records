import SwiftUI

@main
struct MeetingRecordApp: App {
    var body: some Scene {
        Window("Meeting Record", id: "main") {
            ContentView()
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 1000, height: 700)
        .windowResizability(.contentMinSize)
        .commands { MeetingCommands() }
    }
}

private struct RenameMeetingKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var renameMeeting: (() -> Void)? {
        get { self[RenameMeetingKey.self] }
        set { self[RenameMeetingKey.self] = newValue }
    }
}

private struct MeetingCommands: Commands {
    @FocusedValue(\.renameMeeting) private var rename

    var body: some Commands {
        CommandMenu("Meeting") {
            Button("Rename Meeting") { rename?() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(rename == nil)
        }
    }
}
