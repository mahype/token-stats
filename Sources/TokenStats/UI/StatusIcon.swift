import AppKit

/// Zeichnet das Menüleisten-Symbol in den drei Anzeige-Modi (SPEC §2).
enum StatusIcon {
    struct Input {
        var mode: MenuBarMode
        var severity: Severity?     // nil = noch keine Daten
        var percent: Double?
        var bars: [Double]          // oben Session, unten Woche
        var colored: Bool
        var paused: Bool            // Rate-Limit aktiv
    }

    static let height: CGFloat = 18

    static func image(_ input: Input) -> NSImage {
        // Ohne Zustandsfarbe oder ohne Daten: Template, damit Hell/Dunkel automatisch passt.
        let tint: NSColor? = input.colored ? input.severity?.nsColor : nil

        let glyph = CGRect(x: 0, y: 0, width: height, height: height)
        var width = glyph.width
        var text: NSAttributedString?

        switch input.mode {
        case .icon:
            break
        case .iconPercent:
            let label = input.percent.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
            let string = NSAttributedString(string: label, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold),
                .foregroundColor: tint ?? .black,
            ])
            text = string
            width += 3 + ceil(string.size().width)
        case .iconBars:
            width += 3 + 22
        }
        if input.paused { width += 2 + 7 }

        let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let color = (tint ?? .black).cgColor
            context.setStrokeColor(color)
            context.setFillColor(color)
            context.setLineWidth(RobotGlyph.lineWidth(in: glyph))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(RobotGlyph.strokes(in: glyph))
            context.strokePath()
            context.addPath(RobotGlyph.fills(in: glyph))
            context.fillPath()

            var x = glyph.maxX + 3
            if let text {
                let size = text.size()
                text.draw(at: NSPoint(x: x, y: (height - size.height) / 2))
                x += ceil(size.width)
            } else if input.mode == .iconBars {
                for (row, value) in input.bars.prefix(2).enumerated() {
                    let y = 5.5 + CGFloat(row) * 5
                    let track = CGRect(x: x, y: y, width: 22, height: 3)
                    context.setFillColor((tint ?? .black).withAlphaComponent(0.3).cgColor)
                    context.fill(track)
                    let barColor = tint == nil ? NSColor.black : Severity(percent: value).nsColor
                    context.setFillColor(barColor.cgColor)
                    context.fill(CGRect(x: x, y: y, width: 22 * min(max(value, 0), 1), height: 3))
                }
                x += 22
            }
            if input.paused {
                // Pause-Symbol: letzte Werte, Abfrage ruht wegen Rate-Limit.
                context.setFillColor(color)
                context.fill(CGRect(x: x + 2, y: 6, width: 2, height: 6))
                context.fill(CGRect(x: x + 6, y: 6, width: 2, height: 6))
            }
            return true
        }
        image.isTemplate = tint == nil
        return image
    }
}
