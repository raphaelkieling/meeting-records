import SwiftUI

enum SidebarDropArea: Equatable {
    case before, inside, after

    init(y: CGFloat, height: CGFloat, isFolder: Bool) {
        let fraction = y / max(height, 1)
        if isFolder, fraction >= 0.30, fraction < 0.70 {
            self = .inside
        } else {
            self = fraction < 0.5 ? .before : .after
        }
    }

    func destination(on target: SidebarItem, in items: [SidebarItem]) -> (parent: UUID?, before: UUID?)? {
        switch self {
        case .before:
            return (target.parentID, target.id)
        case .inside:
            return (target.id, nil)
        case .after:
            // The line under an expanded folder is above its first child.
            if target.folder?.expanded == true, let child = items.first(where: { $0.parentID == target.id }) {
                return (target.id, child.id)
            }
            guard let index = items.firstIndex(where: { $0.id == target.id }) else { return nil }
            let next = items.suffix(from: items.index(after: index)).first { $0.parentID == target.parentID }
            return (target.parentID, next?.id)
        }
    }
}

enum SidebarDropRow: Hashable {
    case item(UUID)
    case rootEnd
}

struct SidebarDropFrames: PreferenceKey {
    static let coordinateSpace = "sidebar-drop-area"
    static var defaultValue: [SidebarDropRow: CGRect] { [:] }

    static func reduce(value: inout [SidebarDropRow: CGRect], nextValue: () -> [SidebarDropRow: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

extension View {
    func sidebarDropFrame(_ row: SidebarDropRow) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: SidebarDropFrames.self,
                    value: [row: geometry.frame(in: .named(SidebarDropFrames.coordinateSpace))])
            }
        }
    }
}
