import AppKit
import Combine

@MainActor
final class RecordingMenuBar: NSObject, NSApplicationDelegate {
    let recording = RecordingCoordinator()
    private var statusItem: NSStatusItem?
    private var stateObservation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        stateObservation = recording.$state.removeDuplicates().sink { [weak self] state in
            self?.updateStatusItem(for: state)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        recording.state == .idle
    }

    private func updateStatusItem(for state: RecordingCoordinator.State) {
        let canStop: Bool
        switch state {
        case .idle, .starting:
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        case .recording:
            canStop = true
        case .finishing:
            canStop = false
        }

        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        let title = canStop ? "Recording" : "Saving Recording…"
        let symbol = canStop ? "record.circle.fill" : "hourglass"
        let label = "Meeting Record: \(title)"
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.button?.contentTintColor = canStop ? .systemRed : nil
        item.button?.setAccessibilityLabel(label)
        item.button?.toolTip = label

        let menu = NSMenu()
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        if canStop {
            menu.addItem(withTitle: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "").target = self
        }
        item.menu = menu
    }

    @objc private func stopRecording() {
        recording.stop()
    }
}
