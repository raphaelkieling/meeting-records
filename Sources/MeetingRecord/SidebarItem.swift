import Foundation

struct SidebarItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var parentID: UUID?
    var folder: Folder?

    struct Folder: Equatable, Sendable {
        let name: String
        let color: TagColor?
        var expanded: Bool
    }
}

extension Array where Element == SidebarItem {
    mutating func moveSidebarItem(_ id: UUID, to parentID: UUID?, before siblingID: UUID?) throws {
        guard let source = firstIndex(where: { $0.id == id }) else { throw SidebarMoveError.invalidTarget }
        if let siblingID {
            guard let sibling = first(where: { $0.id == siblingID }), sibling.parentID == parentID else {
                throw SidebarMoveError.invalidTarget
            }
        }

        if let parentID {
            let itemsByID = Dictionary(uniqueKeysWithValues: map { ($0.id, $0) })
            guard itemsByID[parentID]?.folder != nil else { throw SidebarMoveError.invalidTarget }
            var ancestor: UUID? = parentID
            while let current = ancestor {
                guard current != id else { throw SidebarMoveError.nestingCycle }
                ancestor = itemsByID[current]?.parentID
            }
        }
        guard id != siblingID else { return }

        var item = remove(at: source)
        item.parentID = parentID
        let insertion = siblingID.flatMap { id in firstIndex { $0.id == id } } ?? endIndex
        insert(item, at: insertion)
        if let parentID, let parent = firstIndex(where: { $0.id == parentID }) {
            self[parent].folder?.expanded = true
        }
    }
}

enum SidebarMoveError: LocalizedError {
    case invalidTarget, nestingCycle

    var errorDescription: String? {
        switch self {
        case .invalidTarget: "The destination is no longer available."
        case .nestingCycle: "A folder cannot be moved into itself or one of its folders."
        }
    }
}
