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
                Text("Summary Prompts").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Add Prompt…", systemImage: "plus") {
                    editing = SummaryPrompt(id: UUID().uuidString, name: "", text: "")
                }
            }
            Text("Choose a saved prompt when you generate a summary.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(prompts) { prompt in
                HStack {
                    Text(prompt.name).lineLimit(1)
                    Spacer()
                    Button { editing = prompt } label: { Image(systemName: "pencil") }
                        .help("Edit Prompt")
                        .accessibilityLabel("Edit \(prompt.name)")
                    if prompt.builtIn == nil {
                        Button(role: .destructive) { pendingRemoval = prompt } label: {
                            Image(systemName: "trash")
                        }
                        .help("Remove Prompt")
                        .accessibilityLabel("Remove \(prompt.name)")
                    }
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
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
                TextField("Name", text: $draft.name)
            } else {
                Text(draft.name).font(.subheadline.weight(.medium))
            }
            HStack {
                Text("Prompt").font(.subheadline.weight(.medium))
                Spacer()
                if let original = draft.builtIn {
                    Button("Reset to Default") { draft.text = original.text }
                        .disabled(draft.text == original.text)
                }
            }
            TextEditor(text: $draft.text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary).allowsHitTesting(false) }
                .frame(height: 156)
                .accessibilityLabel("Prompt")
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
        .frame(width: 480)
    }
}
