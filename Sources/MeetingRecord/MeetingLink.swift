import Foundation

enum MeetingLink {
    static func meetingID(from url: URL) -> UUID? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "meetingrecord",
              components.host?.lowercased() == "meeting",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil else { return nil }
        return UUID(uuidString: String(components.path.dropFirst()))
    }

    static func markdown(for meeting: Meeting) -> String {
        let title = meeting.name.split(whereSeparator: \.isNewline).joined(separator: " ")
        let escapedTitle = title.map { character in
            "\\[]`*_<>~&!".contains(character) ? "\\\(character)" : String(character)
        }.joined()
        return "[\(escapedTitle)](meetingrecord://meeting/\(meeting.id.uuidString))"
    }
}
