import AVFoundation
import Combine
import Darwin
import Foundation

enum RecordingCompression {
    enum Failure: LocalizedError {
        case invalidAudio, invalidPath, durationChanged, didNotSaveSpace

        var errorDescription: String? {
            switch self {
            case .invalidAudio: "The original audio could not be decoded."
            case .invalidPath: "A recording file has an invalid path."
            case .durationChanged: "The compressed audio did not preserve the original timeline."
            case .didNotSaveSpace: "The compressed files would not save space."
            }
        }
    }

    static func run(store: MeetingStore, id: UUID, root: URL) async throws {
        let clips = try await store.audioSegments(for: id).filter { $0.relativePath.hasSuffix(".caf") }
        guard !clips.isEmpty else { return }
        var replacements: [String] = []
        var published: [URL] = []
        var committed = false
        defer {
            if !committed {
                for url in published { try? FileManager.default.removeItem(at: url) }
            }
        }

        var originalBytes = 0
        var compressedBytes = 0
        for clip in clips {
            try Task.checkCancellation()
            let original = try fileURL(clip.relativePath, root: root)
            let destination = original.deletingPathExtension().appendingPathExtension("m4a")
            let replacement = String(clip.relativePath.dropLast(3)) + "m4a"
            let sizes = try await encode(original, destination: destination, frames: clip.frameCount)
            originalBytes += sizes.original
            compressedBytes += sizes.compressed
            replacements.append(replacement)
            published.append(destination)
        }
        guard compressedBytes < originalBytes else { throw Failure.didNotSaveSpace }
        try Task.checkCancellation()

        do {
            let lock = try await waitForPlayback(root: root)
            defer { withExtendedLifetime(lock) {} }
            try await store.replaceRecordingAudio(id, originals: clips.map(\.relativePath), replacements: replacements)
            committed = true
        }
        try await cleanOriginals(store: store, root: root)
    }

    private static func waitForPlayback(root: URL) async throws -> RecordingFileLock {
        let directory = root.appendingPathComponent(".audio-access", isDirectory: true)
        while true {
            try Task.checkCancellation()
            do { return try RecordingFileLock(root: directory) }
            catch RecordingError.alreadyRecording { try await Task.sleep(for: .seconds(2)) }
        }
    }

    static func cleanOriginals(store: MeetingStore, root: URL) async throws {
        var removed: [String] = []
        var firstError: (any Error)?
        for path in try await store.pendingUncompressedAudio() {
            do {
                guard path.hasSuffix(".caf") else { throw Failure.invalidPath }
                let url = try fileURL(path, root: root)
                try removeIfPresent(url)
                removed.append(path)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        try await store.finishUncompressedAudioRemoval(removed)
        if let firstError { throw firstError }
    }

    private static func fileURL(_ path: String, root: URL) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw Failure.invalidPath
        }
        return root.appendingPathComponent(path)
    }

    private static func removeIfPresent(_ url: URL) throws {
        guard Darwin.unlink(url.path) != 0 else { return }
        let code = errno
        if code != ENOENT { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
    }

    private static func encode(_ source: URL, destination: URL, frames: Int64) async throws
        -> (original: Int, compressed: Int) {
        let input = try AVAudioFile(forReading: source)
        guard input.length == frames, frames > 0 else { throw Failure.invalidAudio }
        let format = input.processingFormat
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".compression.m4a")
        try removeIfPresent(temporary)
        defer { try? removeIfPresent(temporary) }
        try writeAAC(input: input, to: temporary)
        let decoded = try AVAudioFile(forReading: temporary)
        guard decoded.processingFormat.sampleRate == format.sampleRate,
              decoded.processingFormat.channelCount == format.channelCount, decoded.length == frames,
              let probe = AVAudioPCMBuffer(pcmFormat: decoded.processingFormat, frameCapacity: 1)
        else { throw Failure.durationChanged }
        try decoded.read(into: probe)
        guard probe.frameLength == 1 else { throw Failure.invalidAudio }
        decoded.framePosition = frames - 1
        try decoded.read(into: probe)
        guard probe.frameLength == 1 else { throw Failure.invalidAudio }

        let duration = Double(frames) / format.sampleRate
        let asset = AVURLAsset(url: temporary, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw Failure.invalidAudio }
        let range = try await track.load(.timeRange)
        guard abs(range.duration.seconds - duration) <= 0.001 else { throw Failure.durationChanged }

        let original = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let compressed = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        // A previous interrupted run can leave a destination that was never referenced by SQLite.
        try removeIfPresent(destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return (original, compressed)
    }

    private static func writeAAC(input: AVAudioFile, to url: URL) throws {
        let format = input.processingFormat
        let output = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: format.channelCount == 1 ? 64_000 : 96_000
        ], commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_768) else {
            throw Failure.invalidAudio
        }
        while input.framePosition < input.length {
            try Task.checkCancellation()
            try input.read(into: buffer)
            guard buffer.frameLength > 0 else { throw Failure.invalidAudio }
            try output.write(from: buffer)
        }
    }
}

