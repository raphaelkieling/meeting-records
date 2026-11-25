import CoreAudio
import Foundation

struct RecordingAutoStop {
    let scheduledEnd: Date?
    private var lastAudio: ContinuousClock.Instant
    private var lastMicrophoneSample: ContinuousClock.Instant
    private var observedExternalInput = false

    init(scheduledEnd: Date?, started: ContinuousClock.Instant = .now) {
        self.scheduledEnd = scheduledEnd
        lastAudio = started
        lastMicrophoneSample = started
    }

    mutating func observeAudio(rms: Double, isMicrophone: Bool, at time: ContinuousClock.Instant) {
        // Reset the silence interval after a gap in microphone capture, such as system sleep.
        if rms >= 0.003 || (isMicrophone && lastMicrophoneSample.duration(to: time) > .seconds(2)) {
            lastAudio = time
        }
        if isMicrophone { lastMicrophoneSample = time }
    }

    mutating func shouldStop(externalInputRunning: Bool?, at time: ContinuousClock.Instant, date: Date) -> Bool {
        if externalInputRunning == true { observedExternalInput = true }
        let microphoneReleased = observedExternalInput && externalInputRunning == false
        let silent = lastAudio.duration(to: time) >= .seconds(120)
            && lastMicrophoneSample.duration(to: time) <= .seconds(2)
        let pastScheduledEnd = scheduledEnd.map { date > $0 } ?? false
        let score = (microphoneReleased ? 40 : 0) + (silent ? 30 : 0) + (pastScheduledEnd ? 30 : 0)
        return score >= 70
    }

    static func externalInputRunning() -> Bool? {
        guard #available(macOS 14.2, *) else { return nil }
        var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &property, 0, nil, &size) == noErr else { return nil }
        let stride = UInt32(MemoryLayout<AudioObjectID>.stride)
        guard size > 0 else { return false }
        guard size.isMultiple(of: stride) else { return nil }
        var processes = [AudioObjectID](repeating: 0, count: Int(size / stride))
        let status = processes.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let address = buffer.baseAddress else { return OSStatus(kAudioHardwareUnspecifiedError) }
            return AudioObjectGetPropertyData(system, &property, 0, nil, &size, address)
        }
        guard status == noErr else { return nil }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var incomplete = false
        for process in processes.prefix(Int(size / stride)) {
            guard let running = processProperty(kAudioProcessPropertyIsRunningInput, of: process) else {
                incomplete = true
                continue
            }
            guard running != 0 else { continue }
            guard let pid = processProperty(kAudioProcessPropertyPID, of: process) else {
                incomplete = true
                continue
            }
            if pid != UInt32(bitPattern: ownPID) { return true }
        }
        return incomplete ? nil : false
    }

    private static func processProperty(_ selector: AudioObjectPropertySelector, of process: AudioObjectID) -> UInt32? {
        var property = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: value))
        guard AudioObjectGetPropertyData(process, &property, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
