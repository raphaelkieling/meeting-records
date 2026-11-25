import SwiftUI

struct InputsView: View {
    let meetingID: UUID
    let store: MeetingStore
    let revision: Int
    let calendarEventDate: Date?
    let calendarName: String?
    @ObservedObject var transcription: TranscriptionCoordinator
    let revealLatest: Bool
    let openSettings: () -> Void
    let openCalendar: (Date) -> Void
    let deleteRecording: (Recording) async throws -> Void
    let removeCalendarLink: () async throws -> Void
    @StateObject private var playback = RecordingPlayback()
    @State private var didReveal = false
    @State private var highlightedID: UUID?
    @State private var recordings: [Recording]?
    @State private var error: String?
    @State private var statuses: [UUID: TranscriptStatus] = [:]
    @State private var pendingRemoval: Recording?
    @State private var removingID: UUID?
    @State private var confirmingCalendarRemoval = false
    @State private var removingCalendar = false
    @State private var removalError: String?

    private struct LoadKey: Equatable {
        let meetingID: UUID
        let revision: Int
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    } else if let recordings {
                        if let calendarEventDate {
                            calendarInput(date: calendarEventDate, calendarName: calendarName ?? "Calendar")
                        }
                        if let error = removalError ?? playback.error {
                            Text(error).foregroundStyle(.red)
                        }
                        if !transcription.isReady, recordings.contains(where: { statuses[$0.id]?.status != .complete }) {
                            Button("Install a model to transcribe audio", action: openSettings)
                                .buttonStyle(.link)
                        }
                        ForEach(Array(recordings.enumerated()), id: \.element.id) { index, recording in
                            card(for: recording, index: index).id(recording.id)
                        }
                    } else {
                        ProgressView().controlSize(.small).accessibilityLabel("Loading inputs")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .background(alignment: .topLeading) {
                    MeetingScrollbar().frame(width: 0, height: 0).accessibilityHidden(true)
                }
            }
            .contentMargins(.all, EdgeInsets(top: 0, leading: 0, bottom: 92, trailing: 12), for: .scrollContent)
            .contentMargins(.vertical, 6, for: .scrollIndicators)
            .task(id: highlightedID) {
                guard let highlightedID else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                proxy.scrollTo(highlightedID, anchor: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if error == nil, recordings?.isEmpty == true, calendarEventDate == nil {
                MeetingEmptyState("No inputs yet.", icon: "tray",
                                  detail: "Record this meeting to add audio.")
                    .offset(y: -20)
            }
        }
        .confirmationDialog("Remove Recording?", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        ), titleVisibility: .visible, presenting: pendingRemoval) { recording in
            Button("Remove Recording", role: .destructive) { remove(recording) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This permanently removes the audio and transcription for this recording.")
        }
        .confirmationDialog("Remove Calendar Link?", isPresented: $confirmingCalendarRemoval, titleVisibility: .visible) {
            Button("Remove Calendar Link", role: .destructive) { removeCalendar() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This unlinks the event from this meeting. The event will still be in Calendar.")
        }
        .task(id: [transcription.revision, revision]) {
            do {
                let values = try await store.transcriptStatuses(for: meetingID)
                guard !Task.isCancelled else { return }
                statuses = values
            } catch where !Task.isCancelled {
                self.error = "Could not load transcription status. \(error.localizedDescription)"
            } catch {}
        }
        .onDisappear { playback.stop() }
        .task(id: LoadKey(meetingID: meetingID, revision: revision)) {
            do {
                let values = try await store.recordings(for: meetingID, includeActive: true)
                guard !Task.isCancelled else { return }
                recordings = values
                if revealLatest && !didReveal {
                    highlightedID = values.last(where: { $0.endedAt != nil })?.id
                    didReveal = true
                }
                error = nil
            } catch {
                guard !Task.isCancelled else { return }
                playback.stop()
                self.error = "Could not load inputs. \(error.localizedDescription)"
            }
        }
    }

    private func card(for recording: Recording, index: Int) -> some View {
        let title = "Recording \(index + 1)"
        let transcript = statuses[recording.id]
        let active = recording.endedAt == nil
        let playing = playback.activeID == recording.id
        let highlighted = revealLatest && highlightedID == recording.id
        let status = switch transcript?.status ?? .pending {
        case .pending: transcript?.error == nil ? "Transcription pending" : "Transcription failed"
        case .transcribing: "Transcribing"
        case .complete: "Transcript ready"
        }
        let details = [
            recording.startedAt.formatted(date: .abbreviated, time: .shortened),
            active ? "Recording" : status,
            recording.state == .interrupted ? "Interrupted" : nil,
            playing ? "Playing" : nil
        ].compactMap { $0 }

        return inputCard(title: title, icon: "waveform", details: details, error: transcript?.error,
                         highlighted: highlighted) {
            Button {
                playback.toggle(recording.id, store: store)
            } label: {
                Label(playing ? "Stop Playback" : "Play Recording", systemImage: playing ? "stop.fill" : "play.fill")
            }
            .disabled(active || removingID == recording.id)
            if transcript?.error != nil {
                Button("Retry Transcription", systemImage: "arrow.clockwise") {
                    Task { await transcription.retry() }
                }
                .disabled(removingID == recording.id)
            }
            Divider()
            Button("Remove Recording…", systemImage: "trash", role: .destructive) {
                pendingRemoval = recording
            }
            .disabled(active || removingID != nil)
        }
    }

    private func calendarInput(date: Date, calendarName: String) -> some View {
        inputCard(title: "Calendar Event", icon: "calendar",
                  details: [calendarName, date.formatted(date: .abbreviated, time: .shortened)]) {
            Button("Open in Calendar", systemImage: "arrow.up.right") { openCalendar(date) }
            Divider()
            Button("Remove Calendar Link…", systemImage: "link.badge.minus", role: .destructive) {
                confirmingCalendarRemoval = true
            }
            .disabled(removingCalendar)
        }
    }

    private func inputCard<Actions: View>(title: String, icon: String, details: [String],
                                          error: String? = nil, highlighted: Bool = false,
                                          @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.meetingAccent)
                .frame(width: 34, height: 34)
                .background(Color.meetingAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(details.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            Menu(content: actions) {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 24, minHeight: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Actions for \(title)")
            .accessibilityLabel("Actions for \(title)")
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(highlighted ? Color.accentColor : Color.secondary.opacity(0.18),
                              lineWidth: highlighted ? 2 : 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    private func remove(_ recording: Recording) {
        guard removingID == nil else { return }
        removingID = recording.id
        removalError = nil
        if playback.activeID == recording.id { playback.stop() }
        Task {
            defer { removingID = nil }
            do {
                try await deleteRecording(recording)
            } catch {
                removalError = "Could not remove recording. \(error.localizedDescription)"
            }
        }
    }

    private func removeCalendar() {
        guard !removingCalendar else { return }
        removingCalendar = true
        removalError = nil
        Task {
            defer { removingCalendar = false }
            do {
                try await removeCalendarLink()
            } catch {
                removalError = "Could not remove calendar link. \(error.localizedDescription)"
            }
        }
    }
}
