import SwiftUI

struct SearchView: View {
    let store: MeetingStore
    let refreshKey: String
    let openMeeting: (UUID) -> Void

    @State private var text = ""
    @State private var tags: [Tag] = []
    @State private var tagLoadError: String?
    @State private var hasLoadedTags = false
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var results: [SearchResult] = []
    @State private var error: String?
    @State private var isSearching = false
    @State private var searchRevision = 0
    @State private var searchTask: Task<Void, Never>?
    @State private var isTagFilterPresented = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Find a moment across all your meetings.")
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search titles, descriptions, transcripts, and labels", text: $text)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .accessibilityLabel("Search meetings")
                        .onChange(of: text) { _, _ in scheduleSearch() }
                    if !text.isEmpty {
                        Button {
                            text = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                                .frame(width: 18, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Clear search")
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))

                Button {
                    isTagFilterPresented.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tag")
                        Text(selectedTagIDs.isEmpty ? "Labels" : "Labels (\(selectedTagIDs.count))")
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                }
                .buttonStyle(.plain)
                .help("Filter by all selected labels")
                .accessibilityLabel(selectedTagIDs.isEmpty ? "Filter by labels" : "Filter by \(selectedTagIDs.count) labels")
                .popover(isPresented: $isTagFilterPresented, arrowEdge: .bottom) {
                    tagFilter
                        .task(id: refreshKey) { await reloadTags() }
                }
            }
            .font(.callout)

            if !selectedTagIDs.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tags.filter { selectedTagIDs.contains($0.id) }) { TagPill(tag: $0) }
                    Spacer(minLength: 8)
                    Button("Clear labels") { selectedTagIDs = [] }
                        .buttonStyle(.link)
                        .font(.caption)
                        .fixedSize()
                }
            }

            if isSearching {
                ProgressView("Searching meetings…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                MeetingEmptyState("Search Unavailable", icon: "exclamationmark.magnifyingglass", detail: error)
                    .frame(maxWidth: .infinity)
            } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedTagIDs.isEmpty {
                MeetingEmptyState("Search Meetings", icon: "magnifyingglass",
                                  detail: "Search titles, descriptions, transcripts, or labels.")
                    .frame(maxWidth: .infinity)
            } else if results.isEmpty {
                MeetingEmptyState("No Matching Meetings", icon: "magnifyingglass",
                                  detail: "Try another phrase or clear a selected label.")
                    .frame(maxWidth: .infinity)
            } else {
                HStack {
                    Text("\(results.count) \(results.count == 1 ? "meeting" : "meetings")")
                    Spacer()
                    Text("Sorted by most recent")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(results) { result in
                            resultRow(result)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
            }
            Spacer(minLength: 0)
        }
        .task(id: refreshKey) {
            scheduleSearch()
        }
        .onChange(of: selectedTagIDs) { _, _ in scheduleSearch() }
        .onDisappear {
            searchTask?.cancel()
            isSearching = false
        }
    }

    private var tagFilter: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Match every selected label").font(.subheadline.weight(.semibold))
                Spacer()
                if !selectedTagIDs.isEmpty {
                    Button("Clear") { selectedTagIDs = [] }
                        .buttonStyle(.link)
                }
            }
            if let tagLoadError {
                Text(tagLoadError).font(.caption).foregroundStyle(.secondary)
            } else if !hasLoadedTags {
                ProgressView("Loading labels…").controlSize(.small)
            } else if tags.isEmpty {
                Text("Create a label from Labels in the sidebar.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(tags) { tag in
                    Toggle(isOn: selected(tag)) {
                        HStack(spacing: 8) {
                            Circle().fill(tag.color.swiftUIColor).frame(width: 9, height: 9)
                            Text(tag.name)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityLabel(tag.name)
                }
            }
        }
        .padding(14)
        .frame(width: 250, alignment: .leading)
    }

    private func selected(_ tag: Tag) -> Binding<Bool> {
        Binding(get: { selectedTagIDs.contains(tag.id) }, set: { isSelected in
            if isSelected { selectedTagIDs.insert(tag.id) }
            else { selectedTagIDs.remove(tag.id) }
        })
    }

    private func resultRow(_ result: SearchResult) -> some View {
        Button { openMeeting(result.meeting.id) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(result.meeting.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let description = result.meeting.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let excerpt = result.transcriptExcerpt {
                    Text(excerpt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 5) {
                    Text(result.meeting.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                    Spacer(minLength: 4)
                    ForEach(result.assignedTags) { tag in
                        TagPill(tag: tag).lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(result.meeting.name)
        .accessibilityValue(accessibilitySummary(for: result))
    }

    private func accessibilitySummary(for result: SearchResult) -> String {
        var values = [result.meeting.createdAt.formatted(date: .abbreviated, time: .omitted)]
        values.append(contentsOf: result.assignedTags.map(\.name))
        if let description = result.meeting.description { values.append(description) }
        if let excerpt = result.transcriptExcerpt { values.append(excerpt) }
        return values.joined(separator: ", ")
    }

    private func reloadTags() async {
        do {
            let availableTags = try await store.allTags()
            guard !Task.isCancelled else { return }
            tags = availableTags
            selectedTagIDs.formIntersection(availableTags.map(\.id))
            tagLoadError = nil
            hasLoadedTags = true
        } catch {
            guard !Task.isCancelled else { return }
            tagLoadError = error.localizedDescription
        }
    }

    @MainActor
    private func scheduleSearch() {
        searchRevision += 1
        let revision = searchRevision
        searchTask?.cancel()
        let query = SearchQuery(text: text, selectedTagIDs: selectedTagIDs)
        isSearching = !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !query.selectedTagIDs.isEmpty
        guard isSearching else {
            results = []
            error = nil
            return
        }
        searchTask = Task {
            do { try await Task.sleep(for: .milliseconds(180)) }
            catch { return }
            defer {
                if revision == searchRevision { isSearching = false }
            }
            guard !Task.isCancelled else { return }
            do {
                let results = try await store.searchMeetings(query)
                guard !Task.isCancelled, revision == searchRevision else { return }
                self.results = results
                error = nil
            } catch {
                guard !Task.isCancelled, revision == searchRevision else { return }
                self.error = error.localizedDescription
            }
        }
    }
}
