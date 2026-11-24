import Foundation

struct SearchQuery: Equatable, Sendable {
    let text: String
    let selectedTagIDs: Set<UUID>
}

struct SearchResult: Identifiable, Sendable {
    let meeting: Meeting
    let assignedTags: [Tag]
    let transcriptExcerpt: String?

    var id: UUID { meeting.id }
}
