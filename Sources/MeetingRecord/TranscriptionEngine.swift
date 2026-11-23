import AVFoundation
import Foundation
import WhisperKit

enum TranscriptionError: LocalizedError {
    case modelUnavailable
    case invalidDownload(String, Int?)
    case engineBusy

    var errorDescription: String? {
        switch self {
        case .modelUnavailable: "The transcription model for this recording is unavailable."
        case .engineBusy: "The transcription engine is already processing audio."
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
    private var isProcessing = false

    func transcribe(_ audio: AudioSegment, at url: URL, using modelFolder: URL) async throws -> TranscribedCheckpoint {
        guard !isProcessing else { throw TranscriptionError.engineBusy }
        isProcessing = true
        defer { isProcessing = false }

        let file = try AVAudioFile(forReading: url)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        let checkpointEnd = audio.startOffset + Int64((duration * 1e9).rounded())
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
        // Use a low peak threshold so quiet speech can still reach the model.
        guard samples.contains(where: { abs($0) >= 0.001 }) else {
            return TranscribedCheckpoint(processedThrough: checkpointEnd, segments: [])
        }

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
