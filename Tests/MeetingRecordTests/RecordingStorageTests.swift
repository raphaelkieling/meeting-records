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
        XCTAssertEqual(microphoneLevel.peak, 0.25, accuracy: 0.001)
        XCTAssertEqual(computerLevel.peak, 0.5, accuracy: 0.001)
        XCTAssertEqual(microphoneLevel.rms, 0.25, accuracy: 0.001)
        try await storage.finish()
        let saved = try await store.finalizeRecording(recording.id, endedAt: Date(), interrupted: false)
        XCTAssertTrue(saved)
        let inputs = try await store.recordings(for: recording.meetingID)
        XCTAssertEqual(inputs.map(\.state), [.completed])
        let segments = try await store.audioSegments(for: recording.id)
        let duration = try await RecordingPlayback.savedDuration(segments: segments, root: root)
        XCTAssertEqual(duration, 0.225, accuracy: 0.001)
        let directory = root.appendingPathComponent(recording.meetingID.uuidString)
            .appendingPathComponent(recording.id.uuidString)
        XCTAssertEqual(try AVAudioFile(forReading: directory.appendingPathComponent("me/0.caf")).length, 4_800)
        XCTAssertEqual(try AVAudioFile(forReading: directory.appendingPathComponent("other/125000000.caf")).length, 4_800)

        let bytes = try await RecordingStorage.bytesUsed(at: root)
        XCTAssertGreaterThan(bytes, 0)
        try FileManager.default.removeItem(at: directory)
        let bytesAfterDeletion = try await RecordingStorage.bytesUsed(at: root)
        XCTAssertEqual(bytesAfterDeletion, 0)
    }

    func testRecoversPublishedCheckpointMissingFromSQLite() async throws {
        let (store, root, recording) = try await fixture()
        do {
            let storage = RecordingStorage(store: store, root: root, recording: recording)
            for chunk in 0..<101 {
                _ = try await storage.append(sample(source: .me, offset: Int64(chunk) * 100_000_000, value: 0.25))
            }
        }
        let file = root.appendingPathComponent(recording.meetingID.uuidString)
            .appendingPathComponent(recording.id.uuidString).appendingPathComponent("me/0.caf")
        XCTAssertEqual(try AVAudioFile(forReading: file).length, 480_000)
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
        let segments = try await store.audioSegments(for: recording.id)
        let duration = try await RecordingPlayback.savedDuration(segments: segments, root: root)
        XCTAssertEqual(duration, 10, accuracy: 0.001)
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

    func testMeetingDeletionUpdatesHomeAndRetriesFilesAfterReopen() async throws {
        let (store, root, recording) = try await fixture()
        let storage = RecordingStorage(store: store, root: root, recording: recording)
        _ = try await storage.append(sample(source: .me, offset: 0, value: 0.25))
        try await storage.finish()
        let active = try await store.loadHomeSummary()
        XCTAssertEqual(active.savedRecordingCount, 0)
        do {
            try await store.deleteMeeting(recording.meetingID)
            XCTFail("An active Meeting must remain available.")
        } catch MeetingStoreError.meetingRecording {}

        _ = try await store.finalizeRecording(recording.id, endedAt: Date(), interrupted: false)
        let segments = try await store.audioSegments(for: recording.id)
        let audio = try XCTUnwrap(segments.first)
        let text = TranscribedCheckpoint(processedThrough: 100_000_000,
            segments: [.init(startOffset: 0, endOffset: 50_000_000, text: "test")])
        _ = try await store.claimTranscript(recording.id, model: .base)
        try await store.saveTranscript(audio, result: text)
        let transcription = await TranscriptionCoordinator(store: store)
        await transcription.start()
        for _ in 0..<100 {
            if await transcription.completionRevision > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let completionRevision = await transcription.completionRevision
        XCTAssertEqual(completionRevision, 1)

        let sibling = try await store.createMeeting(id: UUID(), name: "Keep")
        let siblingDirectory = root.appendingPathComponent(sibling.id.uuidString)
        try FileManager.default.createDirectory(at: siblingDirectory, withIntermediateDirectories: true)
        let target = root.appendingPathComponent(recording.meetingID.uuidString)
        let database = root.deletingLastPathComponent().appendingPathComponent("meetings.sqlite")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        XCTAssertEqual(sqlite3_exec(handle, """
            CREATE TRIGGER reject_delete BEFORE DELETE ON meetings
            BEGIN SELECT RAISE(ABORT, 'blocked'); END;
            """, nil, nil, nil), SQLITE_OK)
        do {
            try await store.deleteMeeting(recording.meetingID)
            XCTFail("Expected the database trigger to reject deletion.")
        } catch MeetingStoreError.sqlite {}
        let intact = try await store.loadHomeSummary()
        XCTAssertEqual(intact.savedRecordingCount, 1)
        XCTAssertEqual(intact.recordedTime, 0.1, accuracy: 0.000_001)
        XCTAssertTrue(intact.missingDurationIDs.isEmpty)
        XCTAssertEqual(intact.completedTranscriptions, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        let noPending = try await store.pendingMeetingDeletions()
        XCTAssertTrue(noPending.isEmpty)
        XCTAssertEqual(sqlite3_exec(handle, "DROP TRIGGER reject_delete", nil, nil, nil), SQLITE_OK)

        try await store.deleteMeeting(recording.meetingID)
        let reopened = MeetingStore(databaseURL: database)
        let after = try await reopened.loadHomeSummary()
        XCTAssertEqual(after.meetings.map(\.id), [sibling.id])
        XCTAssertEqual(after.savedRecordingCount, 0)
        XCTAssertEqual(after.completedTranscriptions, 0)
        let lateClaim = try await reopened.claimTranscript(recording.id, model: .base)
        XCTAssertEqual(lateClaim, .removed)
        try await reopened.saveTranscript(audio, result: text)
        let siblingRecording = Recording(id: UUID(), meetingID: sibling.id, startedAt: Date(), endedAt: nil, state: .starting)
        try await reopened.beginRecording(siblingRecording)
        let nextClaim = try await reopened.claimTranscript(siblingRecording.id, model: .base)
        XCTAssertEqual(nextClaim, .changed)

        let blocker = root.appendingPathComponent(".deletions")
        try Data().write(to: blocker)
        do {
            try await RecordingStorage.finishMeetingDeletions(store: reopened)
            XCTFail("Expected file cleanup to remain pending.")
        } catch {}
        let pending = try await reopened.pendingMeetingDeletions()
        XCTAssertEqual(pending, [recording.meetingID])
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))

        try FileManager.default.removeItem(at: blocker)
        try await RecordingStorage.finishMeetingDeletions(store: reopened)
        try await RecordingStorage.finishMeetingDeletions(store: reopened)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: siblingDirectory.path))
        let cleared = try await reopened.pendingMeetingDeletions()
        XCTAssertTrue(cleared.isEmpty)
    }

    func testRemovingOneRecordingKeepsOtherInputsAndRetriesFileCleanup() async throws {
        let (store, root, recording) = try await fixture()
        do {
            try await store.deleteRecording(recording)
            XCTFail("Expected active recording removal to fail.")
        } catch MeetingStoreError.meetingRecording {}

        let storage = RecordingStorage(store: store, root: root, recording: recording)
        _ = try await storage.append(sample(source: .me, offset: 0, value: 0.25))
        try await storage.finish()
        try await store.finalizeRecording(recording.id, endedAt: .now, interrupted: false)
        let clips = try await store.audioSegments(for: recording.id)
        let clip = try XCTUnwrap(clips.first)
        let audio = root.appendingPathComponent(clip.relativePath)
        _ = try await store.claimTranscript(recording.id, model: .base)
        try await store.saveTranscript(clip, result: .init(processedThrough: 100_000_000,
            segments: [.init(startOffset: 0, endOffset: 100_000_000, text: "Removed source")]))
        var answer = ChatMessage(role: .assistant, body: "Removed source", status: .streaming, requestID: UUID())
        answer.citations = [.init(meetingID: recording.meetingID, recordingID: recording.id,
                                  passageIDs: ["passage"], startOffset: 0, revision: 0)]
        let chat = ChatConversation(title: "Recording source", messages: [answer])
        try await store.saveChat(chat, changed: 1, create: true)

        let other = Recording(id: UUID(), meetingID: recording.meetingID, startedAt: .now, endedAt: nil, state: .starting)
        try await store.beginRecording(other)
        try await store.markRecordingStarted(other.id)
        try await store.deleteRecording(recording)

        let reopened = MeetingStore(databaseURL: root.deletingLastPathComponent().appendingPathComponent("meetings.sqlite"))
        let inputs = try await reopened.recordings(for: recording.meetingID, includeActive: true)
        XCTAssertEqual(inputs.map(\.id), [other.id])
        let passages = try await reopened.transcriptPassages(for: recording.meetingID)
        XCTAssertTrue(passages.isEmpty)
        try await reopened.saveChat(chat, changed: 1, create: false)
        let history = try await reopened.loadChatHistory()
        XCTAssertEqual(history.first?.messages.first?.status, .sourceRemoved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))

        let blocker = root.appendingPathComponent(".deletions")
        try Data().write(to: blocker)
        do {
            _ = try await RecordingStorage.finishMeetingDeletions(store: reopened)
            XCTFail("Expected file cleanup to remain pending.")
        } catch {}
        let pending = try await reopened.pendingRecordingDeletions()
        XCTAssertEqual(pending.map(\.recordingID), [recording.id])
        try FileManager.default.removeItem(at: blocker)
        try await RecordingStorage.finishMeetingDeletions(store: reopened)
        let cleared = try await reopened.pendingRecordingDeletions()
        XCTAssertTrue(cleared.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
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
