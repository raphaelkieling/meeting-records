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

    static func recover(store: MeetingStore, root: URL) async throws {
        for recording in try await store.unfinishedRecordings() {
            let storage = RecordingStorage(store: store, root: root, recording: recording)
            try await storage.reconcile()
            try await store.finalizeRecording(recording.id, endedAt: Date(), interrupted: true)
        }
    }

    func append(_ sample: CapturedAudio) async throws -> Double {
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
        if let current = checkpoints[sample.source], Double(current.frames) / format.sampleRate >= 5 {
            try await publish(sample.source)
        }
        return level(of: pcm)
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
                    let frames = try AVAudioFile(forReading: url).length
                    if frames > 0 { try await register(url, source: source, start: start, frames: frames) }
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
        checkpoint.file = nil
        guard checkpoint.frames > 0 else {
            try FileManager.default.removeItem(at: checkpoint.temporary)
            return
        }
        let file = try FileHandle(forWritingTo: checkpoint.temporary)
        try file.synchronize()
        try file.close()
        try FileManager.default.moveItem(at: checkpoint.temporary, to: checkpoint.destination)
        try await register(checkpoint.destination, source: source, start: checkpoint.start, frames: checkpoint.frames)
    }

    private func register(_ url: URL, source: AudioSegment.Source, start: Int64, frames: Int64) async throws {
        let relativePath = [recording.meetingID.uuidString, recording.id.uuidString, source.rawValue, url.lastPathComponent]
            .joined(separator: "/")
        try await store.registerSegment(AudioSegment(recordingID: recording.id, source: source,
            startOffset: start, frameCount: frames, relativePath: relativePath))
        checkpointPublished()
    }

    private func level(of pcm: AVAudioPCMBuffer) -> Double {
        let channels = Int(pcm.format.channelCount)
        let stride = pcm.stride
        var peak = 0.0
        for channel in 0..<channels {
            for frame in Swift.stride(from: 0, to: Int(pcm.frameLength), by: 8) {
                let index = frame * stride
                if let samples = pcm.floatChannelData {
                    peak = max(peak, abs(Double(samples[channel][index])))
                } else if let samples = pcm.int16ChannelData {
                    peak = max(peak, abs(Double(samples[channel][index])) / 32_768)
                } else if let samples = pcm.int32ChannelData {
                    peak = max(peak, abs(Double(samples[channel][index])) / 2_147_483_648)
                }
            }
        }
        return min(1, peak)
    }
}
