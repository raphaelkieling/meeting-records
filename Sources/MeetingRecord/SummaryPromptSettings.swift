import SwiftUI

struct SummaryPromptSettings: View {
    @AppStorage(SummaryPrompt.libraryKey) private var promptLibrary = Data()
    @AppStorage(SummaryPrompt.legacyPreferenceKey) private var legacyPrompt = ""
    @State private var editing: SummaryPrompt?
    @State private var pendingRemoval: SummaryPrompt?
    @State private var saveError: String?

    private var prompts: [SummaryPrompt] {
        SummaryPrompt.library(from: promptLibrary, legacyText: legacyPrompt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SettingsHeading("Summary Prompts")
                Spacer()
                Button("Add Prompt…", systemImage: "plus") {
                    editing = SummaryPrompt(id: UUID().uuidString, name: "", text: "")
                }
            }
            ForEach(prompts) { prompt in
                HStack(spacing: 12) {
                    Button { editing = prompt } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: "doc.text").foregroundStyle(Color.meetingAccent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(prompt.name).font(.body.weight(.medium))
                                Text(prompt.text).font(.callout).foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "pencil").foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit \(prompt.name)")
                    if prompt.builtIn == nil {
                        Button("Remove \(prompt.name)", systemImage: "trash", role: .destructive) {
                            pendingRemoval = prompt
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }

            if let saveError {
                Text(saveError).font(.caption).foregroundStyle(.red)
            }
        }
        .sheet(item: $editing) { prompt in
            SummaryPromptEditSheet(prompt: prompt, existing: prompts, save: save)
        }
        .alert("Remove Summary Prompt?", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        ), presenting: pendingRemoval) { prompt in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                persist(prompts.filter { $0.id != prompt.id })
            }
        } message: { prompt in
            Text("Remove “\(prompt.name)” from the prompt picker?")
        }
    }

    private func save(_ prompt: SummaryPrompt) {
        var updated = prompts
        if let index = updated.firstIndex(where: { $0.id == prompt.id }) {
            updated[index] = prompt
        } else {
            updated.append(prompt)
        }
        persist(updated)
    }

    private func persist(_ prompts: [SummaryPrompt]) {
        do {
            promptLibrary = try JSONEncoder().encode(prompts)
            saveError = nil
        } catch {
            saveError = "Could not save summary prompts. \(error.localizedDescription)"
        }
    }
}

private struct SummaryPromptEditSheet: View {
    let existing: [SummaryPrompt]
    let save: (SummaryPrompt) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: SummaryPrompt

    init(prompt: SummaryPrompt, existing: [SummaryPrompt], save: @escaping (SummaryPrompt) -> Void) {
        self.existing = existing
        self.save = save
        _draft = State(initialValue: prompt)
    }

    var body: some View {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let duplicate = existing.contains {
            $0.id != draft.id && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        VStack(alignment: .leading, spacing: 12) {
            Text(existing.contains { $0.id == draft.id } ? "Edit Summary Prompt" : "Add Summary Prompt")
                .font(.headline)
            if draft.builtIn == nil {
                TextField("Name", text: $draft.name).textFieldStyle(.roundedBorder)
            } else {
                Text(draft.name).font(.body.weight(.medium))
            }
            HStack {
                SettingsHeading("Prompt")
                Spacer()
                if let original = draft.builtIn {
                    Button("Reset to Default") { draft.text = original.text }
                        .disabled(draft.text == original.text)
                }
            }
            SettingsPromptEditor(text: $draft.text, label: "Prompt", height: 250)
            if duplicate {
                Text("A prompt with this name already exists.")
                    .font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save(SummaryPrompt(id: draft.id, name: name, text: text))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || text.isEmpty || duplicate)
            }
        }
        .padding(22)
        .frame(width: 580)
    }
}
