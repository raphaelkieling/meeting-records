import Combine
import Foundation
import os

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
        let meters: Task<Void, Never>
        let lock: RecordingFileLock
    }

    let store: MeetingStore
    let transcription: TranscriptionCoordinator
    let summaries: MeetingSummaryCoordinator
    let compression: RecordingCompressionCoordinator
    lazy var chat = MeetingChatCoordinator(store: store)

    init() {
        let store = MeetingStore()
        self.store = store
        self.transcription = TranscriptionCoordinator(store: store)
        self.summaries = MeetingSummaryCoordinator(store: store)
        self.compression = RecordingCompressionCoordinator(store: store)
    }
    @Published private(set) var state = State.idle
    @Published private(set) var revision = 0
    @Published var error: String?
    @Published var screenCaptureError: String?
    @Published private(set) var cleanupError: String?
    @Published private var deletingMeetings: Set<UUID> = []
    private var isCleaningUp = false
    private var cleanupRequested = false
    let levels = CurrentValueSubject<Double, Never>(0)
    let microphoneRMS = CurrentValueSubject<Double, Never>(0)
    private var session: Session?
    private var screenCaptureTimer: Task<Void, Never>?
    private var manualScreenCapture: Task<Void, Never>?
    @Published private(set) var automaticScreenCaptures = UserDefaults.standard.bool(forKey: "automaticScreenCaptures")
    @Published private(set) var screenCaptureInterval = (1...60).contains(UserDefaults.standard.integer(forKey: "screenCaptureInterval"))
        ? UserDefaults.standard.integer(forKey: "screenCaptureInterval") : 10

    func setAutomaticScreenCaptures(_ enabled: Bool) {
        automaticScreenCaptures = enabled
        UserDefaults.standard.set(enabled, forKey: "automaticScreenCaptures")
        scheduleScreenCaptures()
    }

    func setScreenCaptureInterval(_ minutes: Int) {
        screenCaptureInterval = min(60, max(1, minutes))
        UserDefaults.standard.set(screenCaptureInterval, forKey: "screenCaptureInterval")
        scheduleScreenCaptures()
    }

    private func scheduleScreenCaptures() {
        screenCaptureTimer?.cancel()
        screenCaptureTimer = nil
        guard automaticScreenCaptures, case .recording = state else { return }
        let interval = Duration.seconds(screenCaptureInterval * 60)
        screenCaptureTimer = Task { [weak self] in
            let clock = ContinuousClock()
            var deadline = clock.now.advanced(by: interval)
            while !Task.isCancelled {
                do { try await clock.sleep(until: deadline) }
                catch { return }
                await self?.captureScreen()
                repeat { deadline = deadline.advanced(by: interval) } while deadline <= clock.now
            }
        }
    }

    func takeScreenCapture() {
        guard manualScreenCapture == nil else { return }
        manualScreenCapture = Task { [weak self] in
            await self?.captureScreen()
            self?.manualScreenCapture = nil
        }
    }

    private func captureScreen() async {
        guard case .recording = state, let session, !Task.isCancelled else { return }
        let recording = session.recording
        do {
            let shot = try await MeetingScreenCapture.jpeg(timeline: session.capture)
            guard self.session?.recording.id == recording.id else { return }
            try await store.saveScreenCapture(shot.data, recording: recording, offset: shot.offset)
            revision += 1
        } catch is CancellationError {
        } catch {
            guard self.session?.recording.id == recording.id, !Task.isCancelled else { return }
            screenCaptureError = "Could not capture the screen. \(error.localizedDescription)"
        }
    }

    func deleteScreenCapture(_ id: UUID, meetingID: UUID, recordingID: UUID) async throws {
        try await store.deleteScreenCapture(id, meetingID: meetingID, recordingID: recordingID)
        revision += 1
    }

    private var autoStopMonitor: Task<Void, Never>?
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
            await finishMeetingDeletions()
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

    func deleteRecording(_ recording: Recording) async throws {
        try await store.deleteRecording(recording)
        summaries.cancel(for: recording.meetingID)
        chat.recordingDeleted(recording.id)
        revision += 1
        await finishMeetingDeletions()
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
                if try await RecordingStorage.finishMeetingDeletions(store: store) { revision += 1 }
                cleanupError = nil
            } catch MeetingStoreError.incompatibleVersion {
                // Library loading already shows this error. Retrying file cleanup cannot resolve it.
                cleanupError = nil
            } catch {
                cleanupError = error.localizedDescription
            }
        }
    }

    func toggle(for meetingID: UUID) {
        switch state {
        case .idle:
            guard !deletingMeetings.contains(meetingID) else { return }
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
        await compression.pauseForCapture()
        do {
            try await RecordingCapture.authorize()
            let root = try await store.recordingRoot()
            let lock = try RecordingFileLock(root: root)
            try await RecordingStorage.recover(store: store, root: root)
            await finishMeetingDeletions()
            revision += 1
            let scheduledEnd = try? await store.scheduledEnd(for: meetingID)
            let recording = Recording(id: UUID(), meetingID: meetingID, startedAt: Date(), endedAt: nil, state: .starting)
            try await store.beginRecording(recording)
            let capture = RecordingCapture(recordingID: recording.id)
            let storage = RecordingStorage(store: store, root: root, recording: recording,
                                           checkpointPublished: transcription.checkpointPublished)
            let autoStop = OSAllocatedUnfairLock(initialState: RecordingAutoStop(scheduledEnd: scheduledEnd))
            let (meterUpdates, meterContinuation) = AsyncStream<(peak: Double, rms: Double)>.makeStream(
                bufferingPolicy: .bufferingNewest(1)
            )
            let consumer = Task.detached(priority: .userInitiated) {
                defer { meterContinuation.finish() }
                var lastUpdate = ContinuousClock.now
                var lastDelayLog: ContinuousClock.Instant?
                var peak = 0.0
                var rms = 0.0
                for try await sample in capture.samples {
                    let dequeuedAt = ContinuousClock.now
                    let input = try await storage.append(sample)
                    peak = max(peak, input.peak)
                    if sample.source == .me { rms = input.rms }
                    let now = ContinuousClock.now
                    let queueDelay = sample.enqueuedAt.duration(to: dequeuedAt)
                    let appendDelay = dequeuedAt.duration(to: now)
                    if (queueDelay >= .milliseconds(250) || appendDelay >= .milliseconds(250)),
                       lastDelayLog.map({ $0.duration(to: now) >= .seconds(1) }) ?? true {
                        RecordingCapture.diagnostics.notice("Audio processing delay recording=\(recording.id.uuidString, privacy: .public) source=\(sample.source.rawValue, privacy: .public) queue=\(queueDelay.description, privacy: .public) appendRoundTrip=\(appendDelay.description, privacy: .public)")
                        lastDelayLog = now
                    }
                    autoStop.withLock {
                        $0.observeAudio(rms: input.rms, isMicrophone: sample.source == .me, at: now)
                    }
                    if lastUpdate.duration(to: now) >= .milliseconds(75) {
                        meterContinuation.yield((peak, rms))
                        lastUpdate = now
                        peak = 0
                    }
                }
            }
            do {
                try await capture.start(microphoneID: microphoneID)
                try await store.markRecordingStarted(recording.id)
            } catch {
                consumer.cancel()
                try? await capture.stop()
                _ = await consumer.result
                try? await storage.finish()
                _ = try? await store.finalizeRecording(recording.id, endedAt: Date(), interrupted: true)
                withExtendedLifetime(lock) {}
                throw error
            }

            let meters = Task { [weak self] in
                for await update in meterUpdates {
                    self?.levels.send(update.peak)
                    self?.microphoneRMS.send(update.rms)
                }
            }
            session = Session(recording: recording, capture: capture, storage: storage,
                              consumer: consumer, meters: meters, lock: lock)
            state = .recording(meetingID)
            scheduleScreenCaptures()
            revision += 1
            autoStopMonitor = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, self.state == .recording(meetingID) else { return }
                    let externalInput = RecordingAutoStop.externalInputRunning()
                    let shouldStop = autoStop.withLock {
                        $0.shouldStop(externalInputRunning: externalInput, at: .now, date: .now)
                    }
                    if shouldStop {
                        self.stop()
                        return
                    }
                    do { try await Task.sleep(for: .seconds(2)) }
                    catch { return }
                }
            }
            Task {
                if case .failure(let error) = await consumer.result, state == .recording(meetingID) {
                    state = .finishing(meetingID)
                    await finish(cause: error)
                }
            }
        } catch {
            compression.resumeAfterCapture()
            self.error = "Could not start recording. \(error.localizedDescription)"
            state = .idle
            await startMicrophoneMeterIfNeeded()
        }
    }

    private func finish(cause: (any Error)? = nil) async {
        guard let session else { return }
        screenCaptureTimer?.cancel()
        screenCaptureTimer = nil
        manualScreenCapture?.cancel()
        autoStopMonitor?.cancel()
        autoStopMonitor = nil
        session.meters.cancel()
        var failure = cause
        var discarded = false
        do { try await session.capture.stop() }
        catch { failure = failure ?? error }
        if case .failure(let error) = await session.consumer.result { failure = failure ?? error }
        do { try await session.storage.finish() }
        catch { failure = failure ?? error }
        do {
            if failure != nil { try await session.storage.reconcile() }
            let saved = try await store.finalizeRecording(session.recording.id, endedAt: Date(), interrupted: failure != nil)
            discarded = !saved
            if discarded, failure == nil { failure = RecordingError.emptyRecording }
        } catch {
            failure = error
        }
        if let failure { error = "Recording ended. \(failure.localizedDescription)" }
        self.session = nil
        compression.resumeAfterCapture()
        levels.send(0)
        microphoneRMS.send(0)
        revision += 1
        state = .idle
        await startMicrophoneMeterIfNeeded()
        transcription.checkpointPublished()
        if discarded { await finishMeetingDeletions() }
    }
}
