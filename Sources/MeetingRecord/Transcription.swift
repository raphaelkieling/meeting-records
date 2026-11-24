import Foundation

enum TranscriptionStatus: String, Sendable {
    case pending = "Pending"
    case transcribing = "Transcribing"
    case complete = "Complete"
}

struct TranscriptStatus: Sendable {
    let status: TranscriptionStatus
    let error: String?
}

struct TranscriptionWork: Sendable {
    let audio: AudioSegment
    let audioSegments: [AudioSegment]
    let modelID: String?
    let modelVersion: String?
}

struct TranscribedCheckpoint: Sendable {
    struct Segment: Sendable {
        let startOffset: Int64
        let endOffset: Int64
        let text: String
    }
    let processedThrough: Int64
    let segments: [Segment]
}

struct TranscriptPassage: Sendable, Identifiable {
    static func hasWords(_ text: String) -> Bool {
        text.rangeOfCharacter(from: .alphanumerics) != nil
    }

    let inputID: UUID
    let source: AudioSegment.Source
    let checkpoint: Int64
    let sequence: Int64
    let startOffset: Int64
    let endOffset: Int64
    let text: String

    var id: String { "\(inputID):\(source.rawValue):\(checkpoint):\(sequence)" }
}
