import AppKit
import SwiftUI

struct CommandPaletteView: View {
    let meetings: [Meeting]
    let store: MeetingStore
    let indexRevision: Int
    let commands: [PaletteCommand]
    let activate: (PaletteItem) -> Void
    let startChat: (String) -> Void

    let dismiss: () -> Void
    @State private var query = ""
    @State private var tags: [Tag] = []
    @State private var tagError: String?
    @State private var transcriptMatches: [ChatEvidence] = []
    @State private var searchedQuery = ""
    @State private var transcriptError: String?
    @State private var selectedID: PaletteItem.ID?

    private struct SearchKey: Equatable {
        let question: String
        let indexRevision: Int
    }

    var body: some View {
        let question = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searching = !question.isEmpty && searchedQuery != question
        let matches = PaletteItem.search(query, meetings: meetings, tags: tags, commands: commands)
        let transcriptItems = searching ? [] : transcriptMatches.map(PaletteItem.transcript)
        let chatCommand: [PaletteItem] = question.isEmpty ? [] :
            [.command(PaletteCommand(title: "Ask across all meetings: \(question)", icon: "bubble.left.and.bubble.right", keywords: []) {
                startChat(question)
            })]
        let items = PaletteItem.Section.allCases.flatMap { section in
            (Array(matches.filter { $0.section == section }.prefix(10)) + transcriptItems + chatCommand)
                .filter { $0.section == section }
        }
        let activeIndex = items.firstIndex { $0.id == selectedID } ?? items.startIndex

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                PaletteQueryField(
                    onChange: { query = $0; selectedID = nil },
                    move: { offset in
                        guard !items.isEmpty else { return }
                        let index = min(max(activeIndex + offset, items.startIndex), items.count - 1)
                        selectedID = items[index].id
                    },
                    submit: { if items.indices.contains(activeIndex) { activate(items[activeIndex]) } },
                    cancel: { dismiss() }
                )
                .frame(height: 28)
            }
            .padding(.horizontal, 19)
            .padding(.vertical, 12)

            Divider()

            if searching {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).frame(width: 20)
                        .accessibilityHidden(true)
                    Text("Searching transcripts…")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 19)
                .padding(.vertical, 8)
            }

            if items.isEmpty {
                Text("No matches").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                results(items, selected: items[activeIndex].id)
            }

            if let transcriptError, !searching, !question.isEmpty {
                Text(transcriptError).font(.caption).foregroundStyle(.secondary).padding(8)
            }
            if let tagError {
                HStack {
                    Text("Could not load tags. \(tagError)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { Task { await loadTags() } }
                }
                .padding(12)
            }

            Divider()

            HStack(spacing: 14) {
                keyHint("↑ ↓", "Navigate")
                keyHint("↩", "Open")
                Spacer()
                keyHint("Esc", "Close")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
        }
        .frame(width: 560)
        .tint(.meetingAccent)
        .onExitCommand { dismiss() }
        .task { await loadTags() }
        .task(id: SearchKey(question: question, indexRevision: indexRevision)) {
            transcriptMatches = []
            transcriptError = nil
            guard !question.isEmpty else { searchedQuery = ""; return }
            do {
                try await Task.sleep(for: .milliseconds(120))
                let hits = try await store.findTranscriptPassages(question)
                try Task.checkCancellation()
                transcriptMatches = hits
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                transcriptError = "Could not search transcripts. \(error.localizedDescription)"
            }
            searchedQuery = question
        }
    }

    private func results(_ items: [PaletteItem], selected: PaletteItem.ID) -> some View {
        let sections = PaletteItem.Section.allCases.compactMap { section in
            let rows = items.filter { $0.section == section }
            return rows.isEmpty ? nil : (section: section, rows: rows)
        }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections, id: \.section) { group in
                        Text(group.section.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 10)
                            .frame(height: 26, alignment: .bottomLeading)
                            .padding(.bottom, 4)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.rows) { item in
                            row(item, selected: item.id == selected)
                                .id(item.id)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .background(alignment: .topLeading) {
                    MeetingScrollbar().frame(width: 0, height: 0).accessibilityHidden(true)
                }
            }
            .contentMargins(.vertical, 6, for: .scrollIndicators)
            .frame(height: min(324, CGFloat(items.count * 36 + sections.count * 30 + 8)))
            .onChange(of: selected) { _, id in proxy.scrollTo(id) }
        }
    }

    private func row(_ item: PaletteItem, selected: Bool) -> some View {
        Button { activate(item) } label: {
            HStack(spacing: 10) {
                switch item {
                case .meeting(let meeting):
                    resultIcon("text.bubble", color: .meetingAccent)
                    Text(meeting.name)
                    if let detail = meeting.description {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 180, alignment: .leading)
                            .layoutPriority(-1)
                    }
                case .transcript(let hit):
                    resultIcon("waveform", color: .meetingAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(hit.title) · \(hit.citation.timestamp)")
                        Text(hit.body).font(.caption).foregroundStyle(.secondary)
                    }
                case .tag(let tag):
                    resultIcon("tag", color: tag.color.swiftUIColor)
                    Text(tag.name)
                case .command(let command):
                    resultIcon(command.icon, color: .secondary)
                    Text(command.title)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "return")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .font(.body)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(selected ? Color.meetingAccent.opacity(0.14) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func resultIcon(_ icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .foregroundStyle(color)
            .frame(width: 20)
            .accessibilityHidden(true)
    }

    private func keyHint(_ key: String, _ title: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.caption2.monospaced())
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(title).font(.caption)
        }
        .foregroundStyle(.secondary)
    }

    private func loadTags() async {
        tagError = nil
        do { tags = try await store.allTags() }
        catch { tagError = error.localizedDescription }
    }
}

private struct PaletteQueryField: NSViewRepresentable {
    var onChange: (String) -> Void
    var move: (Int) -> Void
    var submit: () -> Void
    var cancel: () -> Void

    func makeNSView(context: Context) -> QueryField {
        let field = QueryField()
        field.placeholderString = "Search meetings, transcripts, tags, and commands"
        field.setAccessibilityLabel("Search meetings, transcripts, tags, and commands")
        field.font = .systemFont(ofSize: 18)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byClipping
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: QueryField, context: Context) {
        context.coordinator.field = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(field: self) }

    final class QueryField: NSTextField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                window.makeFirstResponder(self)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var field: PaletteQueryField

        init(field: PaletteQueryField) { self.field = field }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            field.onChange(textField.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch selector {
            case #selector(NSResponder.moveUp(_:)): field.move(-1)
            case #selector(NSResponder.moveDown(_:)): field.move(1)
            case #selector(NSResponder.insertNewline(_:)): field.submit()
            case #selector(NSResponder.cancelOperation(_:)): field.cancel()
            default: return false
            }
            return true
        }
    }
}
