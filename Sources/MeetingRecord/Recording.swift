import Foundation

struct Recording: Identifiable, Sendable {
    enum State: String, Sendable { case starting, recording, completed, interrupted }

    let id: UUID
    let meetingID: UUID
    let startedAt: Date
    let endedAt: Date?
    let state: State
}

struct AudioSegment: Sendable {
    enum Source: String, CaseIterable, Sendable { case me, other }

    let recordingID: UUID
    let source: Source
    // Nanoseconds from the common host-clock start of the recording.
    let startOffset: Int64
    let frameCount: Int64
    let relativePath: String
}

enum RecordingError: LocalizedError {
    case microphonePermission, screenPermission, noMicrophone, noDisplay
    case invalidAudio, captureOverrun, emptyRecording, alreadyRecording

    var errorDescription: String? {
        switch self {
        case .microphonePermission: "Allow microphone access in System Settings → Privacy & Security → Microphone, then try again."
        case .screenPermission: "Allow screen recording in System Settings → Privacy & Security to capture Mac audio. Reopen Meeting Record after granting access."
        case .noMicrophone: "Connect a microphone and try again."
        case .noDisplay: "Mac audio capture needs an available display."
        case .invalidAudio: "An audio source delivered an unreadable buffer or timestamp."
        case .captureOverrun: "The app could not save audio as fast as it was captured."
        case .emptyRecording: "No audio was available to save."
        case .alreadyRecording: "Another Meeting is recording or finishing."
        }
    }
}