@MainActor
final class RecordingCompressionCoordinator: ObservableObject {
    private static let automaticByDefault = false
    private static let enabledKey = "automaticRecordingCompression"
    private static let startKey = "automaticRecordingCompressionStart"

    let store: MeetingStore
    @Published private(set) var automaticEnabled =
        UserDefaults.standard.object(forKey: RecordingCompressionCoordinator.enabledKey) as? Bool
        ?? RecordingCompressionCoordinator.automaticByDefault
    @Published private(set) var progress: String?
    @Published private(set) var result: String?
    @Published private(set) var revision = 0
    private var worker: Task<Void, Never>?
    private var captureInProgress = false
    private var requestedManual = false
    private var requestedAutomatic = false
    private var automaticStart: Date?

    init(store: MeetingStore) {
        self.store = store
        automaticStart = UserDefaults.standard.object(forKey: Self.startKey) as? Date
        if automaticEnabled, automaticStart == nil { startAutomaticPolicy() }
    }

    func setAutomatic(_ enabled: Bool) {
        guard enabled != automaticEnabled else { return }
        automaticEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled {
            startAutomaticPolicy()
            enqueueAutomatic()
        }
    }

    private func startAutomaticPolicy() {
        let date = Date.now
        automaticStart = date
        UserDefaults.standard.set(date, forKey: Self.startKey)
    }

    func enqueueAutomatic() {
        guard automaticEnabled else { return }
        requestedAutomatic = true
        startWorker()
    }

    func compactExisting() {
        requestedManual = true
        startWorker()
    }

    func pauseForCapture() async {
        captureInProgress = true
        guard let worker else { return }
        worker.cancel()
        await worker.value
    }

    func resumeAfterCapture() {
        captureInProgress = false
        enqueueAutomatic()
        if requestedManual { startWorker() }
    }

    func recover() async {
        do {
            guard try await !store.pendingUncompressedAudio().isEmpty else { return }
            let root = try await store.recordingRoot()
            let lock = try RecordingFileLock(root: root.appendingPathComponent(".compression", isDirectory: true))
            defer { withExtendedLifetime(lock) {} }
            try await RecordingCompression.cleanOriginals(store: store, root: root)
            revision += 1
        } catch RecordingError.alreadyRecording {
        } catch {
            result = "Could not finish removing original audio. \(error.localizedDescription)"
        }
    }

    private func startWorker() {
        guard !captureInProgress, worker == nil else { return }
        result = nil
        progress = "Checking recordings…"
        worker = Task(priority: .utility) { [weak self] in await self?.processQueue() }
    }

    private func processQueue() async {
        defer {
            worker = nil
            progress = nil
        }
        var interruptedManual = false
        var interruptedAutomatic = false
        do {
            let root = try await store.recordingRoot()
            try Task.checkCancellation()
            let lock = try RecordingFileLock(root: root.appendingPathComponent(".compression", isDirectory: true))
            defer { withExtendedLifetime(lock) {} }
            try await RecordingCompression.cleanOriginals(store: store, root: root)
            revision += 1
            while requestedManual || requestedAutomatic {
                try Task.checkCancellation()
                let manual = requestedManual
                interruptedManual = manual
                interruptedAutomatic = requestedAutomatic
                requestedManual = false
                requestedAutomatic = false
                guard manual || automaticEnabled else { continue }
                let candidates = try await store.compressibleRecordings(endedAfter: manual ? nil : automaticStart)
                var count = 0
                var failures = 0
                var lastError: String?
                for (index, id) in candidates.enumerated() {
                    try Task.checkCancellation()
                    guard manual || automaticEnabled else { break }
                    progress = "Compacting recording \(index + 1) of \(candidates.count)…"
                    do {
                        try await RecordingCompression.run(store: store, id: id, root: root)
                        count += 1
                        revision += 1
                    } catch {
                        try Task.checkCancellation()
                        failures += 1
                        lastError = error.localizedDescription
                    }
                }
                if failures > 0 {
                    result = "Compacted \(count) of \(candidates.count) recordings. \(lastError ?? "")"
                } else if count > 0 {
                    result = count == 1 ? "Compacted 1 recording." : "Compacted \(count) recordings."
                } else if manual {
                    result = "No transcribed recordings to compact."
                }
                interruptedManual = false
                interruptedAutomatic = false
            }
        } catch is CancellationError {
            requestedManual = requestedManual || interruptedManual
            requestedAutomatic = requestedAutomatic || interruptedAutomatic
        } catch {
            requestedManual = false
            requestedAutomatic = false
            result = "Could not compact audio. \(error.localizedDescription)"
        }
    }
}
