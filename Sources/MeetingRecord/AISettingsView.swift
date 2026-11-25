import SwiftUI

enum AISettings {
    enum Feature { case chat, summary }

    static let defaultModelKey = "defaultAIModel"
    static let chatModelKey = "selectedMeetingChatModel"

    static func resolve(_ override: String, defaultModel: String) -> SummaryModel {
        SummaryModel(rawValue: override) ?? SummaryModel(rawValue: defaultModel) ?? .appleIntelligence
    }

    static func model(for feature: Feature) -> SummaryModel {
        let defaults = UserDefaults.standard
        let key = feature == .chat ? chatModelKey : SummaryModel.preferenceKey
        return resolve(defaults.string(forKey: key) ?? "", defaultModel: defaults.string(forKey: defaultModelKey) ?? "")
    }
}

enum MeetingChatSettings {
    static let instructionsKey = "meetingChatInstructions"
    static let defaultInstructions = "Answer concisely. Use relevant meeting transcript evidence and cite it. If the meetings do not establish an answer, say so."
}

struct AISettingsView: View {
    @AppStorage(AISettings.defaultModelKey) private var defaultModel = SummaryModel.appleIntelligence.rawValue
    @AppStorage(AISettings.chatModelKey) private var chatModel = ""
    @AppStorage(SummaryModel.preferenceKey) private var summaryModel = ""
    @AppStorage(MeetingChatSettings.instructionsKey) private var instructions = MeetingChatSettings.defaultInstructions
    @State private var draftKey = ""
    @State private var keyError: String?
    @State private var hasKey = OpenAIKey.hasConfiguredKey
    @State private var isChangingKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsHeading("Models")
            modelRow("Default Model", selection: $defaultModel, inheritsDefault: false)
            modelRow("Chat", selection: $chatModel)
            modelRow("Summary", selection: $summaryModel)
            if [chatModel, summaryModel].contains(where: { !AISettings.resolve($0, defaultModel: defaultModel).usesOpenAI }) {
                AppleIntelligenceAvailability()
            }
            Divider()
            SettingsHeading("OpenAI")
            SettingsNote("GPT sends relevant meeting data to OpenAI. API usage is billed separately from ChatGPT.")
            HStack {
                SecureField(hasKey ? "Replace with a shared API key" : "OpenAI API key", text: $draftKey)
                    .textFieldStyle(.roundedBorder)
                Button("Save Key") { changeKey(remove: false) }
                    .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if hasKey {
                    Button(sharedKey ? "Remove Key" : "Stop Using Existing Keys", role: .destructive) {
                        changeKey(remove: true)
                    }
                }
            }
            .disabled(isChangingKey)
            if let keyError {
                Text(keyError).font(.caption).foregroundStyle(.red)
            } else if hasKey {
                SettingsNote(sharedKey ? "Shared API key saved in Keychain." : "Existing keys still work. Save a shared key to use it for Chat and Summary.")
            }
            Divider()
            SettingsHeading("Chat Instructions")
            SettingsPromptEditor(text: $instructions, label: "Chat instructions", height: 170)
            Divider()
            SummaryPromptSettings()
        }
    }

    private var sharedKey: Bool { UserDefaults.standard.bool(forKey: OpenAIKey.savedPreferenceKey) }

    private func modelRow(_ title: LocalizedStringKey, selection: Binding<String>,
                          inheritsDefault: Bool = true) -> some View {
        LabeledContent(title) {
            Picker(title, selection: selection) {
                if inheritsDefault { Text("Use Default").tag("") }
                modelOptions
            }
            .labelsHidden()
        }
    }

    private var modelOptions: some View {
        ForEach(SummaryModel.allCases, id: \.rawValue) { model in
            Text(model.displayName).tag(model.rawValue)
        }
    }

    private func changeKey(remove: Bool) {
        let key = draftKey
        isChangingKey = true
        keyError = nil
        Task {
            defer { isChangingKey = false }
            do {
                try await Task.detached {
                    if remove { try OpenAIKey.remove() }
                    else { try OpenAIKey.save(key) }
                }.value
                hasKey = OpenAIKey.hasConfiguredKey
                draftKey = ""
            } catch {
                keyError = error.localizedDescription
            }
        }
    }
}
