import EventKit
import SwiftUI

struct HomeView: View {
    let meetings: [Meeting]?
    let error: String?
    let recordedTime: TimeInterval?
    let completedTranscriptions: Int?
    let durationError: String?
    let open: (UUID) -> Void
    let retry: () -> Void
    let canRecord: Bool
    let record: () -> Void
    let canCreateMeeting: Bool
    let createMeeting: (CalendarEventDetails, Date, String) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var calendarStore = EKEventStore()
    @State private var currentEvents: [EKEvent] = []
    @State private var nextEvent: EKEvent?
    @State private var calendarAvailable = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Record a Meeting", systemImage: "record.circle", action: record)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canRecord)
                }
                calendarAgenda
                recentMeetings
                if meetings != nil && error == nil { libraryStats }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 16)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                refreshCalendar()
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            if scenePhase == .active { refreshCalendar() }
        }
    }

    private var calendarAgenda: some View {
        let events = currentEvents + (nextEvent.map { [$0] } ?? [])
        return VStack(alignment: .leading, spacing: 10) {
            Text("Calendar").font(.headline).accessibilityAddTraits(.isHeader)
            if events.isEmpty {
                Text(calendarAvailable ? "No timed events in the next 7 days." : "Connect your agenda from Calendar in the sidebar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(events, id: \.self) { event in
                        if event != events.first { Divider().padding(.horizontal, 14) }
                        calendarEvent(event, isInProgress: currentEvents.contains(event))
                    }
                }
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func calendarEvent(_ event: EKEvent, isInProgress: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.meetingDetails.title).font(.body.weight(.semibold)).lineLimit(2)
                    .accessibilityValue(isInProgress ? Text("In progress") : Text(""))
                Text("\(event.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())) · \(event.calendar.title)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                createMeeting(event.meetingDetails, event.startDate, event.calendar.title)
            } label: {
                Image(systemName: "plus")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.meetingAccent)
                    .frame(width: 26, height: 26)
                    .background(Color.meetingAccent.opacity(0.12), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.borderless)
            .disabled(!canCreateMeeting)
            .help("Create Meeting")
            .accessibilityLabel("Create Meeting")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isInProgress ? Color.meetingAccent.opacity(0.08) : .clear)
    }

    private var recentMeetings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Meetings").font(.headline).accessibilityAddTraits(.isHeader)
            if let error {
                Text("Could not load recent meetings. \(error)").foregroundStyle(.secondary)
                Button("Try Again", action: retry)
            } else if let meetings {
                if meetings.isEmpty {
                    Text("No meetings yet.").foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(meetings) { meeting in
                            if meeting.id != meetings.first?.id { Divider().padding(.leading, 42) }
                            recentRow(meeting)
                        }
                    }
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                }
            } else {
                ProgressView("Loading meetings…").controlSize(.small)
            }
        }
    }

    private func recentRow(_ meeting: Meeting) -> some View {
        Button { open(meeting.id) } label: {
            HStack(spacing: 10) {
                Image(systemName: "text.bubble")
                    .foregroundStyle(Color.meetingAccent).accessibilityHidden(true)
                Text(meeting.name).lineLimit(1)
                Spacer(minLength: 8)
                Text(meeting.createdAt, format: .dateTime.month(.abbreviated).day())
                    .font(.caption).foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .padding(.vertical, 10).padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onKeyPress(.return) { open(meeting.id); return .handled }
        .help(meeting.name)
    }

    private var libraryStats: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Library").font(.headline).accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: 10) {
                total("Time Recorded", value: timeLabel, icon: "clock")
                total("Completed Transcriptions", value: completedTranscriptions?.formatted(), icon: "text.alignleft")
            }
            if let durationError {
                Text(durationError).font(.caption).foregroundStyle(.secondary)
                Button("Try Again", action: retry)
            }
        }
    }

    private func refreshCalendar() {
        calendarAvailable = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        let now = Date.now
        guard calendarAvailable, let end = Calendar.current.date(byAdding: .day, value: 7, to: now) else {
            currentEvents = []
            nextEvent = nil
            return
        }
        let predicate = calendarStore.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = calendarStore.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
        currentEvents = events.filter { $0.startDate <= now && $0.endDate > now }
        nextEvent = events.first { $0.startDate > now }
    }

    private var timeLabel: String? {
        if let recordedTime {
            return Duration.seconds(recordedTime.rounded(.down))
                .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
        }
        return durationError == nil ? nil : "Unavailable"
    }

    private func total(_ title: String, value: String?, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.callout).foregroundStyle(.secondary)
            if let value {
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
