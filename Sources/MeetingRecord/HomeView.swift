import SwiftUI

struct HomeView: View {
    let meetings: [Meeting]?
    let error: String?
    let recordedTime: TimeInterval?
    let completedTranscriptions: Int?
    let durationError: String?
    let open: (UUID) -> Void
    let retry: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent Meetings").font(.headline)
                if let error {
                    Text("Could not load recent meetings. \(error)")
                        .foregroundStyle(.secondary)
                    Button("Try Again", action: retry)
                } else if let meetings {
                    if meetings.isEmpty {
                        Text("No meetings yet.").foregroundStyle(.secondary)
                    }
                    ForEach(meetings) { meeting in
                        Button { open(meeting.id) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "text.bubble").accessibilityHidden(true)
                                Text(meeting.name).lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .padding(12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled()
                        .onKeyPress(.return) { open(meeting.id); return .handled }
                        .onKeyPress(.space) { open(meeting.id); return .handled }
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                        .help(meeting.name)
                    }
                } else {
                    ProgressView("Loading meetings…").controlSize(.small)
                }
                if meetings != nil && error == nil {
                    HStack(alignment: .top, spacing: 28) {
                        total("Time Recorded", value: timeLabel)
                        total("Completed Transcriptions", value: completedTranscriptions?.formatted())
                    }
                    .padding(.top, 12)

                    if let durationError {
                        Text(durationError).font(.caption).foregroundStyle(.secondary)
                        Button("Try Again", action: retry)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var timeLabel: String? {
        if let recordedTime {
            return Duration.seconds(recordedTime.rounded(.down))
                .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
        }
        return durationError == nil ? nil : "Unavailable"
    }

    private func total(_ title: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let value {
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
