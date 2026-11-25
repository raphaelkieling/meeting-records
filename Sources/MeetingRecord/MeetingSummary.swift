import Combine
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct MeetingSummary: Sendable {
    let text: String
    let model: String
    let transcriptRevision: String
}

struct MeetingSummarySnapshot: Sendable {
    let summary: MeetingSummary?
    let transcript: String
    let context: String
    let transcriptRevision: String
    let hasPendingAudio: Bool

    var canGenerate: Bool { !hasPendingAudio && !transcript.isEmpty }
    var isOutdated: Bool { summary.map { $0.transcriptRevision != transcriptRevision } ?? false }
}

enum SummaryModel: String, CaseIterable {
    case appleIntelligence = "apple-intelligence"
    case gpt62Astra = "gpt-6.2-astra"
    case gpt62Sol = "gpt-6.2-sol"
    case gpt61Terra = "gpt-6.1-terra"
    case gpt6Luna = "gpt-6-luna"
    case gpt54Mini = "gpt-5.4-mini"
    case gpt54Nano = "gpt-5.4-nano"

    static let preferenceKey = "selectedSummarizationModel"
    var usesOpenAI: Bool { self != .appleIntelligence }

    var displayName: String {
        switch self {
        case .appleIntelligence: "Apple Intelligence"
        case .gpt62Astra: "OpenAI · GPT-6.2 Astra"
        case .gpt62Sol: "OpenAI · GPT-6.2 Sol"
        case .gpt61Terra: "OpenAI · GPT-6.1 Terra"
        case .gpt6Luna: "OpenAI · GPT-6 Luna"
        case .gpt54Mini: "OpenAI · GPT-5.4 mini"
        case .gpt54Nano: "OpenAI · GPT-5.4 nano"
        }
    }

    static var selected: Self {
        AISettings.model(for: .summary)
    }
}

@MainActor
final class MeetingSummaryCoordinator: ObservableObject {
    @Published private(set) var generating: Set<UUID> = []
    @Published private(set) var errors: [UUID: String] = [:]
    @Published private(set) var revision = 0
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private let store: MeetingStore
    private let summarize: @Sendable (String, String, SummaryModel, String) async throws -> String

    init(store: MeetingStore,
         summarize: @escaping @Sendable (String, String, SummaryModel, String) async throws -> String = MeetingSummarizer.generate) {
        self.store = store
        self.summarize = summarize
    }

    func generate(for meetingID: UUID, model: SummaryModel = .selected, prompt: String = SummaryPrompt.general.text) {
        guard generating.insert(meetingID).inserted else { return }
        errors[meetingID] = nil
        tasks[meetingID] = Task {
            defer {
                tasks[meetingID] = nil
                generating.remove(meetingID)
                revision += 1
            }
            do {
                let source = try await store.summarySnapshot(for: meetingID)
                guard source.canGenerate else { throw MeetingSummaryError.transcriptNotReady }
                try Task.checkCancellation()
                let text = try await summarize(source.transcript, source.context, model, prompt)
                try Task.checkCancellation()
                try await store.saveSummary(.init(text: text, model: model.rawValue,
                                                  transcriptRevision: source.transcriptRevision), for: meetingID)
            } catch {
                if !Task.isCancelled { errors[meetingID] = error.localizedDescription }
            }
        }
    }

    func cancel(for meetingID: UUID) {
        tasks[meetingID]?.cancel()
        errors[meetingID] = nil
    }
}

private enum MeetingSummaryError: LocalizedError {
    case transcriptNotReady
    case unavailable(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .transcriptNotReady: "Wait until the meeting has a completed transcript."
        case .unavailable(let detail): detail
        case .emptyResponse: "The model returned an empty summary."
        }
    }
}

enum MeetingSummarizer {
    enum Availability: Equatable, Sendable {
        case ready, preparing, unavailable(String)

        var message: String? {
            switch self {
            case .ready: nil
            case .preparing: "macOS is preparing the Apple Intelligence model. You can check setup in System Settings → Apple Intelligence & Siri."
            case .unavailable(let reason): reason
            }
        }
    }

