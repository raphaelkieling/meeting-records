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

    let store: MeetingStore
    let transcription: TranscriptionCoordinator
    let summaries: MeetingSummaryCoordinator
    lazy var chat = MeetingChatCoordinator(store: store)

    init() {
        let store = MeetingStore()
        self.store = store
        self.transcription = TranscriptionCoordinator(store: store)
        self.summaries = MeetingSummaryCoordinator(store: store)
    }
    @Published private(set) var state = State.idle
    @Published private(set) var revision = 0
    @Published var error: String?
    @Published var cleanupError: String?
    @Published private var deletingMeetings: Set<UUID> = []
    private var isCleaningUp = false
    private var cleanupRequested = false
    let levels = CurrentValueSubject<Double, Never>(0)
    let microphoneRMS = CurrentValueSubject<Double, Never>(0)
    private var session: Session?
    private var checkedRecovery = false
    @Published private(set) var microphoneID = UserDefaults.standard.string(forKey: "selectedMicrophoneID") ?? ""
    private var microphoneMeter: RecordingCapture?

    func selectMicrophone(_ id: String) {
        microphoneID = id
        UserDefaults.standard.set(id, forKey: "selectedMicrophoneID")
        stopMicrophoneMeter()
        if state == .idle { microphoneRMS.send(0) }
        if microphoneMeterRequested { Task { await startMicrophoneMeterIfNeeded() } }
    }

    private var microphoneMeterStop: Task<Void, Never>?
    private var microphoneMeterRequested = false

    func setMicrophoneMetering(_ enabled: Bool) {
        microphoneMeterRequested = enabled
        if enabled {
            Task { await startMicrophoneMeterIfNeeded() }
            return
        }
        stopMicrophoneMeter()
        if state == .idle { microphoneRMS.send(0) }
    }

    private func stopMicrophoneMeter() {
        guard let meter = microphoneMeter else { return }
        microphoneMeter = nil
        microphoneMeterStop = Task { try? await meter.stop() }
    }

    private func startMicrophoneMeterIfNeeded() async {
        await microphoneMeterStop?.value
        guard microphoneMeterRequested, state == .idle, microphoneMeter == nil else { return }
        let meter = RecordingCapture()
        microphoneMeter = meter
        do {
            try await meter.startMicrophone(id: microphoneID) { [weak self, weak meter] level in
                Task { @MainActor in
                    guard let self, let meter, self.microphoneMeter === meter,
                          self.microphoneMeterRequested, self.state == .idle else { return }
                    self.microphoneRMS.send(level)
                }
            }
        } catch {
            guard microphoneMeter === meter else { return }
            stopMicrophoneMeter()
            self.error = "Could not monitor the microphone. \(error.localizedDescription)"
        }
    }

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
            return
        }
        await transcription.start()
    }

    func isDeleting(_ id: UUID) -> Bool { deletingMeetings.contains(id) }

    func canDelete(_ id: UUID) -> Bool {
        state.meetingID != id && !isDeleting(id)
    }

    func deleteMeeting(_ id: UUID) async throws {
        guard canDelete(id) else { throw MeetingStoreError.meetingRecording }
        deletingMeetings.insert(id)
        defer { deletingMeetings.remove(id) }
        try await store.deleteMeeting(id)
        summaries.cancel(for: id)
        chat.meetingsDeleted([id])
    }

    func deleteAllMeetings() async throws {
        guard state == .idle, deletingMeetings.isEmpty else { throw RecordingError.alreadyRecording }
        let deletedIDs = try await store.deleteAllMeetings()
        for id in deletedIDs { summaries.cancel(for: id) }
        chat.meetingsDeleted(Set(deletedIDs))
        revision += 1
    }

    func finishMeetingDeletions() async {
        cleanupRequested = true
        guard !isCleaningUp else { return }
        isCleaningUp = true
        defer { isCleaningUp = false }
        while cleanupRequested {
            cleanupRequested = false
            do {
                try await RecordingStorage.finishMeetingDeletions(store: store)
                cleanupError = nil
            } catch {
                cleanupError = error.localizedDescription
            }
        }
    }

    func toggle(for meetingID: UUID) {
        switch state {
        case .idle:
            guard transcription.isReady, !deletingMeetings.contains(meetingID) else { return }
            state = .starting(meetingID)
            error = nil
            Task {
                stopMicrophoneMeter()
                await microphoneMeterStop?.value
                await start(meetingID: meetingID)
            }
        case .recording(let owner) where owner == meetingID:
            stop()
        default:
            break
        }
    }

    func stop() {
        guard case .recording(let meetingID) = state else { return }
        state = .finishing(meetingID)
        Task { await finish() }
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
                try await capture.start(microphoneID: microphoneID)
                try await store.markRecordingStarted(recording.id)
            } catch {
                try? await capture.stop()
                _ = try? await store.finalizeRecording(recording.id, endedAt: Date(), interrupted: true)
                withExtendedLifetime(lock) {}
                throw error
            }

            let storage = RecordingStorage(store: store, root: root, recording: recording,
                                           checkpointPublished: transcription.checkpointPublished)
            let consumer = Task { [weak self] in
                var lastUpdate = ContinuousClock.now
                var peak = 0.0
                var rms = 0.0
                for try await sample in capture.samples {
                    let input = try await storage.append(sample)
                    peak = max(peak, input.peak)
                    if sample.source == .me { rms = input.rms }
                    let now = ContinuousClock.now
                    if lastUpdate.duration(to: now) >= .milliseconds(75) {
                        self?.levels.send(peak)
                        self?.microphoneRMS.send(rms)
                        lastUpdate = now
                        peak = 0
                    }
                }
            }
            session = Session(recording: recording, capture: capture, storage: storage, consumer: consumer, lock: lock)
            state = .recording(meetingID)
            revision += 1
            Task {
                if case .failure(let error) = await consumer.result, state == .recording(meetingID) {
                    state = .finishing(meetingID)
                    await finish(cause: error)
                }
            }
        } catch {
            self.error = "Could not start recording. \(error.localizedDescription)"
            state = .idle
            await startMicrophoneMeterIfNeeded()
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
        microphoneRMS.send(0)
        revision += 1
        state = .idle
        await startMicrophoneMeterIfNeeded()
        transcription.checkpointPublished()
    }
}
