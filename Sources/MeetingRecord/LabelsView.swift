import SwiftUI

struct LabelsView: View {
    let store: MeetingStore
    let onChange: () -> Void

    @State private var labels: [Tag]?
    @State private var isEditing = false
    @State private var editingID: UUID?
    @State private var name = ""
    @State private var color: TagColor = .gold
    @State private var pendingDeletion: Tag?
    @State private var error: String?
    @State private var isSaving = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Organize meetings with shared labels.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("New Label", systemImage: "plus") { beginEditing() }
            }

            if !isEditing, let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }

            if let labels {
                if labels.isEmpty {
                    MeetingEmptyState("No Labels Yet", icon: "tag",
                                      detail: "Create a label to organize your meetings.")
                        .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(labels) { label in
                                row(label)
                                if label.id != labels.last?.id { Divider() }
                            }
                        }
                        .padding(.horizontal, 12)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            } else if error == nil {
                ProgressView("Loading labels…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Button("Try Again") { Task { await reload() } }
            }
        }
        .disabled(isSaving)
        .task { await reload() }
        .sheet(isPresented: $isEditing) {
            editor
                .focusEffectDisabled()
        }
        .alert("Delete Label?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        ), presenting: pendingDeletion) { label in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                changeLabels { try await store.deleteTag(label.id) }
            }
        } message: { label in
            Text("“\(label.name)” will be removed from every meeting that uses it.")
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(editingID == nil ? "New Label" : "Edit Label")
                .font(.headline)
            TextField("Label name", text: $name)
                .textFieldStyle(.plain)
                .focused($isNameFocused)
                .onSubmit(save)
                .padding(8)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 8) {
                Text("Color").font(.subheadline)
                HStack(spacing: 10) {
                    ForEach(TagColor.allCases, id: \.self) { option in
                        Button { color = option } label: {
                            Circle()
                                .fill(option.swiftUIColor)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    if color == option {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(option.title)
                        .accessibilityLabel(option.title)
                        .accessibilityAddTraits(color == option ? .isSelected : [])
                    }
                }
            }
            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    error = nil
                    isEditing = false
                }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 360)
        .disabled(isSaving)
        .interactiveDismissDisabled(isSaving)
        .onAppear { isNameFocused = true }
    }

    private func row(_ label: Tag) -> some View {
        HStack(spacing: 10) {
            Circle().fill(label.color.swiftUIColor).frame(width: 9, height: 9)
                .accessibilityHidden(true)
            Text(label.name)
            Spacer()
            Button { beginEditing(label) } label: {
                Image(systemName: "pencil")
            }
            .help("Edit Label")
            .accessibilityLabel("Edit \(label.name)")
            Button(role: .destructive) { pendingDeletion = label } label: {
                Image(systemName: "trash")
            }
            .help("Delete Label")
            .accessibilityLabel("Delete \(label.name)")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 9)
    }

    private func beginEditing(_ label: Tag? = nil) {
        editingID = label?.id
        name = label?.name ?? ""
        color = label?.color ?? .gold
        error = nil
        isEditing = true
    }

    private func save() {
        do {
            let tag = try Tag(id: editingID ?? UUID(), name: name, color: color)
            let updating = editingID != nil
            changeLabels { try await store.saveTag(tag, updating: updating) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func changeLabels(_ operation: @escaping () async throws -> Void) {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await operation()
                isEditing = false
                onChange()
                await reload()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func reload() async {
        error = nil
        do { labels = try await store.allTags() }
        catch { self.error = error.localizedDescription }
    }
}
