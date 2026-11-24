import XCTest
@testable import MeetingRecord

final class CommandPaletteSearchTests: XCTestCase {
    func testGroupsTitleAndMetadataMatchesBeforeTagsAndCommands() throws {
        let date = Date(timeIntervalSince1970: 0)
        let tag = try Tag(id: UUID(), name: "Revisão", color: .blue)
        let unassigned = try Tag(id: UUID(), name: "Revisão Backlog", color: .gold)
        let titleMatch = try Meeting(id: UUID(), name: "Revisão de projeto", createdAt: date, updatedAt: date)
        let descriptionMatch = try Meeting(id: UUID(), name: "Retro", description: "Revisão do processo",
                                           createdAt: date, updatedAt: date)
        let tagged = try Meeting(id: UUID(), name: "Planning", tags: [tag], createdAt: date, updatedAt: date)
        let command = PaletteCommand(title: "Open Settings", icon: "gearshape", keywords: ["review", "revisão"]) {}
        let meetings = [tagged, descriptionMatch, titleMatch]
        let tags = [tag, unassigned]

        let results = PaletteItem.search("  REVISAO ", meetings: meetings, tags: tags, commands: [command])
        XCTAssertEqual(results.map(\.id), [.meeting(titleMatch.id), .meeting(tagged.id), .meeting(descriptionMatch.id),
                                            .tag(tag.id), .tag(unassigned.id), .command(command.title)])

        let crossField = PaletteItem.search("revisao planning", meetings: meetings, tags: tags, commands: [command])
        XCTAssertEqual(crossField.map(\.id), [.meeting(tagged.id)])

        let empty = PaletteItem.search("", meetings: meetings, tags: tags, commands: [command])
        XCTAssertEqual(empty.map(\.id), meetings.map { .meeting($0.id) } + [.command(command.title)])
    }
}
