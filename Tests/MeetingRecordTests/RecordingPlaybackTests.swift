import AVFoundation
import XCTest
@testable import MeetingRecord

@MainActor
final class RecordingPlaybackTests: XCTestCase {
    func testSavedSourcesMixOnlyAtTheirTimelineOffsets() async throws {
        let (store, root, meetingID) = try await fixture()
        let recording = try await save(in: store, meetingID: meetingID, root: root, clips: [
            (.other, 100, 0.5), (.me, 400, 0.25), (.me, 0, 0.25)
        ])
        let segments = try await store.audioSegments(for: recording)
        XCTAssertEqual(segments.map(\.source), [.me, .other, .me])
        XCTAssertEqual(segments.map(\.startOffset), [0, 100_000_000, 400_000_000])
        let urls = segments.map { root.appendingPathComponent($0.relativePath) }
        let originals = try urls.map { try Data(contentsOf: $0) }
        let (asset, mix) = try await RecordingPlayback.makeComposition(segments: segments, root: root)
        let samples = try render(asset, mix: mix)
        guard samples.count > 21_600 else { return XCTFail("Rendered mix ended early") }
        XCTAssertEqual(samples[2_400], 0.125, accuracy: 0.01)  // Me at 50 ms.
        XCTAssertEqual(samples[7_200], 0.375, accuracy: 0.01)  // Both at 150 ms.
        XCTAssertEqual(samples[12_000], 0.25, accuracy: 0.01) // Other at 250 ms.
        XCTAssertEqual(samples[16_800], 0, accuracy: 0.01)    // Gap at 350 ms.
        XCTAssertEqual(samples[21_600], 0.125, accuracy: 0.01)
        XCTAssertEqual(try urls.map { try Data(contentsOf: $0) }, originals)
        for segment in segments {
            let file = try AVAudioFile(forReading: root.appendingPathComponent(segment.relativePath))
            XCTAssertEqual(file.length, segment.frameCount)
        }
    }

    func testInterruptedRecordingPlaysAvailableSourceAndMissingAudioResetsControl() async throws {
        let (store, root, meetingID) = try await fixture()
        let id = try await save(in: store, meetingID: meetingID, root: root, clips: [(.other, 0, 0.5)])
        let second = try await save(in: store, meetingID: meetingID, root: root, clips: [(.me, 0, 0.25)])
        let segments = try await store.audioSegments(for: id)
        let (asset, mix) = try await RecordingPlayback.makeComposition(segments: segments, root: root)
        let samples = try render(asset, mix: mix)
        XCTAssertEqual(samples[2_400], 0.5, accuracy: 0.01)

        let playback = RecordingPlayback()
        playback.toggle(id, store: store)
        XCTAssertEqual(playback.activeID, id)
        playback.toggle(second, store: store)
        XCTAssertEqual(playback.activeID, second)
        playback.toggle(second, store: store)
        XCTAssertNil(playback.activeID)
        playback.toggle(id, store: store)
        playback.stop()  // The Inputs view calls stop when it disappears.
        XCTAssertNil(playback.activeID)

        let deleted = try XCTUnwrap(segments.first)
        try FileManager.default.removeItem(at: root.appendingPathComponent(deleted.relativePath))
        playback.toggle(id, store: store)
        let deadline = ContinuousClock.now + .seconds(3)
        while playback.activeID != nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(playback.activeID)
        XCTAssertNotNil(playback.error)
    }

    func testPlaybackReturnsToIdleAfterNaturalCompletion() async throws {
        let (store, root, meetingID) = try await fixture()
        let id = try await save(in: store, meetingID: meetingID, root: root, clips: [(.me, 0, 0)])
        let playback = RecordingPlayback()
        playback.toggle(id, store: store)
        XCTAssertEqual(playback.activeID, id)
        let deadline = ContinuousClock.now + .seconds(5)
        while playback.activeID != nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(playback.activeID)
        XCTAssertNil(playback.error)
    }

    private func fixture() async throws -> (MeetingStore, URL, UUID) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = MeetingStore(databaseURL: directory.appendingPathComponent("meetings.sqlite"))
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let meeting = try await store.createMeeting(id: UUID(), name: "Playback Test")
        return (store, try await store.recordingRoot(), meeting.id)
    }

    private func save(in store: MeetingStore, meetingID: UUID, root: URL,
                      clips: [(AudioSegment.Source, Int64, Float)]) async throws -> UUID {
        let id = UUID()
        try await store.beginRecording(Recording(id: id, meetingID: meetingID, startedAt: Date(),
                                                endedAt: nil, state: .starting))
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 9_600))
        buffer.frameLength = 9_600
        let data = try XCTUnwrap(buffer.floatChannelData?[0])
        for (source, milliseconds, level) in clips {
            let offset = milliseconds * 1_000_000
            let path = "\(meetingID)/\(id)/\(source.rawValue)/\(offset).caf"
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            for frame in 0..<Int(buffer.frameLength) { data[frame] = level }
            do {
                let file = try AVAudioFile(forWriting: url, settings: format.settings)
                try file.write(from: buffer)
            }
            try await store.registerSegment(AudioSegment(recordingID: id, source: source, startOffset: offset,
                                                         frameCount: 9_600, relativePath: path))
        }
        try await store.finalizeRecording(id, endedAt: Date(), interrupted: clips.count == 1)
        return id
    }

    private func render(_ asset: AVMutableComposition, mix: AVAudioMix) throws -> [Float] {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: asset.tracks, audioSettings: format.settings)
        output.audioMix = mix
        reader.add(output)
        XCTAssertTrue(reader.startReading(), String(describing: reader.error))
        var samples: [Float] = []
        while let sample = output.copyNextSampleBuffer() {
            let frames = Int32(sample.numSamples)
            let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(frames)))
            pcm.frameLength = UInt32(frames)
            let result = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: frames,
                                                                     into: pcm.mutableAudioBufferList)
            XCTAssertEqual(result, noErr)
            let data = try XCTUnwrap(pcm.floatChannelData?[0])
            samples.append(contentsOf: UnsafeBufferPointer(start: data, count: Int(frames)))
        }
        XCTAssertEqual(reader.status, .completed, String(describing: reader.error))
        return samples
    }
}
