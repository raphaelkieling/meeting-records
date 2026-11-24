import SwiftUI

struct MeetingDescriptionEditorView: View {
    let meeting: Meeting
    let store: MeetingStore
    let onSave: (Meeting) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var error: String?
    @State private var isSaving = false

    init(meeting: Meeting, store: MeetingStore, onSave: @escaping (Meeting) -> Void) {
        self.meeting = meeting
        self.store = store
        self.onSave = onSave
        _draft = State(initialValue: meeting.description ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(meeting.name).font(.headline)
            TextEditor(text: $draft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(5)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 150)
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Add a short description for this meeting…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.top, 5)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Meeting description")
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Description", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        Task {
            do {
                let meeting = try await store.updateMeetingDescription(id: meeting.id, description: draft)
                onSave(meeting)
                dismiss()
            } catch { self.error = error.localizedDescription }
            isSaving = false
        }
    }
}
