import XCTest
@testable import MeetingRecord

final class TranscriptionEngineTests: XCTestCase {
    func testSteadySignalAboveThresholdIsSelected() throws {
        let samples = [Float](repeating: 0.2, count: 1_000)
        let selected = try XCTUnwrap(TranscriptionEngine.selectMicrophoneIntervals(samples, threshold: 0.1, sampleRate: 1_000))
        XCTAssertEqual(selected, samples)
    }

    func testSteadySignalBelowThresholdIsSkipped() {
        let samples = [Float](repeating: 0.02, count: 1_000)
        XCTAssertNil(TranscriptionEngine.selectMicrophoneIntervals(samples, threshold: 0.1, sampleRate: 1_000))
    }

    func testCrossingKeepsQuietContextAndDropsDistantNoise() throws {
        var samples = [Float](repeating: 0.01, count: 3_000)
        samples.replaceSubrange(1_000..<1_200, with: repeatElement(0.2, count: 200))
        let selected = try XCTUnwrap(TranscriptionEngine.selectMicrophoneIntervals(samples, threshold: 0.1,
            sampleRate: 1_000, context: 0.1))
        XCTAssertEqual(selected[950], 0.01)
        XCTAssertEqual(selected[1_250], 0.01)
        XCTAssertEqual(selected[799], 0)
        XCTAssertEqual(selected[1_300], 0)
    }

    func testEmptyAndBriefPauseRemainDeterministic() throws {
        XCTAssertNil(TranscriptionEngine.selectMicrophoneIntervals([], threshold: 0.1))
        var samples = [Float](repeating: 0.2, count: 3_000)
        samples.replaceSubrange(1_000..<1_100, with: repeatElement(0, count: 100))
        let selected = try XCTUnwrap(TranscriptionEngine.selectMicrophoneIntervals(samples, threshold: 0.1,
            sampleRate: 1_000, context: 0.1))
        XCTAssertEqual(selected[1_050], 0)
        XCTAssertNotEqual(selected[900], 0)
        XCTAssertNotEqual(selected[1_100], 0)
    }

    func testOtherTrackDoesNotUseMicrophoneThreshold() throws {
        let samples = [Float](repeating: 0.001, count: 1_000)
        XCTAssertNil(TranscriptionEngine.selectedSamples(samples, source: .me, threshold: 1))
        XCTAssertEqual(try XCTUnwrap(TranscriptionEngine.selectedSamples(samples, source: .other, threshold: 1)), samples)
    }
}
