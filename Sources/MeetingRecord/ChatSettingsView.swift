import SwiftUI

enum MeetingChatSettings {
    static let instructionsKey = "meetingChatInstructions"
    static let defaultInstructions = "Answer concisely. Use relevant meeting transcript evidence and cite it. If the meetings do not establish an answer, say so."
}

struct ChatSettingsView: View {
    @AppStorage(MeetingChatSettings.instructionsKey) private var instructions = MeetingChatSettings.defaultInstructions
    @AppStorage("selectedMeetingChatModel") private var selectedModel = SummaryModel.appleIntelligence.rawValue
    @AppStorage("openAIChatKeySaved") private var hasKey = false
    @State private var draftKey = ""
    @State private var keyStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Model").font(.headline)
            Picker("Chat model", selection: $selectedModel) {
                ForEach(SummaryModel.allCases, id: \.rawValue) { model in
                    Text(model.displayName).tag(model.rawValue)
                }
            }
            if SummaryModel(rawValue: selectedModel)?.usesOpenAI == true {
                SecureField(hasKey ? "Replace Chat API key" : "OpenAI API key", text: $draftKey)
                HStack {
                    Button("Save Chat Key") {
                        do { try OpenAIChatKey.save(draftKey); hasKey = true; draftKey = ""; keyStatus = "Chat API key saved in Keychain." }
                        catch { keyStatus = error.localizedDescription }
                    }.disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if hasKey { Button("Remove Key", role: .destructive) { do { try OpenAIChatKey.remove(); hasKey = false; keyStatus = "Chat API key removed." } catch { keyStatus = error.localizedDescription } } }
                }
                if let keyStatus { Text(keyStatus).font(.caption).foregroundStyle(.secondary) }
                Text("Meeting Chat sends your question and matching transcript excerpts to OpenAI. API usage is billed separately from ChatGPT.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Chat model settings are independent from Summarization.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Initial instructions").font(.headline)
            Text("These instructions guide every answer in Meeting Chat.").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $instructions)
                .font(.body)
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
