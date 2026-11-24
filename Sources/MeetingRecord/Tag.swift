import Foundation

enum TagColor: String, CaseIterable, Hashable, Sendable {
    case gold, lavender, green, coral, blue, rose
}

struct Tag: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let name: String
    let color: TagColor

    init(id: UUID, name: String, color: TagColor) throws {
        self.id = id
        self.name = try Self.normalizedName(name)
        self.color = color
    }

    static func normalizedName(_ value: String) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw MeetingStoreError.emptyTagName }
        guard !name.contains("\0") else { throw MeetingStoreError.invalidName }
        return name
    }

    var normalizedKey: String { name.lowercased() }
}

struct MeetingTagAssignment: Hashable, Sendable {
    let meetingID: UUID
    let tagID: UUID
}
