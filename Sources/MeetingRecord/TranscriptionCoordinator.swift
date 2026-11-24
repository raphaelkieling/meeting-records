import Combine
import Foundation

@MainActor
final class TranscriptionCoordinator: ObservableObject {
    @Published private(set) var revision = 0
    @Published private(set) var completionRevision = 0
    @Published private(set) var installed: Set<String> = []
    @Published private(set) var selected: TranscriptionModel = .large
    @Published private(set) var microphoneThreshold = 0.001
    @Published private(set) var downloading: TranscriptionModel?
    @Published private(set) var downloadedBytes: Int64 = 0
    @Published private(set) var error: String?

    private let store: MeetingStore
    private let engine = TranscriptionEngine()
    private let events = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private var worker: Task<Void, Never>?
    private var recordingsRoot: URL?
    private var queueLock: RecordingFileLock?
    private let selectionKey = "selectedTranscriptionModel"

    var isReady: Bool { installed.contains(selected.id) }
    var checkpointPublished: @Sendable () -> Void {
        let wakeup = events.continuation
        return { wakeup.yield(()) }
    }

    init(store: MeetingStore) {
        self.store = store
        if let id = UserDefaults.standard.string(forKey: selectionKey),
           let model = TranscriptionModel.catalog.first(where: { $0.id == id }) {
            selected = model
        }
        if let saved = UserDefaults.standard.object(forKey: "microphoneTranscriptionThreshold") as? Double,
           saved.isFinite {
            microphoneThreshold = min(1, max(0, saved))
        }
    }

    func start() async {
        do { try await startWorker() }
        catch { self.error = "Could not start transcription. \(error.localizedDescription)" }
    }

    private func startWorker() async throws {
        guard worker == nil else { return }
        let root = try await store.recordingRoot()
        let lock = try RecordingFileLock(root: modelsRoot(root))
        // Start after capture recovery so historical offsets are fully reconciled.
        try await store.resetTranscriptionQueue()
        queueLock = lock
        recordingsRoot = root
        installed = Set(TranscriptionModel.catalog.filter {
            FileManager.default.fileExists(atPath: TranscriptionEngine.folder(for: $0, root: modelsRoot(root)).path)
        }.map(\.id))
        revision += 1

        let stream = events.stream
        worker = Task { [weak self] in
            for await _ in stream { await self?.drain() }
        }
        events.continuation.yield(())
    }

    func select(_ model: TranscriptionModel) {
        guard installed.contains(model.id) else { return }
        selected = model
        UserDefaults.standard.set(model.id, forKey: selectionKey)
        Task { await retry(unstartedOnly: true) }
    }

    func setMicrophoneThreshold(_ value: Double) {
        microphoneThreshold = min(1, max(0, value))
        UserDefaults.standard.set(microphoneThreshold, forKey: "microphoneTranscriptionThreshold")
    }

    func download(_ model: TranscriptionModel) async {
        guard downloading == nil, let recordingsRoot else { return }
        downloading = model
        downloadedBytes = 0
        error = nil
        defer { downloading = nil }
        do {
            try await TranscriptionEngine.install(model, root: modelsRoot(recordingsRoot)) { [weak self] bytes in
                Task { @MainActor in
                    guard let self, self.downloading == model else { return }
                    guard bytes == model.downloadSize || bytes - self.downloadedBytes >= model.downloadSize / 200 else { return }
                    self.downloadedBytes = bytes
                }
            }
            let needsDefault = !isReady
            installed.insert(model.id)
            if needsDefault { select(model) }
            await retry()
        } catch {
            self.error = "Could not install \(model.name). \(error.localizedDescription)"
        }
    }

    func retry(unstartedOnly: Bool = false) async {
        do {
            // Keep the in-flight chunk claimed. Only clear failure markers during retry.
            try await store.retryDeferredTranscripts(unstartedOnly: unstartedOnly)
            revision += 1
            error = nil
            events.continuation.yield(())
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func modelsRoot(_ recordingsRoot: URL) -> URL {
        recordingsRoot.deletingLastPathComponent().appendingPathComponent("Models", isDirectory: true)
    }

    private func drain() async {
        guard let root = recordingsRoot else { return }
        do {
            while !Task.isCancelled {
                if try await store.finishDrainedTranscripts() {
                    revision += 1
                    completionRevision += 1
                }
                guard isReady, let work = try await store.nextTranscriptionWork() else { return }
                let id = work.audio.recordingID
                let pinned = work.modelID.flatMap { id in TranscriptionModel.catalog.first { $0.id == id } }
                let model = pinned ?? selected
                switch try await store.claimTranscript(id, model: model) {
                case .removed: continue
                case .changed: revision += 1
                case .unchanged: break
                }
                do {
                    guard installed.contains(model.id),
                          work.modelID == nil || (pinned != nil && work.modelVersion == model.version)
                    else { throw TranscriptionError.modelUnavailable }
                    let result = try await engine.transcribe(work.audioSegments,
                        urls: work.audioSegments.map { root.appendingPathComponent($0.relativePath) },
                        using: TranscriptionEngine.folder(for: model, root: modelsRoot(root)),
                        nemotronAsset: model.isNemotron ? model.files.first?.path : nil,
                        microphoneThreshold: microphoneThreshold)
                    try await store.saveTranscript(work.audioSegments, result: result)
                } catch {
                    try await store.deferTranscript(id, error: error.localizedDescription)
                }
                revision += 1
            }
        } catch {
            self.error = "Could not process the transcription queue. \(error.localizedDescription)"
        }
    }
}
