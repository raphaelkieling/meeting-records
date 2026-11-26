import AppKit
import SwiftUI

extension TagColor {
    private var folderPalette: (name: String, swatch: UInt32, light: UInt32, dark: UInt32) {
        switch self {
        case .gold: ("Amber", 0xF7AA21, 0x8A5200, 0xFFC052)
        case .lavender: ("Violet", 0x9955FF, 0x6D35C2, 0xBE98FF)
        case .green: ("Emerald", 0x17C982, 0x00764D, 0x46DD9C)
        case .coral: ("Vermilion", 0xF6504A, 0xB92D29, 0xFF8078)
        case .blue: ("Azure", 0x238DF8, 0x005FB7, 0x6AB3FF)
        case .rose: ("Magenta", 0xED46AB, 0xAD226F, 0xF98DCE)
        }
    }

    var folderColorName: String { folderPalette.name }

    var folderColor: Color {
        let palette = folderPalette
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return Self.folderNSColor(isDark ? palette.dark : palette.light)
        })
    }

    @MainActor
    func folderColorSwatch(isSelected: Bool) -> NSImage {
        let fill = Self.folderNSColor(folderPalette.swatch)
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            if isSelected {
                let check = NSBezierPath()
                check.move(to: NSPoint(x: 4, y: 7))
                check.line(to: NSPoint(x: 6, y: 5))
                check.line(to: NSPoint(x: 10, y: 9))
                check.lineWidth = 1.35
                check.lineCapStyle = .round
                NSColor.black.withAlphaComponent(0.8).setStroke()
                check.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func folderNSColor(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
