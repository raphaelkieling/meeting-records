import SwiftUI

struct SidebarView: View {
    @Binding var destination: Destination
    let state: MeetingLoadState
    let retry: () -> Void
    @FocusState private var focusedDestination: Destination?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            navigationButton("Home", icon: "house", target: .home)
            navigationButton("Configurações", icon: "gearshape", target: .settings)
            Text("Meetings").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.top, 16).padding(.horizontal, 8)
            switch state {
            case .loading:
                ProgressView("Carregando reuniões…").controlSize(.small).padding(8)
                Spacer()
            case .failed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Não foi possível carregar as reuniões").font(.callout)
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    Button("Tentar novamente", action: retry)
                }.padding(8)
                Spacer()
            case .loaded(let meetings) where meetings.isEmpty:
                Text("Nenhuma reunião").foregroundStyle(.secondary).padding(8)
                Spacer()
            case .loaded(let meetings):
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(meetings) { meeting in
                                navigationButton(meeting.name, icon: "text.bubble", target: .meeting(meeting.id))
                                    .id(Destination.meeting(meeting.id))
                            }
                        }.padding(2)
                    }
                    .onChange(of: focusedDestination) { _, target in
                        if let target { proxy.scrollTo(target) }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 240)
        .frame(maxHeight: .infinity)
        .background(.background.secondary)
        .onAppear { focusedDestination = .home }
        .onMoveCommand { direction in
            let meetings: [Meeting]
            if case .loaded(let values) = state { meetings = values } else { meetings = [] }
            let targets: [Destination] = [.home, .settings] + meetings.map { .meeting($0.id) }
            let index = targets.firstIndex(of: focusedDestination ?? .home) ?? 0
            switch direction {
            case .down: focusedDestination = targets[min(index + 1, targets.count - 1)]
            case .up: focusedDestination = targets[max(index - 1, 0)]
            default: break
            }
        }
    }

    private func navigationButton(_ title: String, icon: String, target: Destination) -> some View {
        Button { destination = target } label: {
            Label(title, systemImage: icon)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(destination == target ? Color.accentColor.opacity(0.16) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(focusedDestination == target ? Color.accentColor : .clear, lineWidth: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focusedDestination, equals: target)
        .onKeyPress(.return) { destination = target; return .handled }
        .onKeyPress(.space) { destination = target; return .handled }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(destination == target ? .isSelected : [])
    }
}
