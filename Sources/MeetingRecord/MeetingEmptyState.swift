import SwiftUI

struct MeetingEmptyState: View {
    let title: LocalizedStringKey
    let icon: String
    var detail: String?

    init(_ title: LocalizedStringKey, icon: String, detail: String? = nil) {
        self.title = title
        self.icon = icon
        self.detail = detail
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(16)
        .offset(y: -24)
    }
}
