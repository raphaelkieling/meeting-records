import SwiftUI
import AppKit

struct MeetingActions: View {
    let meeting: Meeting
    let canEdit: Bool
    let canDelete: Bool
    let openChat: () -> Void
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        Button("Chat About This Meeting", systemImage: "bubble.left.and.bubble.right", action: openChat)
        Divider()
        Button("Edit Meeting…", systemImage: "pencil", action: edit)
            .disabled(!canEdit)
        Button("Copy Link as Markdown", systemImage: "link", action: copyLink)
        Button("Delete Meeting…", role: .destructive, action: delete)
            .disabled(!canDelete)
    }

    func copyLink() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(MeetingLink.markdown(for: meeting), forType: .string)
    }
}

struct MeetingEditorView: View {
    let meeting: Meeting
    let store: MeetingStore
    let onSave: (Meeting) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description: String
    @State private var availableTags: [Tag]?
    @State private var selectedTagIDs: Set<UUID>
    @State private var error: String?
    @State private var isSaving = false

    init(meeting: Meeting, store: MeetingStore, onSave: @escaping (Meeting) -> Void) {
        self.meeting = meeting
        self.store = store
        self.onSave = onSave
        _name = State(initialValue: meeting.name)
        _description = State(initialValue: meeting.description ?? "")
        _selectedTagIDs = State(initialValue: Set(meeting.tags.map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Meeting").font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Title").font(.subheadline.weight(.medium))
                TextField("Title", text: $name, axis: .vertical)
                    .lineLimit(1...3)
                    .accessibilityLabel("Meeting title")
            }
            .disabled(isSaving)

            VStack(alignment: .leading, spacing: 6) {
                Text("Description").font(.subheadline.weight(.medium))
                TextEditor(text: $description)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(5)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    .frame(height: 110)
                    .accessibilityLabel("Meeting description")
            }
            .disabled(isSaving)

            VStack(alignment: .leading, spacing: 6) {
                Text("Labels").font(.subheadline.weight(.medium))
                if let availableTags {
                    if availableTags.isEmpty {
                        Text("Create labels from Labels in the sidebar.").foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(availableTags) { tag in
                                    Toggle(isOn: selection(for: tag)) {
                                        HStack(spacing: 8) {
                                            Circle().fill(tag.color.swiftUIColor).frame(width: 10, height: 10)
                                            Text(tag.name)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: min(CGFloat(availableTags.count) * 24, 108))
                    }
                } else if error != nil {
                    Button("Retry Loading Labels") { Task { await loadTags() } }
                } else {
                    ProgressView("Loading labels…").controlSize(.small)
                }
            }
            .disabled(isSaving)

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving || availableTags == nil)
            }
        }
        .padding(22)
        .frame(width: 460)
        .interactiveDismissDisabled(isSaving)
        .task { await loadTags() }
    }

    private func selection(for tag: Tag) -> Binding<Bool> {
        Binding(get: { selectedTagIDs.contains(tag.id) }, set: { isSelected in
            if isSelected { selectedTagIDs.insert(tag.id) }
            else { selectedTagIDs.remove(tag.id) }
        })
    }

    private func loadTags() async {
        error = nil
        do { availableTags = try await store.allTags() }
        catch { self.error = error.localizedDescription }
    }

    private func save() {
        guard !isSaving, availableTags != nil else { return }
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                let updated = try await store.updateMeeting(id: meeting.id, name: name, description: description,
                                                            selectedTagIDs: selectedTagIDs)
                onSave(updated)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