    static func availability() -> Availability {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .ready
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable("Turn on Apple Intelligence in System Settings.")
            case .unavailable(.modelNotReady): return .preparing
            case .unavailable: return .unavailable("Apple Intelligence is unavailable on this Mac.")
            @unknown default: return .unavailable("Apple Intelligence is unavailable on this Mac.")
            }
        }
        #endif
        return .unavailable("Apple Intelligence summaries require macOS 26 or later and a compatible build.")
    }

    @MainActor
    static func watchAvailability(_ update: (Availability) -> Void) async {
        while !Task.isCancelled {
            let status = await Task.detached { availability() }.value
            guard !Task.isCancelled else { return }
            update(status)
            guard status == .preparing else { return }
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return }
        }
    }

    static func generate(_ transcript: String, context: String, model: SummaryModel, prompt: String) async throws -> String {
        let instructions = SummaryPrompt.instructions(for: prompt)
        if model.usesOpenAI {
            let key = try OpenAIKey.load(for: .summary)
            let client = OpenAISummaryClient(model: model, key: key)
            return try await summarizeSections(transcript[...], requestByteLimit: 120_000, respond: { source, merging in
                try await client.respond(instructions: instructions, input: input(for: source, context: context, merging: merging))
            }, isContextOverflow: { ($0 as? OpenAISummaryError) == .contextOverflow })
        }
        if let reason = availability().message { throw MeetingSummaryError.unavailable(reason) }
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return try await summarizeSections(transcript[...], respond: { source, merging in
                try await respond(to: source, context: context, merging: merging, instructions: instructions)
            }, isContextOverflow: isContextOverflow)
        }
        #endif
        throw MeetingSummaryError.unavailable("Apple Intelligence is unavailable in this build.")
    }

    static func summarizeSections(_ transcript: Substring,
                                  requestByteLimit: Int = 10_000,
                                  respond: (String, Bool) async throws -> String,
                                  isContextOverflow: (Error) -> Bool) async throws -> String {
        try Task.checkCancellation()
        // Keep requests bounded and split further if the model's token budget is exceeded.
        if transcript.utf8.count <= requestByteLimit || transcript.count <= 1 {
            do {
                return try await respond(String(transcript), false)
            } catch {
                guard isContextOverflow(error), transcript.count > 1 else { throw error }
            }
        }
        let middle = transcript.index(transcript.startIndex, offsetBy: transcript.count / 2)
        let boundary = transcript[middle...].prefix(300).firstIndex(of: "\n")
            ?? transcript[..<middle].suffix(300).lastIndex(of: "\n")
        let split = boundary.flatMap { $0 > transcript.startIndex && $0 < transcript.endIndex ? $0 : nil } ?? middle
        let first = try await summarizeSections(transcript[..<split], requestByteLimit: requestByteLimit,
                                               respond: respond, isContextOverflow: isContextOverflow)
        let second = try await summarizeSections(transcript[split...], requestByteLimit: requestByteLimit,
                                                respond: respond, isContextOverflow: isContextOverflow)
        return try await respond([first, second].joined(separator: "\n\n"), true)
    }

    static func input(for source: String, context: String, merging: Bool) throws -> String {
        let operation = merging
            ? "Combine these chronological section notes using the requested format. Remove repetition and preserve the distinct decisions and commitments relevant to the summary."
            : "Summarize the meeting transcript."
        let key = merging ? "section notes" : "transcript"
        let encoded = try JSONEncoder().encode([key: source, "meeting context": context])
        return operation + "\n\nSource (JSON):\n" + String(decoding: encoded, as: UTF8.self)
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private static func respond(to source: String, context: String, merging: Bool, instructions: String) async throws -> String {
        try Task.checkCancellation()
        let session = LanguageModelSession(model: .default, instructions: instructions)
        let input = try input(for: source, context: context, merging: merging)
        let response = try await session.respond(to: input,
            options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 800))
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw MeetingSummaryError.emptyResponse }
        return text
    }

    @available(macOS 26, *)
    private static func isContextOverflow(_ error: Error) -> Bool {
        if #available(macOS 27, *) {
            if let modelError = error as? LanguageModelError,
               case .contextSizeExceeded = modelError { return true }
        } else if let generationError = error as? LanguageModelSession.GenerationError,
                  case .exceededContextWindowSize = generationError {
            return true
        }
        return false
    }
    #endif
}
