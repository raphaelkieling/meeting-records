import AppKit
import ImageIO
import SwiftUI

struct ScreenCaptureThumbnail: View {
    let capture: MeetingScreenCapture
    @State private var thumbnail: CGImage?

    var body: some View {
        Button {
            NSWorkspace.shared.open(capture.url)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 170, maxHeight: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                Label("\(capture.timestamp) · Screen Capture", systemImage: "photo")
                    .font(.caption)
            }
        }
        .buttonStyle(.plain)
        .help("Open Screen Capture")
        .task(id: capture.id) {
            let url = capture.url
            thumbnail = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil as CGImage? }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 340
                ] as CFDictionary)
            }.value
        }
    }
}
