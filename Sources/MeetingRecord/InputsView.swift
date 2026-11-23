import SwiftUI

struct InputsView: View {
    let meetingID: UUID
    let store: MeetingStore
    let revision: Int
    @StateObject private var playback = RecordingPlayback()
    @State private var recordings: [Recording]?
    @State private var error: String?

    private struct LoadKey: Equatable {
        let meetingID: UUID
        let revision: Int
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error {
                    Text(error).foregroundStyle(.red)
                } else if let recordings {
                    if let playbackError = playback.error {
                        Text(playbackError)
                            .foregroundStyle(.red)
                    }
                    if recordings.isEmpty {
                        Text("No inputs yet.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(recordings.enumerated()), id: \.element.id) { index, recording in
                        card(for: recording, index: index)
                    }
                } else {
                    ProgressView().controlSize(.small).accessibilityLabel("Loading inputs")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 20)
        }
        .onDisappear { playback.stop() }
        .task(id: LoadKey(meetingID: meetingID, revision: revision)) {
            do {
                let values = try await store.recordings(for: meetingID)
                guard !Task.isCancelled else { return }
                recordings = values
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
        let playing = playback.activeID == recording.id
        let action = playing ? "Stop" : "Play"

        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Label(title, systemImage: "waveform")
                    .font(.headline)
                if recording.state == .interrupted {
                    Text("Interrupted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                Button {
                    playback.toggle(recording.id, store: store)
                } label: {
                    Image(systemName: playing ? "stop.fill" : "play.fill")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("\(action) \(title)")
                .help(action)

                Text(recording.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary)
                .allowsHitTesting(false)
        }
    }
}
