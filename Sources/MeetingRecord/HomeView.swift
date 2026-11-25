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
    let openCalendar: (Date?) -> Void
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
                upcomingCard
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

    private var upcomingCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "calendar")
                .font(.title3)
                .foregroundStyle(Color.meetingAccent)
                .frame(width: 38, height: 38)
                .background(Color.meetingAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                if !currentEvents.isEmpty || nextEvent != nil {
                    ForEach(currentEvents, id: \.self) { event in
                        calendarEvent(event, label: "In Progress")
                    }
                    if let nextEvent {
                        calendarEvent(nextEvent, label: "Up Next")
                    }
                } else {
                    Text("Calendar").font(.headline).accessibilityAddTraits(.isHeader)
                    Text(calendarAvailable ? "No timed events in the next 7 days." : "Open Calendar to connect your agenda.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button("Open Calendar", action: { openCalendar(currentEvents.first?.startDate ?? nextEvent?.startDate) })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func calendarEvent(_ event: EKEvent, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.headline).accessibilityAddTraits(.isHeader)
            Text(event.meetingDetails.title).font(.title3.weight(.semibold)).lineLimit(2)
            Text("\(event.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())) · \(event.calendar.title)")
                .font(.callout).foregroundStyle(.secondary)
            Button("Create Meeting") {
                createMeeting(event.meetingDetails, event.startDate, event.calendar.title)
            }
            .disabled(!canCreateMeeting)
        }
        .padding(.bottom, 6)
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
