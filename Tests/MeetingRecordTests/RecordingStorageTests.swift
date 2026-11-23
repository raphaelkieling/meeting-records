import AVFoundation
import SQLite3
import XCTest
@testable import MeetingRecord

final class RecordingStorageTests: XCTestCase {
    func testFinalizesBothSourcesAndPreservesTimeline() async throws {
        let (store, root, recording) = try await fixture()
        let storage = RecordingStorage(store: store, root: root, recording: recording)
        let microphoneLevel = try await storage.append(sample(source: .me, offset: 0, value: 0.25))
        let computerLevel = try await storage.append(sample(source: .other, offset: 125_000_000, value: 0.5))
        XCTAssertEqual(microphoneLevel, 0.25, accuracy: 0.001)
        XCTAssertEqual(computerLevel, 0.5, accuracy: 0.001)
        try await storage.finish()
        let saved = try await store.finalizeRecording(recording.id, endedAt: Date(), interrupted: false)
        XCTAssertTrue(saved)
        let inputs = try await store.recordings(for: recording.meetingID)
        XCTAssertEqual(inputs.map(\.state), [.completed])
        let directory = root.appendingPathComponent(recording.meetingID.uuidString)
            .appendingPathComponent(recording.id.uuidString)
        XCTAssertEqual(try AVAudioFile(forReading: directory.appendingPathComponent("me/0.caf")).length, 4_800)
        XCTAssertEqual(try AVAudioFile(forReading: directory.appendingPathComponent("other/125000000.caf")).length, 4_800)
    }

    func testRecoversPublishedCheckpointMissingFromSQLite() async throws {
        let (store, root, recording) = try await fixture()
        do {
            let storage = RecordingStorage(store: store, root: root, recording: recording)
            for chunk in 0..<51 {
                _ = try await storage.append(sample(source: .me, offset: Int64(chunk) * 100_000_000, value: 0.25))
            }
        }
        let file = root.appendingPathComponent(recording.meetingID.uuidString)
            .appendingPathComponent(recording.id.uuidString).appendingPathComponent("me/0.caf")
        XCTAssertEqual(try AVAudioFile(forReading: file).length, 240_000)
        let database = root.deletingLastPathComponent().appendingPathComponent("meetings.sqlite")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.path, &handle), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(handle, "DELETE FROM audio_segments", nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)

        // Discard the pending partial clip as if its writer exited before publishing.
        try await RecordingStorage.recover(store: store, root: root)
        try await RecordingStorage.recover(store: store, root: root)
        let inputs = try await store.recordings(for: recording.meetingID)
        XCTAssertEqual(inputs.map(\.id), [recording.id])
        XCTAssertEqual(inputs.map(\.state), [.interrupted])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path), ["0.caf"])
    }

    func testWriteFailureKeepsPublishedAudioAndEmptyAttemptsStayHidden() async throws {
        let (store, root, recording) = try await fixture()
        let storage = RecordingStorage(store: store, root: root, recording: recording)
        _ = try await storage.append(sample(source: .me, offset: 0, value: 0.25))
        try await storage.finish()
        let session = root.appendingPathComponent(recording.meetingID.uuidString)
            .appendingPathComponent(recording.id.uuidString)
        // A regular file prevents creating the second track directory.
        try Data().write(to: session.appendingPathComponent("other"))
        do {
            _ = try await storage.append(sample(source: .other, offset: 0, value: 0.5))
            XCTFail("Expected the Other write to fail")
        } catch {}
        try await storage.reconcile()
        let saved = try await store.finalizeRecording(recording.id, endedAt: Date(), interrupted: true)
        XCTAssertTrue(saved)
        XCTAssertEqual(try AVAudioFile(forReading: session.appendingPathComponent("me/0.caf")).length, 4_800)

        let empty = Recording(id: UUID(), meetingID: recording.meetingID, startedAt: Date(), endedAt: nil, state: .starting)
        try await store.beginRecording(empty)
        let savedEmpty = try await store.finalizeRecording(empty.id, endedAt: Date(), interrupted: true)
        XCTAssertFalse(savedEmpty)
        let inputs = try await store.recordings(for: recording.meetingID)
        XCTAssertEqual(inputs.map(\.id), [recording.id])
        XCTAssertEqual(inputs.map(\.state), [.interrupted])
    }

    private func fixture() async throws -> (MeetingStore, URL, Recording) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = MeetingStore(databaseURL: directory.appendingPathComponent("meetings.sqlite"))
        let meeting = try await store.createMeeting(id: UUID(), name: "Recording Test")
        let recording = Recording(id: UUID(), meetingID: meeting.id, startedAt: Date(), endedAt: nil, state: .starting)
        try await store.beginRecording(recording)
        try await store.markRecordingStarted(recording.id)
        return (store, try await store.recordingRoot(), recording)
    }

    private func sample(source: AudioSegment.Source, offset: Int64, value: Float) throws -> CapturedAudio {
        let count = 4_800
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let samples = [Float](repeating: value, count: count)
        let bytes = count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes,
            blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: bytes,
            flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block), noErr)
        let data = try XCTUnwrap(block)
        try samples.withUnsafeBytes { buffer in
            let base = try XCTUnwrap(buffer.baseAddress)
            XCTAssertEqual(CMBlockBufferReplaceDataBytes(with: base, blockBuffer: data, offsetIntoDestination: 0,
                                                        dataLength: bytes), noErr)
        }
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: data,
            formatDescription: format.formatDescription, sampleCount: count,
            presentationTimeStamp: CMTime(value: offset, timescale: 1_000_000_000),
            packetDescriptions: nil, sampleBufferOut: &sample), noErr)
        return CapturedAudio(buffer: try XCTUnwrap(sample), source: source, startOffset: offset)
    }
}
