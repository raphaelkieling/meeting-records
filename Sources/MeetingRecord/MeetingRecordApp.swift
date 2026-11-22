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
    }
}
