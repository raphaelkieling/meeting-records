import Foundation

struct Meeting: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date
    let updatedAt: Date

    init(id: UUID, name: String, createdAt: Date, updatedAt: Date) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              createdAt.timeIntervalSince1970.isFinite, updatedAt.timeIntervalSince1970.isFinite else {
            throw MeetingStoreError.invalidRecord
        }
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func normalizedName(_ value: String) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw MeetingStoreError.emptyName }
        guard !name.contains("\0") else { throw MeetingStoreError.invalidName }
        return name
    }

    static func mostRecentFirst(_ lhs: Meeting, _ rhs: Meeting) -> Bool {
        lhs.updatedAt == rhs.updatedAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.updatedAt > rhs.updatedAt
    }
}

enum MeetingStoreError: Error, LocalizedError {
    case invalidRecord, invalidDirectory, incompatibleVersion, emptyName, invalidName, notFound, sqlite(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidRecord: "The database contains an invalid meeting."
        case .invalidDirectory: "The data directory must be a valid absolute path."
        case .incompatibleVersion: "The database version is not supported by this app."
        case .emptyName: "Enter a meeting name."
        case .invalidName: "The meeting name contains an unsupported character."
        case .notFound: "This meeting is no longer available."
        case .sqlite(let code): "Could not access local storage (SQLite \(code)). Please try again."
        }
    }
}
