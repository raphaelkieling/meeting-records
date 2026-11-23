import Combine
import Foundation

@MainActor
final class RecordingCoordinator: ObservableObject {
    enum State: Equatable {
        case idle, starting(UUID), recording(UUID), finishing(UUID)

        var meetingID: UUID? {
            switch self {
            case .idle: nil
            case .starting(let id), .recording(let id), .finishing(let id): id
            }
        }
    }

    private struct Session {
        let recording: Recording
        let capture: RecordingCapture
        let storage: RecordingStorage
        let consumer: Task<Void, any Error>
        let lock: RecordingFileLock
    }

    let store = MeetingStore()
    @Published private(set) var state = State.idle
    @Published private(set) var revision = 0
    @Published var error: String?
    let levels = CurrentValueSubject<Double, Never>(0)
    private var session: Session?
    private var checkedRecovery = false

    func recover() async {
        guard !checkedRecovery, state == .idle else { return }
        checkedRecovery = true
        do {
            let root = try await store.recordingRoot()
            let lock = try RecordingFileLock(root: root)
            defer { withExtendedLifetime(lock) {} }
            try await RecordingStorage.recover(store: store, root: root)
            revision += 1
        } catch {
            self.error = "Could not check for interrupted recordings. \(error.localizedDescription)"
        }
    }

    func toggle(for meetingID: UUID) {
        switch state {
        case .idle:
            state = .starting(meetingID)
            error = nil
            Task { await start(meetingID: meetingID) }
        case .recording(let owner) where owner == meetingID:
            state = .finishing(meetingID)
            Task { await finish() }
        default:
            break
        }
    }

    private func start(meetingID: UUID) async {
        do {
            try await RecordingCapture.authorize()
            let root = try await store.recordingRoot()
            let lock = try RecordingFileLock(root: root)
            try await RecordingStorage.recover(store: store, root: root)
            revision += 1
            let recording = Recording(id: UUID(), meetingID: meetingID, startedAt: Date(), endedAt: nil, state: .starting)
            try await store.beginRecording(recording)
            let capture = RecordingCapture()
            do {
                try await capture.start()
                try await store.markRecordingStarted(recording.id)
            } catch {
                try? await capture.stop()
                _ = try? await store.finalizeRecording(recording.id, endedAt: Date(), interrupted: true)
                withExtendedLifetime(lock) {}
                throw error
            }

            let storage = RecordingStorage(store: store, root: root, recording: recording)
            let consumer = Task { [weak self] in
                var lastUpdate = ContinuousClock.now
                var peak = 0.0
                for try await sample in capture.samples {
                    peak = max(peak, try await storage.append(sample))
                    let now = ContinuousClock.now
                    if lastUpdate.duration(to: now) >= .milliseconds(75) {
                        self?.levels.send(peak)
                        lastUpdate = now
                        peak = 0
                    }
                }
            }
            session = Session(recording: recording, capture: capture, storage: storage, consumer: consumer, lock: lock)
            state = .recording(meetingID)
            Task {
                if case .failure(let error) = await consumer.result, state == .recording(meetingID) {
                    state = .finishing(meetingID)
                    await finish(cause: error)
                }
            }
        } catch {
            self.error = "Could not start recording. \(error.localizedDescription)"
            state = .idle
        }
    }

    private func finish(cause: (any Error)? = nil) async {
        guard let session else { return }
        var failure = cause
        do { try await session.capture.stop() }
        catch { failure = failure ?? error }
        if case .failure(let error) = await session.consumer.result { failure = failure ?? error }
        do { try await session.storage.finish() }
        catch { failure = failure ?? error }
        do {
            if failure != nil { try await session.storage.reconcile() }
            let saved = try await store.finalizeRecording(session.recording.id, endedAt: Date(), interrupted: failure != nil)
            if !saved, failure == nil { failure = RecordingError.emptyRecording }
        } catch {
            failure = error
        }
        if let failure { error = "Recording ended. \(failure.localizedDescription)" }
        self.session = nil
        levels.send(0)
        revision += 1
        state = .idle
    }
}
