import Foundation
import XCTest
@testable import MeetingRecord

final class RecordingAutoStopTests: XCTestCase {
    func testMicrophoneReleaseAndSilenceStopWithoutCalendar() {
        let start = ContinuousClock.now
        let date = Date(timeIntervalSince1970: 120)
        var autoStop = RecordingAutoStop(scheduledEnd: nil, started: start)

        XCTAssertFalse(autoStop.shouldStop(externalInputRunning: false, at: start, date: date))
        XCTAssertFalse(autoStop.shouldStop(externalInputRunning: true, at: start, date: date))
        for second in 1...119 {
            autoStop.observeAudio(rms: 0, isMicrophone: true, at: start.advanced(by: .seconds(second)))
        }
        XCTAssertFalse(autoStop.shouldStop(externalInputRunning: false, at: start.advanced(by: .seconds(119)), date: date))

        let silent = start.advanced(by: .seconds(120))
        autoStop.observeAudio(rms: 0, isMicrophone: true, at: silent)
        XCTAssertFalse(autoStop.shouldStop(externalInputRunning: nil, at: silent, date: date))
        XCTAssertFalse(autoStop.shouldStop(externalInputRunning: true, at: silent, date: date))
        XCTAssertTrue(autoStop.shouldStop(externalInputRunning: false, at: silent, date: date))

        autoStop.observeAudio(rms: 0.1, isMicrophone: false, at: silent)
        XCTAssertFalse(autoStop.shouldStop(externalInputRunning: false, at: silent, date: date))
    }

    func testMicrophoneReleaseAndPastScheduledEndStopWithoutSilence() {
        let time = ContinuousClock.now
        let end = Date(timeIntervalSince1970: 120)
        let afterEnd = end.addingTimeInterval(1)
        var autoStop = RecordingAutoStop(scheduledEnd: end, started: time)

        autoStop.observeAudio(rms: 0.1, isMicrophone: false, at: time)
        XCTAssertFalse(autoStop.shouldStop(externalInputRunning: false, at: time, date: afterEnd))
        XCTAssertFalse(autoStop.shouldStop(externalInputRunning: true, at: time, date: afterEnd))
        XCTAssertFalse(autoStop.shouldStop(externalInputRunning: false, at: time, date: end))
        XCTAssertTrue(autoStop.shouldStop(externalInputRunning: false, at: time, date: afterEnd))
    }

    func testSilenceAndPastScheduledEndDoNotStopByThemselves() {
        let start = ContinuousClock.now
        let end = Date(timeIntervalSince1970: 120)
        var autoStop = RecordingAutoStop(scheduledEnd: end, started: start)
        for second in 1...120 {
            autoStop.observeAudio(rms: 0, isMicrophone: true, at: start.advanced(by: .seconds(second)))
        }
        XCTAssertFalse(autoStop.shouldStop(externalInputRunning: false, at: start.advanced(by: .seconds(120)),
                                           date: end.addingTimeInterval(1)))
    }
}
