import SwiftUI

struct TagManagementView: View {
    let meeting: Meeting
    let store: MeetingStore
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var availableTags: [Tag] = []
    @State private var selectedTagIDs: Set<UUID>
    @State private var error: String?
    @State private var isSaving = false

    init(meeting: Meeting, store: MeetingStore, onSave: @escaping () -> Void) {
        self.meeting = meeting
        self.store = store
        self.onSave = onSave
        _selectedTagIDs = State(initialValue: Set(meeting.tags.map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Labels for \(meeting.name)").font(.headline)
            if availableTags.isEmpty {
                Text("Create a label from Labels in the sidebar.").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(availableTags) { tag in
                            Toggle(isOn: selection(for: tag)) {
                                HStack(spacing: 8) {
                                    Circle().fill(tag.color.swiftUIColor).frame(width: 10, height: 10)
                                    Text(tag.name)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .accessibilityLabel(tag.name)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 230)
            }

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Labels", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving || availableTags.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 430)
        .task { await loadTags() }
    }

    private func selection(for tag: Tag) -> Binding<Bool> {
        Binding(get: { selectedTagIDs.contains(tag.id) }, set: { isSelected in
            if isSelected { selectedTagIDs.insert(tag.id) }
            else { selectedTagIDs.remove(tag.id) }
        })
    }

    private func loadTags() async {
        do { availableTags = try await store.allTags() }
        catch { self.error = error.localizedDescription }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        Task {
            do {
                try await store.saveMeetingTags(meetingID: meeting.id, selectedTagIDs: selectedTagIDs,
                                                newTags: [])
                onSave()
                dismiss()
            } catch { self.error = error.localizedDescription }
            isSaving = false
        }
    }
}

extension TagColor {
    var title: String { rawValue.capitalized }

    var swiftUIColor: Color {
        switch self {
        case .gold: Color(red: 0.82, green: 0.56, blue: 0.20)
        case .lavender: Color(red: 0.43, green: 0.43, blue: 0.75)
        case .green: Color(red: 0.22, green: 0.53, blue: 0.36)
        case .coral: Color(red: 0.76, green: 0.36, blue: 0.31)
        case .blue: Color(red: 0.29, green: 0.45, blue: 0.58)
        case .rose: Color(red: 0.69, green: 0.31, blue: 0.43)
        }
    }
}

struct TagPill: View {
    let tag: Tag

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tag.color.swiftUIColor).frame(width: 6, height: 6)
            Text(tag.name)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(tag.color.swiftUIColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tag.color.swiftUIColor.opacity(0.13), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
