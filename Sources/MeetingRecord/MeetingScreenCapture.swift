import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

struct MeetingScreenCapture: Identifiable, Sendable {
    let id: UUID
    let offset: Int64
    let url: URL

    var timestamp: String { ChatCitation.timestamp(at: offset) }

    static func directory(in root: URL, meetingID: UUID, recordingID: UUID) -> URL {
        root.appendingPathComponent(meetingID.uuidString, isDirectory: true)
            .appendingPathComponent(recordingID.uuidString, isDirectory: true)
            .appendingPathComponent("Screen Captures", isDirectory: true)
    }

    static func saved(in directory: URL) throws -> [Self] {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)
            return try files.compactMap { url in
                let parts = url.deletingPathExtension().lastPathComponent.split(separator: "_", maxSplits: 1)
                guard url.pathExtension == "jpg", parts.count == 2,
                      let offset = Int64(parts[0]), offset >= 0, let id = UUID(uuidString: String(parts[1])),
                      try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { return nil }
                return Self(id: id, offset: offset, url: url)
            }.sorted { ($0.offset, $0.id.uuidString) < ($1.offset, $1.id.uuidString) }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return []
        }
    }

    enum CaptureError: LocalizedError {
        case permission, noDisplay

        var errorDescription: String? {
            switch self {
            case .permission: "Allow screen recording in System Settings → Privacy & Security to save screen captures."
            case .noDisplay: "The main display is unavailable."
            }
        }
    }

    static func jpeg(timeline: RecordingCapture) async throws -> (data: Data, offset: Int64) {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw CaptureError.permission
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
            throw CaptureError.noDisplay
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = Int(filter.contentRect.width * scale)
        configuration.height = Int(filter.contentRect.height * scale)
        try Task.checkCancellation()
        let offset = timeline.currentTimelineOffset
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let data = try await Task.detached(priority: .utility) {
            let buffer = NSMutableData()
            guard let writer = CGImageDestinationCreateWithData(buffer, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
            return buffer as Data
        }.value
        return (data, offset)
    }
}

extension MeetingStore {
    func screenCaptures(meetingID: UUID, recordingID: UUID) throws -> [MeetingScreenCapture] {
        let directory = MeetingScreenCapture.directory(in: try recordingRoot(), meetingID: meetingID, recordingID: recordingID)
        return try MeetingScreenCapture.saved(in: directory)
    }

    func saveScreenCapture(_ data: Data, recording: Recording, offset: Int64) throws {
        try Task.checkCancellation()
        guard try recordings(for: recording.meetingID, includeActive: true).contains(where: {
            $0.id == recording.id && $0.endedAt == nil
        }) else { throw CancellationError() }
        let directory = MeetingScreenCapture.directory(in: try recordingRoot(), meetingID: recording.meetingID,
                                                        recordingID: recording.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("\(offset)_\(UUID().uuidString).jpg"), options: .atomic)
    }

    func screenCaptureEvidence(near match: ChatEvidence) throws -> [ChatEvidence] {
        let citation = match.citation
        let start = citation.startOffset
        let end = match.endOffset ?? start
        let captures = try screenCaptures(meetingID: citation.meetingID, recordingID: citation.recordingID)
        func distance(_ capture: MeetingScreenCapture) -> Int64 {
            max(start - capture.offset, capture.offset - end, 0)
        }
        return captures.filter { distance($0) <= 30_000_000_000 }
            .sorted { distance($0) < distance($1) }
            .prefix(2)
            .map { capture in
                ChatEvidence(title: match.title, body: "Screen capture reference",
                    citation: ChatCitation(meetingID: citation.meetingID, recordingID: citation.recordingID,
                        passageIDs: [], startOffset: capture.offset, revision: 0, screenCaptureID: capture.id))
            }
    }

    func screenCaptureURL(for citation: ChatCitation) throws -> URL? {
        guard let id = citation.screenCaptureID,
              try recordings(for: citation.meetingID, includeActive: true).contains(where: { $0.id == citation.recordingID })
        else { return nil }
        return try screenCaptures(meetingID: citation.meetingID, recordingID: citation.recordingID)
            .first { $0.id == id && $0.offset == citation.startOffset }?.url
    }

    func deleteScreenCapture(_ id: UUID, meetingID: UUID, recordingID: UUID) throws {
        if let capture = try screenCaptures(meetingID: meetingID, recordingID: recordingID).first(where: { $0.id == id }) {
            try FileManager.default.removeItem(at: capture.url)
        }
    }
}
