import AVFoundation
import Darwin

// Recovery and capture share this lock so another process cannot recover a live session.
final class RecordingFileLock: Sendable {
    private let descriptor: Int32

    init(root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let descriptor = Darwin.open(root.appendingPathComponent(".capture-lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            if code == EWOULDBLOCK { throw RecordingError.alreadyRecording }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        self.descriptor = descriptor
    }

    deinit { close(descriptor) }
}

actor RecordingStorage {
    private struct Checkpoint {
        var file: AVAudioFile?
        let temporary: URL
        let destination: URL
        let start: Int64
        var frames: Int64 = 0

        var expectedOffset: Int64 {
            guard let file else { return start }
            return start + Int64((Double(frames) / file.processingFormat.sampleRate * 1e9).rounded())
        }
    }

    private let store: MeetingStore
    private let root: URL
    private let recording: Recording
    private let checkpointPublished: @Sendable () -> Void
    private var checkpoints: [AudioSegment.Source: Checkpoint] = [:]

    init(store: MeetingStore, root: URL, recording: Recording, checkpointPublished: @escaping @Sendable () -> Void = {}) {
        self.store = store
        self.root = root
        self.recording = recording
        self.checkpointPublished = checkpointPublished
    }

    @discardableResult
    static func finishMeetingDeletions(store: MeetingStore) async throws -> Bool {
        if try await store.pendingMeetingDeletions().isEmpty,
           try await store.pendingRecordingDeletions().isEmpty { return false }
        let root = try await store.recordingRoot()
        let lock = try RecordingFileLock(root: root.appendingPathComponent(".deletions", isDirectory: true))
        defer { withExtendedLifetime(lock) {} }
        let meetings = try await store.pendingMeetingDeletions()
        let recordings = try await store.pendingRecordingDeletions()
        var firstError: (any Error)?
        for id in meetings {
            do {
                try removeAudioDirectory(root.appendingPathComponent(id.uuidString, isDirectory: true))
                try await store.finishMeetingDeletion(id)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        for removal in recordings {
            do {
                let directory = root.appendingPathComponent(removal.meetingID.uuidString, isDirectory: true)
                    .appendingPathComponent(removal.recordingID.uuidString, isDirectory: true)
                try removeAudioDirectory(directory)
                try await store.finishRecordingDeletion(removal.recordingID)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
        return !meetings.isEmpty || !recordings.isEmpty
    }

    private static func removeAudioDirectory(_ directory: URL) throws {
        do { try FileManager.default.removeItem(at: directory) }
        catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {}
    }

    static func bytesUsed(at root: URL) async throws -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        var enumerationError: (any Error)?
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys),
                                                   options: .skipsHiddenFiles) { _, error in
            let code = (error as? CocoaError)?.code
            if code == .fileReadNoSuchFile || code == .fileNoSuchFile { return true }
            enumerationError = error
            return false
        }
        var bytes: Int64 = 0
        while let url = files?.nextObject() as? URL {
            try Task.checkCancellation()
            guard url.pathExtension == "caf" else { continue }
            do {
                let values = try url.resourceValues(forKeys: keys)
                if values.isRegularFile == true {
                    bytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                }
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {}
        }
        if let enumerationError { throw enumerationError }
        return bytes
    }

    static func recover(store: MeetingStore, root: URL) async throws {
        for recording in try await store.unfinishedRecordings() {
            let storage = RecordingStorage(store: store, root: root, recording: recording)
            try await storage.reconcile()
            try await store.finalizeRecording(recording.id, endedAt: Date(), interrupted: true)
        }
    }

    struct InputLevels: Sendable {
        let peak: Double
        let rms: Double
    }

    func append(_ sample: CapturedAudio) async throws -> InputLevels {
        guard let description = sample.buffer.formatDescription,
              let count = Int32(exactly: sample.buffer.numSamples), count > 0
        else { throw RecordingError.invalidAudio }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard format.sampleRate.isFinite, format.sampleRate > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(count))
        else { throw RecordingError.invalidAudio }
        pcm.frameLength = UInt32(count)
        let result = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sample.buffer, at: 0, frameCount: count, into: pcm.mutableAudioBufferList
        )
        guard result == noErr else { throw RecordingError.invalidAudio }

        if let current = checkpoints[sample.source],
           current.file?.processingFormat != format || abs(current.expectedOffset - sample.startOffset) > 250_000 {
            try await publish(sample.source)
        }
        if checkpoints[sample.source] == nil {
            checkpoints[sample.source] = try openCheckpoint(source: sample.source, start: sample.startOffset, format: format)
        }
        do {
            try checkpoints[sample.source]?.file?.write(from: pcm)
        } catch {
            if var incomplete = checkpoints.removeValue(forKey: sample.source) {
                incomplete.file = nil
                try? FileManager.default.removeItem(at: incomplete.temporary)
            }
            throw error
        }
        checkpoints[sample.source]?.frames += Int64(count)
        if let current = checkpoints[sample.source], Double(current.frames) / format.sampleRate >= 10 {
            try await publish(sample.source)
        }
        return levels(of: pcm)
    }

    func finish() async throws {
        var failure: (any Error)?
        for source in AudioSegment.Source.allCases {
            do { try await publish(source) }
            catch { if failure == nil { failure = error } }
        }
        if let failure { throw failure }
    }

    func reconcile() async throws {
        for source in AudioSegment.Source.allCases {
            let urls: [URL]
            let directory = directory(for: source)
            do {
                guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
                urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                continue
            }
            for url in urls where url.pathExtension == "caf" {
                let stem = url.deletingPathExtension().lastPathComponent
                if stem.hasSuffix(".partial") {
                    try? FileManager.default.removeItem(at: url)
                } else if let start = Int64(stem), start >= 0 {
                    let file = try AVAudioFile(forReading: url)
                    if file.length > 0 {
                        try await register(url, source: source, start: start, frames: file.length,
                                           sampleRate: file.processingFormat.sampleRate)
                    }
                }
            }
        }
    }

    private func directory(for source: AudioSegment.Source) -> URL {
        root.appendingPathComponent(recording.meetingID.uuidString, isDirectory: true)
            .appendingPathComponent(recording.id.uuidString, isDirectory: true)
            .appendingPathComponent(source.rawValue, isDirectory: true)
    }

    private func openCheckpoint(source: AudioSegment.Source, start: Int64, format: AVAudioFormat) throws -> Checkpoint {
        let directory = directory(for: source)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent("\(start).partial.caf")
        let destination = directory.appendingPathComponent("\(start).caf")
        let file = try AVAudioFile(forWriting: temporary, settings: format.settings,
                                   commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        return Checkpoint(file: file, temporary: temporary, destination: destination, start: start)
    }

    private func publish(_ source: AudioSegment.Source) async throws {
        guard var checkpoint = checkpoints.removeValue(forKey: source) else { return }
        let sampleRate = checkpoint.file?.processingFormat.sampleRate ?? 0
        checkpoint.file = nil
        guard checkpoint.frames > 0 else {
            try FileManager.default.removeItem(at: checkpoint.temporary)
            return
        }
        let file = try FileHandle(forWritingTo: checkpoint.temporary)
        try file.synchronize()
        try file.close()
        try FileManager.default.moveItem(at: checkpoint.temporary, to: checkpoint.destination)
        try await register(checkpoint.destination, source: source, start: checkpoint.start, frames: checkpoint.frames, sampleRate: sampleRate)
    }

    private func register(_ url: URL, source: AudioSegment.Source, start: Int64, frames: Int64, sampleRate: Double) async throws {
        let relativePath = [recording.meetingID.uuidString, recording.id.uuidString, source.rawValue, url.lastPathComponent]
            .joined(separator: "/")
        try await store.registerSegment(AudioSegment(recordingID: recording.id, source: source,
            startOffset: start, frameCount: frames, relativePath: relativePath), duration: Double(frames) / sampleRate)
        checkpointPublished()
    }

    private func levels(of pcm: AVAudioPCMBuffer) -> InputLevels {
        let channels = Int(pcm.format.channelCount)
        let stride = pcm.stride
        var peak = 0.0
        var squareSum = 0.0
        var sampleCount = 0
        for channel in 0..<channels {
            for frame in 0..<Int(pcm.frameLength) {
                let index = frame * stride
                let value: Double
                if let samples = pcm.floatChannelData {
                    value = Double(samples[channel][index])
                } else if let samples = pcm.int16ChannelData {
                    value = Double(samples[channel][index]) / 32_768
                } else if let samples = pcm.int32ChannelData {
                    value = Double(samples[channel][index]) / 2_147_483_648
                } else {
                    continue
                }
                peak = max(peak, abs(value))
                squareSum += value * value
                sampleCount += 1
            }
        }
        return InputLevels(peak: min(1, peak), rms: sampleCount > 0 ? min(1, sqrt(squareSum / Double(sampleCount))) : 0)
    }
}
