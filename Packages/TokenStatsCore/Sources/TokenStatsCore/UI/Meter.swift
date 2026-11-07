import SwiftUI

/// Eine Meter-Zeile mit Balken, Pace-Marke und Reset-Zeit (SPEC §3.4) – im Popover und
/// in den Widgets dieselbe. `compact` rückt Schrift und Abstände für kleine Widgets zusammen.
public struct MeterRow: View {
    public let window: LimitWindow
    public var compact: Bool
    /// Zusatz wie „7 d, alle Modelle“ hinter dem Namen – in schmalen Widget-Spalten weggelassen.
    public var showScope: Bool
    /// Reset und Pace untereinander statt nebeneinander – fürs kleine Widget.
    public var stackDetails: Bool
    public var now: Date

    public init(window: LimitWindow, compact: Bool = false, showScope: Bool = true, stackDetails: Bool = false, now: Date = .now) {
        self.window = window
        self.compact = compact
        self.showScope = showScope
        self.stackDetails = stackDetails
        self.now = now
    }

    public var body: some View {
        let elapsed = window.elapsedFraction(now: now)
        VStack(spacing: compact ? 4 : 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.name).font(.system(size: compact ? 11.5 : 12.5, weight: .semibold))
                    + Text(showScope ? window.scopeNote.map { "  \($0)" } ?? "" : "").font(.system(size: compact ? 10 : 11)).foregroundColor(.secondary)
                Spacer()
                Text(Format.percent(window.percent))
                    .font(.system(size: compact ? 11.5 : 12.5, weight: .bold))
                    .foregroundStyle(window.severity.color)
                    .monospacedDigit()
            }
            MeterBar(percent: window.percent, elapsed: elapsed, color: window.severity.color)
                .frame(height: 6)
            // Ollama nennt keine Reset-Zeiten – dann bleibt die Zeile weg statt leer.
            if window.resetsAt != nil || elapsed != nil {
                let layout = stackDetails ? AnyLayout(VStackLayout(alignment: .leading, spacing: 1)) : AnyLayout(HStackLayout())
                layout {
                    if let resetsAt = window.resetsAt {
                        Text("Reset \(Format.reset(resetsAt, now: now))").lineLimit(1).minimumScaleFactor(compact ? 0.75 : 1)
                    }
                    if !stackDetails { Spacer(minLength: 6) }
                    if let elapsed, let windowLength = window.windowLength {
                        let onPace = abs(window.percent - elapsed) < Format.paceTolerance
                        Text(Format.pace(percent: window.percent, elapsed: elapsed, windowLength: windowLength))
                            .fontWeight(onPace ? .regular : .semibold)
                            .foregroundStyle(onPace ? Color.secondary : window.severity.color)
                            .lineLimit(1)
                            .minimumScaleFactor(compact ? 0.75 : 1)
                    }
                }
                .font(.system(size: compact ? 10 : 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Balken mit Pace-Marke; der Abstand zwischen Füllstand und Marke ist schraffiert (SPEC §3.4):
/// kräftig, wenn der Verbrauch der Zeit voraus ist, blass, wenn Kontingent liegen bleibt.
public struct MeterBar: View {
    public let percent: Double
    public let elapsed: Double?
    public let color: Color

    public init(percent: Double, elapsed: Double?, color: Color) {
        self.percent = percent
        self.elapsed = elapsed
        self.color = color
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let used = min(max(percent, 0), 1)
            let showGap = elapsed.map { abs(used - $0) >= Format.paceTolerance } ?? false
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Rectangle().fill(.quaternary)
                    Rectangle().fill(color).frame(width: width * min(used, elapsed ?? used))
                    if let elapsed, showGap {
                        let ahead = used > elapsed
                        Hatch()
                            .stroke(color, lineWidth: 1.5)
                            .background(color.opacity(ahead ? 0.55 : 0))
                            .opacity(ahead ? 1 : 0.6)
                            .frame(width: width * abs(used - elapsed))
                            .clipped()
                            .offset(x: width * min(used, elapsed))
                    }
                }
                .clipShape(Capsule())
                if let elapsed {
                    Rectangle()
                        .fill(.primary.opacity(0.45))
                        .frame(width: 2, height: 10)
                        .offset(x: width * elapsed - 1)
                }
            }
        }
    }
}

/// Diagonale Schraffur für die Pace-Fläche.
struct Hatch: Shape {
    var spacing: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}
