import SwiftUI

enum Destination: Hashable {
    case home, settings, meeting(UUID)
}

enum MeetingLoadState {
    case loading, loaded([Meeting]), failed(String)
}

struct ContentView: View {
    @State private var destination: Destination = .home
    @State private var state: MeetingLoadState = .loading
    private let store = MeetingStore()

    private var title: String {
        switch destination {
        case .home: "Home"
        case .settings: "Configurações"
        case .meeting(let id):
            if case .loaded(let meetings) = state {
                meetings.first(where: { $0.id == id })?.name ?? "Meeting"
            } else { "Meeting" }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(destination: $destination, state: state) {
                Task { await loadMeetings() }
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).font(.largeTitle.bold()).textSelection(.enabled)
                    Text(message).foregroundStyle(.secondary)
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await loadMeetings() }
    }

    private var message: String {
        switch destination {
        case .home: "Seu espaço de reuniões."
        case .settings: "As configurações aparecerão aqui."
        case .meeting: "O espaço desta reunião está vazio."
        }
    }

    @MainActor
    private func loadMeetings() async {
        state = .loading
        do {
            let meetings = try await store.loadMeetings()
            state = .loaded(meetings)
            if case .meeting(let id) = destination, !meetings.contains(where: { $0.id == id }) {
                destination = .home
            }
        } catch {
            state = .failed(error.localizedDescription)
            if case .meeting = destination { destination = .home }
        }
    }
}
