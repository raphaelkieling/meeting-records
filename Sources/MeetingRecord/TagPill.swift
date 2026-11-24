import SwiftUI

extension TagColor {
    var title: String { rawValue.capitalized }

    var swiftUIColor: Color {
        switch self {
        case .gold: Color(red: 0.82, green: 0.56, blue: 0.20)
        case .lavender: Color(red: 0.43, green: 0.43, blue: 0.75)
        case .green: Color(red: 0.22, green: 0.53, blue: 0.36)
        case .coral: Color(red: 0.76, green: 0.36, blue: 0.31)
        case .blue: Color(red: 0.29, green: 0.45, blue: 0.58)
        case .rose: Color(red: 0.69, green: 0.31, blue: 0.43)
        }
    }
}

struct TagPill: View {
    let tag: Tag

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tag.color.swiftUIColor).frame(width: 6, height: 6)
            Text(tag.name)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(tag.color.swiftUIColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tag.color.swiftUIColor.opacity(0.13), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
