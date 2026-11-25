import AVFoundation
import CTranscribe
import Foundation
import WhisperKit

enum TranscriptionError: LocalizedError {
    case modelUnavailable
    case invalidDownload(String, Int?)
    case engineBusy
    case nemotronFailed(UInt32)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable: "The transcription model for this recording is unavailable."
        case .engineBusy: "The transcription engine is already processing audio."
        case .nemotronFailed(let code): "Nemotron could not transcribe this audio (code \(code))."
        case .invalidDownload(let name, let status):
            if let status, status != 200 { "Could not download \(name) (HTTP \(status))." }
            else { "The download for \(name) was incomplete." }
        }
    }
}

actor TranscriptionEngine {
    // WhisperKit 0.15 is mutable and has no Sendable conformance. The actor's
    // in-flight guard keeps all calls serialized across suspension points.
    private struct LoadedModel: @unchecked Sendable {
        let folder: URL
        let engine: WhisperKit
    }

    private var loaded: LoadedModel?
    private var nemotron: NemotronSession?
    private var isProcessing = false

    func unloadNemotron() {
        nemotron = nil
    }

    func transcribe(_ audio: AudioSegment, at url: URL, using modelFolder: URL,
                    microphoneThreshold: Double = 0.001) async throws -> TranscribedCheckpoint {
        try await transcribe([audio], urls: [url], using: modelFolder, microphoneThreshold: microphoneThreshold)
    }

    func transcribe(_ audioSegments: [AudioSegment], urls: [URL], using modelFolder: URL,
                    nemotronAsset: String? = nil,
                    microphoneThreshold: Double = 0.001) async throws -> TranscribedCheckpoint {
        guard !isProcessing else { throw TranscriptionError.engineBusy }
        guard let audio = audioSegments.first, audioSegments.count == urls.count else {
            throw RecordingError.invalidAudio
        }
        isProcessing = true
        defer { isProcessing = false }

        var samples: [Float] = []
        let sampleRate = 16_000
        for (segment, url) in zip(audioSegments, urls) {
            let file = try AVAudioFile(forReading: url)
            let duration = Double(file.length) / file.processingFormat.sampleRate
            let endOffset = segment.startOffset + Int64((duration * 1e9).rounded())
            let targetEnd = Int((Double(endOffset - audio.startOffset) / 1e9 * Double(sampleRate)).rounded())
            let targetStart = Int((Double(segment.startOffset - audio.startOffset) / 1e9 * Double(sampleRate)).rounded())
            guard targetStart >= 0, targetEnd >= targetStart else { throw RecordingError.invalidAudio }
            if samples.count < targetStart { samples.append(contentsOf: repeatElement(0, count: targetStart - samples.count)) }
            let decoded = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
            if samples.count < targetEnd { samples.append(contentsOf: repeatElement(0, count: targetEnd - samples.count)) }
            let count = min(decoded.count, targetEnd - targetStart)
            if count > 0 { samples.replaceSubrange(targetStart..<(targetStart + count), with: decoded.prefix(count)) }
        }
        let duration = Double(samples.count) / Double(sampleRate)
        let checkpointEnd = audio.startOffset + Int64((duration * 1e9).rounded())
        guard let selected = Self.selectedSamples(samples, source: audio.source, threshold: microphoneThreshold) else {
            return TranscribedCheckpoint(processedThrough: checkpointEnd, segments: [])
        }
        samples = selected

        if let nemotronAsset {
            loaded = nil
            let weights = modelFolder.appendingPathComponent(nemotronAsset)
            if nemotron?.weights != weights { nemotron = try NemotronSession(weights: weights) }
            guard let nemotron else { throw TranscriptionError.modelUnavailable }
            return try nemotron.transcribe(samples, start: audio.startOffset, end: checkpointEnd)
        }
        nemotron = nil
        if loaded?.folder != modelFolder {
            loaded = nil
            guard FileManager.default.fileExists(atPath: modelFolder.appendingPathComponent("tokenizer.json").path),
                  FileManager.default.fileExists(atPath: modelFolder.appendingPathComponent("tokenizer_config.json").path)
            else { throw TranscriptionError.modelUnavailable }
            let engine = try await WhisperKit(WhisperKitConfig(modelFolder: modelFolder.path,
                tokenizerFolder: modelFolder, load: true, download: false))
            loaded = LoadedModel(folder: modelFolder, engine: engine)
        }
        guard let model = loaded else { throw TranscriptionError.modelUnavailable }

        let results: [TranscriptionResult] = try await model.engine.transcribe(audioArray: samples,
            decodeOptions: DecodingOptions(detectLanguage: true, skipSpecialTokens: true))
        let segments: [TranscribedCheckpoint.Segment] = results.flatMap(\.segments).compactMap { segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard TranscriptPassage.hasWords(text), segment.start.isFinite, segment.end.isFinite else { return nil }
            let start = min(duration, max(0, Double(segment.start)))
            let end = min(duration, max(start, Double(segment.end)))
            guard end > start else { return nil }
            return .init(startOffset: audio.startOffset + Int64(start * 1e9),
                         endOffset: audio.startOffset + Int64(end * 1e9), text: text)
        }
        return TranscribedCheckpoint(processedThrough: checkpointEnd, segments: segments)
    }

    static func selectedSamples(_ samples: [Float], source: AudioSegment.Source,
                                threshold: Double) -> [Float]? {
        guard source == .me else { return samples.contains(where: { abs($0) >= 0.001 }) ? samples : nil }
        return selectMicrophoneIntervals(samples, threshold: threshold)
    }

    static func selectMicrophoneIntervals(_ samples: [Float], threshold: Double,
                                          sampleRate: Int = 16_000, context: Double = 0.2) -> [Float]? {
        guard !samples.isEmpty, sampleRate > 0 else { return nil }
        let boundedThreshold = min(1, max(0.001, threshold))
        let window = max(1, sampleRate / 10)
        var eligible = [Bool](repeating: false, count: samples.count)
        let margin = Int(context * Double(sampleRate))
        for start in stride(from: 0, to: samples.count, by: window) {
            let end = min(samples.count, start + window)
            let rms = sqrt(samples[start..<end].reduce(0.0) { $0 + Double($1) * Double($1) } / Double(end - start))
            if rms >= boundedThreshold {
                let from = max(0, start - margin)
                let through = min(samples.count, end + margin)
                eligible.replaceSubrange(from..<through, with: repeatElement(true, count: through - from))
            }
        }
        guard eligible.contains(true) else { return nil }
        var selected = samples
        for index in eligible.indices where !eligible[index] { selected[index] = 0 }
        return selected
    }

    static func folder(for model: TranscriptionModel, root: URL) -> URL {
        root.appendingPathComponent(model.id, isDirectory: true)
            .appendingPathComponent(model.version, isDirectory: true)
    }

    static func install(_ model: TranscriptionModel, root: URL,
                        progress: @escaping @Sendable (Int64) -> Void) async throws {
        let fm = FileManager.default
        let destination = folder(for: model, root: root)
        if fm.fileExists(atPath: destination.path) { return }
        let temporary = root.appendingPathComponent(".\(model.id).partial", isDirectory: true)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 60 * 60
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var downloaded: Int64 = 0
        for asset in model.files {
            let local = temporary.appendingPathComponent(asset.path)
            let localSize = try? local.resourceValues(forKeys: [.fileSizeKey]).fileSize
            if localSize.map(Int64.init) != asset.bytes {
                if fm.fileExists(atPath: local.path) { try fm.removeItem(at: local) }
                try fm.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
                let previous = downloaded
                try await download(asset, from: model.url(for: asset), to: local, session: session) { bytes in
                    progress(previous + min(asset.bytes, bytes))
                }
            }
            downloaded += asset.bytes
            progress(downloaded)
        }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: destination.path) {
            try fm.moveItem(at: temporary, to: destination)
        }
    }

    private static func download(_ asset: TranscriptionModel.Asset, from remote: URL, to destination: URL,
                                 session: URLSession, progress: @escaping @Sendable (Int64) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let task = session.downloadTask(with: remote) { file, response, error in
                do {
                    if let error { throw error }
                    let status = (response as? HTTPURLResponse)?.statusCode
                    guard let file, status == 200,
                          try file.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) == asset.bytes
                    else { throw TranscriptionError.invalidDownload(asset.path, status) }
                    try FileManager.default.moveItem(at: file, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            task.resume()
            // Completion-handler downloads provide byte counts on the task even when
            // Foundation does not call a progress delegate.
            Task {
                while task.state == .running {
                    progress(task.countOfBytesReceived)
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
    }
}

private final class NemotronSession {
    let weights: URL
    private let session: OpaquePointer

    init(weights: URL) throws {
        var handle: OpaquePointer?
        let status = transcribe_open(weights.path, nil, nil, &handle)
        guard status == TRANSCRIBE_OK, let handle else {
            throw TranscriptionError.nemotronFailed(status.rawValue)
        }
        self.weights = weights
        session = handle
    }

    deinit { transcribe_session_free(session) }

    func transcribe(_ samples: [Float], start: Int64, end: Int64) throws -> TranscribedCheckpoint {
        guard let count = Int32(exactly: samples.count) else { throw RecordingError.invalidAudio }
        var parameters = transcribe_run_params()
        transcribe_run_params_init(&parameters)
        parameters.timestamps = TRANSCRIBE_TIMESTAMPS_WORD
        let status = transcribe_run(session, samples, count, &parameters)
        guard status == TRANSCRIBE_OK else { throw TranscriptionError.nemotronFailed(status.rawValue) }
        let text = transcribe_full_text(session).map { String(cString: $0) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let words = transcribe_n_words(session)
        guard TranscriptPassage.hasWords(text) else { return .init(processedThrough: end, segments: []) }

        var first = transcribe_word()
        var last = transcribe_word()
        transcribe_word_init(&first)
        transcribe_word_init(&last)
        let hasTiming = words > 0 && transcribe_get_word(session, 0, &first) == TRANSCRIBE_OK
            && transcribe_get_word(session, words - 1, &last) == TRANSCRIBE_OK
        let duration = end - start
        let from = hasTiming ? min(duration / 1_000_000, max(0, first.t0_ms)) * 1_000_000 : 0
        let through = hasTiming ? min(duration / 1_000_000, max(0, last.t1_ms)) * 1_000_000 : duration
        let segment = through > from
            ? TranscribedCheckpoint.Segment(startOffset: start + from, endOffset: start + through, text: text)
            : TranscribedCheckpoint.Segment(startOffset: start, endOffset: end, text: text)
        return .init(processedThrough: end, segments: [segment])
    }
}
