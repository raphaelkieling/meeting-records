import SwiftUI
import Combine

struct RecordingControl: View {
    let state: RecordingCoordinator.State
    let meetingID: UUID
    let levels: CurrentValueSubject<Double, Never>
    let modelReady: Bool
    let openSettings: () -> Void
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var level = 0.0

    private var isRecording: Bool { state == .recording(meetingID) }
    private var isWorking: Bool { state == .starting(meetingID) || state == .finishing(meetingID) }
    private var needsModel: Bool { state == .idle && !modelReady }
    private var blocked: Bool { state.meetingID.map { $0 != meetingID } ?? false }
    private var label: String {
        if isRecording { return "Stop Recording" }
        if state == .starting(meetingID) { return "Starting Recording" }
        if state == .finishing(meetingID) { return "Saving Recording" }
        return "Record"
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                if isRecording {
                    HStack(spacing: 3) {
                        ForEach([0.45, 0.76, 1, 0.65, 0.91, 0.57, 0.38], id: \.self) { weight in
                            Capsule()
                                .fill(.white)
                                .frame(width: 3, height: 3 + CGFloat(level * weight) * 24)
                        }
                    }
                    .frame(width: 62, height: 26)
                    .accessibilityHidden(true)
                    .transition(.opacity)
                }
                Button(action: action) {
                    Group {
                        if isWorking {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: isRecording ? "stop.fill" : "circle.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle((blocked || needsModel) ? Color.secondary : .white)
                        }
                    }
                    .frame(width: 50, height: 50)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .focusable(!isWorking && !blocked && !needsModel)
                .disabled(isWorking || blocked || needsModel)
                .accessibilityLabel(label)
                .help(needsModel ? "Install a transcription model to record." : label)
            }
            .background((blocked || needsModel) ? Color(nsColor: .controlBackgroundColor)
                        : isRecording ? Color(white: 0.15) : .meetingAccent, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            if needsModel {
                Button("Set up transcription in Settings", action: openSettings)
                    .buttonStyle(.link)
                    .font(.caption)
            } else {
                Text("Another Meeting is recording or finishing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .opacity(blocked ? 1 : 0)
                    .accessibilityHidden(!blocked)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.19), value: isRecording)
        .onReceive(levels) { next in
            level = (max(0, min(1, next))).squareRoot()
        }
    }
}

struct RecordingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 8, height: 8)
            .overlay {
                if !reduceMotion {
                    Circle().stroke(.red.opacity(pulsing ? 0 : 0.55))
                        .scaleEffect(pulsing ? 2 : 1)
                        .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulsing)
                        .onAppear { pulsing = true }
                        .onDisappear { pulsing = false }
                }
            }
            .accessibilityHidden(true)
    }
}
