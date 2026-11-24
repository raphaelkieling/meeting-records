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
    @StateObject private var playback = RecordingPlayback()
    @State private var didReveal = false
    @State private var highlightedID: UUID?
    @State private var recordings: [Recording]?
    @State private var error: String?
    @State private var statuses: [UUID: TranscriptStatus] = [:]

    private struct LoadKey: Equatable {
        let meetingID: UUID
        let revision: Int
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    } else if let recordings {
                        if let calendarEventDate {
                            calendarInput(date: calendarEventDate, calendarName: calendarName ?? "Calendar")
                        }
                        if let playbackError = playback.error {
                            Text(playbackError)
                                .foregroundStyle(.red)
                        }
                        if !recordings.isEmpty && !transcription.isReady {
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
        .task(id: transcription.revision) {
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
        let status = statuses[recording.id]?.status ?? .pending
        let highlighted = revealLatest && highlightedID == recording.id
        let active = recording.endedAt == nil
        let playing = playback.activeID == recording.id
        let action = playing ? "Stop" : "Play"

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform")
                .font(.title3)
                .foregroundStyle(Color.meetingAccent)
                .frame(width: 38, height: 38)
                .background(Color.meetingAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title).font(.headline)
                    Spacer(minLength: 8)
                    Button {
                        playback.toggle(recording.id, store: store)
                    } label: {
                        Image(systemName: playing ? "stop.fill" : "play.fill")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.bordered)
                    .disabled(active)
                    .accessibilityLabel("\(action) \(title)")
                    .help(active ? "Playback is available after recording." : action)
                }
                HStack(spacing: 8) {
                    Text(status.rawValue)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                        .accessibilityLabel("Transcription: \(status.rawValue)")
                    Spacer(minLength: 8)
                    Text(recording.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = statuses[recording.id]?.error {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("Retry Transcription") { Task { await transcription.retry() } }
                        .buttonStyle(.link).font(.caption)
                }
                if recording.state == .interrupted {
                    Text("Interrupted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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

    private func calendarInput(date: Date, calendarName: String) -> some View {
        Button { openCalendar(date) } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar").font(.title3).foregroundStyle(Color.meetingAccent)
                    .frame(width: 38, height: 38)
                    .background(Color.meetingAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calendar Event").font(.headline).foregroundStyle(.primary)
                    Text("\(calendarName) · \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.meetingAccent.opacity(0.45), lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("Show this event in Calendar")
    }
}
