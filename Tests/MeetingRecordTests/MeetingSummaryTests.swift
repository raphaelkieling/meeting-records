import XCTest
@testable import MeetingRecord

final class MeetingSummaryTests: XCTestCase {
    func testContextOverflowSplitsAndMergesInTranscriptOrder() async throws {
        enum ModelError: Error { case contextOverflow }
        let transcript = "Me: ship on Friday.\nOther: update the release notes."
        var received: [String] = []
        let result = try await MeetingSummarizer.summarizeSections(transcript[...]) { source, merging in
            if merging { return source }
            if source.contains("Me:"), source.contains("Other:") { throw ModelError.contextOverflow }
            let section = source.trimmingCharacters(in: .whitespacesAndNewlines)
            received.append(section)
            return section
        } isContextOverflow: { $0 is ModelError }
        XCTAssertEqual(received, ["Me: ship on Friday.", "Other: update the release notes."])
        XCTAssertEqual(result, received.joined(separator: "\n\n"))
    }
}
