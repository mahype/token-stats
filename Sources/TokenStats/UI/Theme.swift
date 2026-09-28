import AppKit
import SwiftUI

/// Zustandsfarben aus dem Entwurf, je für Hell und Dunkel.
extension Severity {
    var nsColor: NSColor {
        switch self {
        case .ok: .dynamic(light: 0x2F8F5B, dark: 0x4CBE83)
        case .warn: .dynamic(light: 0xC1860F, dark: 0xE0A838)
        case .crit: .dynamic(light: 0xC04329, dark: 0xE7705A)
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}

extension NSColor {
    static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }

    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Roboterkopf aus dem Entwurf, in einem 24×24-Raster gezeichnet.
enum RobotGlyph {
    /// Linien: Kopf, Antenne, Mund, Ohren.
    static func strokes(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let t = transform(for: rect)
        path.addPath(CGPath(roundedRect: CGRect(x: 4, y: 8, width: 16, height: 11), cornerWidth: 3.2, cornerHeight: 3.2, transform: nil))
        path.move(to: CGPoint(x: 12, y: 4.2)); path.addLine(to: CGPoint(x: 12, y: 8))
        path.move(to: CGPoint(x: 9.5, y: 16.3)); path.addLine(to: CGPoint(x: 14.5, y: 16.3))
        path.move(to: CGPoint(x: 4, y: 11.5)); path.addLine(to: CGPoint(x: 2.4, y: 11.5))
        path.move(to: CGPoint(x: 20, y: 11.5)); path.addLine(to: CGPoint(x: 21.6, y: 11.5))
        return path.copy(using: [t]) ?? path
    }

    /// Flächen: Augen und Antennenkugel.
    static func fills(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let t = transform(for: rect)
        path.addEllipse(in: CGRect(x: 9 - 1.35, y: 13 - 1.35, width: 2.7, height: 2.7))
        path.addEllipse(in: CGRect(x: 15 - 1.35, y: 13 - 1.35, width: 2.7, height: 2.7))
        path.addEllipse(in: CGRect(x: 12 - 1.3, y: 3.4 - 1.3, width: 2.6, height: 2.6))
        return path.copy(using: [t]) ?? path
    }

    static func lineWidth(in rect: CGRect) -> CGFloat { 1.8 * rect.width / 24 }

    private static func transform(for rect: CGRect) -> CGAffineTransform {
        let scale = min(rect.width, rect.height) / 24
        return CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale)
    }
}

struct RobotIcon: View {
    var size: CGFloat = 15

    var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            context.stroke(
                Path(RobotGlyph.strokes(in: rect)),
                with: .foreground,
                style: StrokeStyle(lineWidth: RobotGlyph.lineWidth(in: rect), lineCap: .round, lineJoin: .round)
            )
            context.fill(Path(RobotGlyph.fills(in: rect)), with: .foreground)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
