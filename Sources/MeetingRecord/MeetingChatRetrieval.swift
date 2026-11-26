import Foundation

struct TranscriptChunk: Sendable {
    let passageIDs: [String]
    let startOffset: Int64
    let endOffset: Int64
    let body: String
}

struct ChatEvidence: Sendable {
    let title: String
    let body: String
    let citation: ChatCitation
    var endOffset: Int64? = nil
}

struct ChatMeetingMatch: Codable, Sendable {
    let id: UUID
    let title: String
    let date: Date
    let description: String?
    let tags: [String]
    let invitees: [String]
    let summaryExcerpt: String?
}

enum MeetingChatRetrieval {
    static let searchInstructions = """
        For questions about what people said, discussed, decided, or agreed to do, check the transcript evidence.
        Use searchMeetings to find candidates by title, date, or keywords in saved summaries. Use summary excerpts to identify likely meetings and useful transcript keywords.
        Choose short topic keywords from the question and conversation context. Call searchTranscript with those keywords and any relevant meeting IDs to verify what happened.
        When a search excerpt lacks context, call readTranscriptContext with its evidence number to read surrounding speech in chronological order. A good starting window is 60 seconds before and after. Dense windows may return only the nearest passages.
        If no meeting is established, use an empty meetingIDs list to search the full selected scope, even when searchMeetings returned no candidates.
        If the transcript search is empty, retry with a shorter keyword, a likely wording variant, or a broader meeting scope within the user's selection.
        Transcript search can also return numbered screen capture references near matching passages. Cite a capture by its number when it helps the user inspect that moment. Capture references provide timing only.
        Verify details from summaries against the transcript and cite transcript evidence for what happened. Use meeting metadata for facts such as titles, dates, and invitees.
        """

    static func refresh(_ store: MeetingStore) async throws {
        for id in try await store.staleChatRecordings() {
            try Task.checkCancellation()
            guard let transcript = try await store.chatIndexInput(id) else { continue }
            let chunks = chunks(from: transcript.passages)
            try Task.checkCancellation()
            try await store.replaceChatIndex(id, revision: transcript.revision, chunks: chunks)
            await Task.yield()
        }
    }

    static func chunks(from passages: [TranscriptPassage]) -> [TranscriptChunk] {
        var result: [TranscriptChunk] = []
        var group: [TranscriptPassage] = []
        var lines: [String] = []
        var bytes = 0

        func flush() {
            guard let first = group.first else { return }
            result.append(TranscriptChunk(passageIDs: group.map(\.id), startOffset: first.startOffset,
                endOffset: group.map(\.endOffset).max() ?? first.endOffset, body: lines.joined(separator: "\n")))
            group.removeAll(keepingCapacity: true)
            lines.removeAll(keepingCapacity: true)
            bytes = 0
        }

        for passage in passages where TranscriptPassage.hasWords(passage.text) {
            let text = Array(passage.text.utf8)
            var start = 0
            while start < text.count {
                var end = min(start + 1_360, text.count)
                while end < text.count, text[end] & 0xC0 == 0x80 { end -= 1 }
                if end < text.count,
                   let space = text[max(start, end - 96)..<end].lastIndex(where: { $0 == 32 || $0 == 10 }) {
                    end = space + 1
                }
                let piece = String(decoding: text[start..<end], as: UTF8.self)
                let line = "\(passage.source == .me ? "Me" : "Other"): \(piece)"
                if bytes + line.utf8.count + 1 > 1_440 { flush() }
                if group.last?.id != passage.id { group.append(passage) }
                lines.append(line)
                bytes += line.utf8.count + 1
                start = end
                if start < text.count { flush() }
            }
        }
        flush()
        return result
    }

    static func terms(from text: String) -> [String] {
        var seen = Set<String>()
        return text.lowercased().split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 2 && $0.count <= 64 && seen.insert($0).inserted }
    }

    static func match(_ terms: [String]) -> String {
        Self.terms(from: terms.joined(separator: " ")).prefix(16).map { "\"\($0)\"" }.joined(separator: " OR ")
    }

    static func citationNumbers(in text: String, count: Int) -> [Int] {
        var seen = Set<Int>()
        return text.matches(of: /\[(\d{1,3})\]/).compactMap { match in
            guard let number = Int(match.1), number > 0, number <= count, seen.insert(number).inserted else { return nil }
            return number
        }
    }
}
