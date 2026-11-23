import AppKit
import SwiftUI

struct MeetingScrollbar: NSViewRepresentable {
    func makeNSView(context: Context) -> Installer { Installer() }

    func updateNSView(_ view: Installer, context: Context) {
        view.install()
    }

    final class Installer: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            install()
        }

        func install() {
            // SwiftUI can finish configuring its scroll view after mounting the content.
            DispatchQueue.main.async { [weak self] in
                guard let scrollView = self?.enclosingScrollView,
                      let current = scrollView.verticalScroller,
                      !(current is Scroller) else { return }
                let replacement = Scroller(frame: current.frame)
                replacement.controlSize = current.controlSize
                replacement.scrollerStyle = scrollView.scrollerStyle
                replacement.knobStyle = current.knobStyle
                scrollView.verticalScroller = replacement
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
    }

    private final class Scroller: NSScroller {
        override class var isCompatibleWithOverlayScrollers: Bool { true }

        override func drawKnob() {
            let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            drawCapsule(in: rect(for: .knob), width: 5, using: contrast ? 0.9 : 0.5)
        }

        override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
            drawCapsule(in: slotRect, width: 7, using: flag ? 0.18 : 0.09)
        }

        private func drawCapsule(in rect: NSRect, width: CGFloat, using opacity: CGFloat) {
            guard rect.width > 0, rect.height > 2 else { return }
            let width = min(width, rect.width)
            let shape = NSRect(x: rect.midX - width / 2, y: rect.minY + 1,
                               width: width, height: rect.height - 2)
            NSColor.labelColor.withAlphaComponent(opacity).setFill()
            NSBezierPath(roundedRect: shape, xRadius: width / 2, yRadius: width / 2).fill()
        }
    }
}
