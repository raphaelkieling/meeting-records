import SwiftUI

struct MeetingEmptyState<Icon: View>: View {
    let title: LocalizedStringKey
    let icon: Icon
    let detail: String?

    init(_ title: LocalizedStringKey, detail: String? = nil, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.icon = icon()
        self.detail = detail
    }

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
            } icon: {
                icon
            }
        } description: {
            if let detail {
                Text(detail)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension MeetingEmptyState where Icon == Image {
    init(_ title: LocalizedStringKey, icon: String, detail: String? = nil) {
        self.init(title, detail: detail) { Image(systemName: icon) }
    }
}
