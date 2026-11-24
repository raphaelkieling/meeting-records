import EventKit
import SwiftUI

@MainActor
struct CalendarView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = EKEventStore()
    @State private var access = EKEventStore.authorizationStatus(for: .event)
    @State private var events: [EKEvent] = []
    @State private var start = Calendar.current.startOfDay(for: .now)
    @State private var error: String?
    @State private var hasMoreAbove = false
    @State private var hasMoreBelow = false
    let createMeeting: (String, String?, Date, String) -> Void
    init(initialDate: Date? = nil, createMeeting: @escaping (String, String?, Date, String) -> Void) {
        self.createMeeting = createMeeting
        _start = State(initialValue: Calendar.current.startOfDay(for: initialDate ?? .now))
    }

    private var today: Date { Calendar.current.startOfDay(for: .now) }
    private var end: Date { Calendar.current.date(byAdding: .day, value: 1, to: start)! }
    private var isToday: Bool { Calendar.current.isDate(start, inSameDayAs: today) }

    var body: some View {
        Group {
            if access == .fullAccess {
                agenda
            } else {
                VStack(spacing: 12) {
                    MeetingEmptyState("Calendar Access Required", icon: "calendar", detail: "Allow access to see events and create meetings from your agenda.")
                    Button("Allow Calendar Access", systemImage: "calendar.badge.plus") { Task { await requestAccess() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Button { start = Calendar.current.date(byAdding: .day, value: -1, to: start)!; loadEvents() } label: {
                    Image(systemName: "chevron.left").frame(width: 22, height: 22)
                }.help("Previous day")
                Text(start, format: .dateTime.weekday(.wide).month(.wide).day().year())
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 220, alignment: .center)
                Button { start = Calendar.current.date(byAdding: .day, value: 1, to: start)!; loadEvents() } label: {
                    Image(systemName: "chevron.right").frame(width: 22, height: 22)
                }.help("Next day")
                Button("Today", systemImage: "calendar") { start = today; loadEvents() }
                    .disabled(isToday)
                Spacer()
            }
            if let error { Text(error).foregroundStyle(.red) }
            if events.isEmpty {
                Spacer()
                MeetingEmptyState("No Calendar Events", icon: "calendar", detail: "There are no events on this day.")
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(dayGroups, id: \.date) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                                    .font(.headline).foregroundStyle(.secondary)
                                ForEach(group.events, id: \.eventIdentifier) { event in eventCard(event) }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .scrollView) } action: { frame in
                        hasMoreAbove = frame.minY < -1
                        hasMoreBelow = frame.maxY > 1
                    }
                }
                .scrollIndicators(.never)
                .mask {
                    VStack(spacing: 0) {
                        if hasMoreAbove {
                            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 24)
                        }
                        Rectangle()
                        if hasMoreBelow {
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 28)
                        }
                    }
                }
            }
        }
        .onAppear(perform: loadEvents)
    }

    private var dayGroups: [(date: Date, events: [EKEvent])] {
        Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.startDate) }
            .map { (date: $0.key, events: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private func eventCard(_ event: EKEvent) -> some View {
        let past = event.endDate < .now
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(past ? Color.secondary.opacity(0.3) : Color(event.calendar.cgColor))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(event.title ?? "Untitled Event").font(.body.weight(.semibold))
                    .foregroundStyle(past ? .secondary : .primary)
                HStack(spacing: 8) {
                    Text(event.startDate ?? .now, format: .dateTime.hour().minute())
                    Text("·")
                    Text(event.calendar.title)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.turn.down.right")
                .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(minHeight: 66)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(count: 2) {
            createMeeting(event.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? event.title! : "Untitled Event",
                          event.notes, event.startDate ?? .now, event.calendar.title)
        }
        .help("Double-click to create a meeting")
        .accessibilityHint("Double-click to create a meeting with this title and description")
    }

    private func refresh() async {
        access = EKEventStore.authorizationStatus(for: .event)
        if access == .fullAccess { loadEvents() }
    }

    private func requestAccess() async {
        do {
            _ = try await store.requestFullAccessToEvents()
            access = EKEventStore.authorizationStatus(for: .event)
            loadEvents()
        } catch { self.error = error.localizedDescription }
    }

    private func loadEvents() {
        guard access == .fullAccess else { return }
        events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .sorted { $0.startDate < $1.startDate }
    }
}
