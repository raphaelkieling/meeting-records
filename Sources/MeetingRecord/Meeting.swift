import Foundation

struct CalendarEventDetails: Codable, Sendable {
    let title: String
    let notes: String?
    let endDate: Date?
    let organizer: String?
    let attendees: [String]
}

struct Meeting: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let description: String?
    let tags: [Tag]
    let createdAt: Date
    let updatedAt: Date
    let calendarEventDate: Date?
    let calendarName: String?

    init(id: UUID, name: String, description: String? = nil, tags: [Tag] = [],
         createdAt: Date, updatedAt: Date, calendarEventDate: Date? = nil, calendarName: String? = nil) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              createdAt.timeIntervalSince1970.isFinite, updatedAt.timeIntervalSince1970.isFinite else {
            throw MeetingStoreError.invalidRecord
        }
        self.id = id
        self.name = name
        self.description = Self.normalizedDescription(description)
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.calendarEventDate = calendarEventDate
        self.calendarName = calendarName
    }

    static func normalizedName(_ value: String) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw MeetingStoreError.emptyName }
        guard !name.contains("\0") else { throw MeetingStoreError.invalidName }
        return name
    }

    static func normalizedDescription(_ value: String?) -> String? {
        guard let value else { return nil }
        let description = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? nil : description
    }

    static func mostRecentFirst(_ lhs: Meeting, _ rhs: Meeting) -> Bool {
        lhs.updatedAt == rhs.updatedAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.updatedAt > rhs.updatedAt
    }
}

enum MeetingStoreError: Error, LocalizedError {
    case invalidRecord, invalidDirectory, incompatibleVersion, emptyName, emptyTagName, duplicateTagName
    case invalidName, notFound, meetingRecording, sqlite(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidRecord: "The database contains an invalid meeting."
        case .invalidDirectory: "The data directory must be a valid absolute path."
        case .incompatibleVersion: "The database version is not supported by this app."
        case .emptyName: "Enter a meeting name."
        case .emptyTagName: "Enter a label name."
        case .duplicateTagName: "A label with that name already exists."
        case .invalidName: "The meeting name contains an unsupported character."
        case .meetingRecording: "Stop the recording before deleting this meeting."
        case .notFound: "This meeting is no longer available."
        case .sqlite(let code): "Could not access local storage (SQLite \(code)). Please try again."
        }
    }
}
