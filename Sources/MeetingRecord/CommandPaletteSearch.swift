import Foundation

struct PaletteCommand {
    let title: String
    let icon: String
    let keywords: [String]
    let run: @MainActor () -> Void
}

enum PaletteItem: Identifiable {
    enum Section: String, CaseIterable {
        case meetings = "Meetings"
        case transcripts = "Transcripts"
        case tags = "Tags"
        case commands = "Commands"
    }

    enum ID: Hashable {
        case meeting(UUID), transcript(String), tag(UUID), command(String)
    }

    case meeting(Meeting)
    case transcript(ChatEvidence)
    case tag(Tag)
    case command(PaletteCommand)

    var id: ID {
        switch self {
        case .meeting(let meeting): .meeting(meeting.id)
        case .transcript(let hit): .transcript(hit.citation.id)
        case .tag(let tag): .tag(tag.id)
        case .command(let command): .command(command.title)
        }
    }

    var section: Section {
        switch self {
        case .meeting: .meetings
        case .transcript: .transcripts
        case .tag: .tags
        case .command: .commands
        }
    }

    static func search(_ query: String, meetings: [Meeting], tags: [Tag], commands: [PaletteCommand]) -> [Self] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        func matches(_ fields: [String]) -> Bool {
            terms.allSatisfy { term in fields.contains { $0.localizedStandardContains(term) } }
        }

        let matchingCommands = commands.filter { matches([$0.title] + $0.keywords) }.map(Self.command)
        guard !terms.isEmpty else { return meetings.prefix(3).map(Self.meeting) + matchingCommands }

        var titleMatches: [Self] = []
        var metadataMatches: [Self] = []
        for meeting in meetings {
            if matches([meeting.name]) {
                titleMatches.append(.meeting(meeting))
            } else if matches([meeting.name, meeting.description ?? ""] + meeting.tags.map(\.name)) {
                metadataMatches.append(.meeting(meeting))
            }
        }
        let matchingTags = tags.filter { matches([$0.name]) }.map(Self.tag)
        return titleMatches + metadataMatches + matchingTags + matchingCommands
    }
}
