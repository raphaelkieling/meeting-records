@preconcurrency import AVFoundation
import CoreGraphics
@preconcurrency import ScreenCaptureKit

/// Capture retains each sample until the serial storage consumer copies its PCM data.
struct CapturedAudio: @unchecked Sendable {
    let buffer: CMSampleBuffer
    let source: AudioSegment.Source
    let startOffset: Int64
}

final class RecordingCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "MeetingRecord.capture", qos: .userInitiated)
    private let microphone = AVCaptureSession()
    private let hostClock = CMClockGetHostTimeClock()
    private let origin = CMClockGetTime(CMClockGetHostTimeClock())
    private let continuation: AsyncThrowingStream<CapturedAudio, any Error>.Continuation
    let samples: AsyncThrowingStream<CapturedAudio, any Error>
    // Start and stop are serialized by RecordingCoordinator.
    private var stream: SCStream?
    struct Microphone: Identifiable, Sendable {
        let id: String
        let name: String
    }

    static func microphones() -> [Microphone] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio,
                                         position: .unspecified).devices.map {
            Microphone(id: $0.uniqueID, name: $0.localizedName)
        }
    }

    private var stopped = false
    private var levelChanged: (@Sendable (Double) -> Void)?
    private var microphoneObservers: [any NSObjectProtocol] = []

    override init() {
        (samples, continuation) = AsyncThrowingStream.makeStream(bufferingPolicy: .bufferingOldest(64))
        super.init()
    }

    static func authorize() async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw RecordingError.microphonePermission }
        if !CGPreflightScreenCaptureAccess(), !CGRequestScreenCaptureAccess() {
            throw RecordingError.screenPermission
        }
    }

    func start(microphoneID: String) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                ?? content.displays.first else { throw RecordingError.noDisplay }
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        self.stream = stream
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await stream.startCapture()
        try await startMicrophone(id: microphoneID)
    }

    func startMicrophone(id: String, levelChanged: (@Sendable (Double) -> Void)? = nil) async throws {
        try await withCheckedThrowingContinuation { (resume: CheckedContinuation<Void, any Error>) in
            queue.async { [self] in
                do {
                    guard !stopped else { throw CancellationError() }
                    guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
                        throw RecordingError.microphonePermission
                    }
                    let selected = id.isEmpty ? AVCaptureDevice.default(for: .audio) : AVCaptureDevice(uniqueID: id)
                    guard let device = selected, device.isConnected, device.hasMediaType(.audio) else {
                        throw id.isEmpty ? RecordingError.noMicrophone : RecordingError.selectedMicrophoneUnavailable
                    }
                    self.levelChanged = levelChanged
                    let input = try AVCaptureDeviceInput(device: device)
                    let output = AVCaptureAudioDataOutput()
                    guard self.microphone.canAddInput(input), self.microphone.canAddOutput(output) else {
                        throw RecordingError.noMicrophone
                    }
                    self.microphone.addInput(input)
                    self.microphone.addOutput(output)
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    let runtimeError = NotificationCenter.default.addObserver(
                        forName: AVCaptureSession.runtimeErrorNotification, object: self.microphone, queue: nil
                    ) { [weak self] notification in
                        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
                        self?.continuation.finish(throwing: error ?? RecordingError.noMicrophone)
                    }
                    let disconnect = NotificationCenter.default.addObserver(
                        forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: nil
                    ) { [weak self] _ in
                        self?.continuation.finish(throwing: RecordingError.noMicrophone)
                    }
                    self.microphoneObservers = [runtimeError, disconnect]
                    self.microphone.startRunning()
                    guard self.microphone.isRunning else { throw RecordingError.noMicrophone }
                    resume.resume()
                } catch { resume.resume(throwing: error) }
            }
        }
    }

    func stop() async throws {
        var screenError: (any Error)?
        if let stream {
            do { try await stream.stopCapture() }
            catch { screenError = error }
            self.stream = nil
        }
        await withCheckedContinuation { resume in
            queue.async {
                self.stopped = true
                self.levelChanged = nil
                for observer in self.microphoneObservers {
                    NotificationCenter.default.removeObserver(observer)
                }
                self.microphoneObservers.removeAll()
                if self.microphone.isRunning { self.microphone.stopRunning() }
                resume.resume()
            }
        }
        // Deliver callbacks already queued before closing the consumer stream.
        await withCheckedContinuation { resume in
            queue.async {
                self.continuation.finish()
                resume.resume()
            }
        }
        if let screenError { throw screenError }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        emit(buffer, source: .other, clock: stream.synchronizationClock)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        continuation.finish(throwing: error)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let levelChanged {
            let channels = connection.audioChannels
            guard !channels.isEmpty else { return }
            let power = channels.reduce(0.0) { total, channel in
                total + pow(10.0, Double(channel.averagePowerLevel) / 10.0)
            }
            let level = sqrt(power / Double(channels.count))
            levelChanged(level.isFinite ? min(1, level) : 0)
            return
        }
        emit(buffer, source: .me, clock: microphone.synchronizationClock)
    }

    var currentTimelineOffset: Int64 {
        max(0, timelineOffset(at: CMClockGetTime(hostClock)).value)
    }

    private func timelineOffset(at time: CMTime) -> CMTime {
        CMTimeConvertScale(CMTimeSubtract(time, origin), timescale: 1_000_000_000, method: .default)
    }

    private func emit(_ buffer: CMSampleBuffer, source: AudioSegment.Source, clock: CMClock?) {
        guard buffer.isValid, buffer.numSamples > 0 else { return }
        guard let clock else {
            continuation.finish(throwing: RecordingError.invalidAudio)
            return
        }
        let time = CMSyncConvertTime(buffer.presentationTimeStamp, from: clock, to: hostClock)
        let offset = timelineOffset(at: time)
        guard offset.isNumeric else {
            continuation.finish(throwing: RecordingError.invalidAudio)
            return
        }
        if case .dropped = continuation.yield(CapturedAudio(buffer: buffer, source: source, startOffset: max(0, offset.value))) {
            continuation.finish(throwing: RecordingError.captureOverrun)
        }
    }
}
