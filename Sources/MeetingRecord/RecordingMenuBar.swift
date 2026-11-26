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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await recording.transcription.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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
        let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        if canStop, let recordingImage = symbolImage?.withSymbolConfiguration(.init(paletteColors: [.systemRed])) {
            recordingImage.isTemplate = false
            item.button?.image = recordingImage
        } else {
            item.button?.image = symbolImage
        }
        item.button?.setAccessibilityLabel(label)
        item.button?.toolTip = label

        let menu = NSMenu()
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        if canStop {
            menu.addItem(withTitle: "Take Screenshot", action: #selector(takeScreenshot), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "").target = self
        }
        item.menu = menu
    }

    @objc private func takeScreenshot() {
        recording.takeScreenCapture()
    }

    @objc private func stopRecording() {
        recording.stop()
    }
}
