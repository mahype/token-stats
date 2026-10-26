import SwiftUI

/// Eine Säule pro Tag, der heutige Tag hervorgehoben – Verbrauchsseite und Widget.
public struct DayChart: View {
    public let days: [UsageSummary.DayTotal]
    /// Ohne Wochentage und mit flacherem Rahmen, für Widgets.
    public var compact: Bool

    public init(days: [UsageSummary.DayTotal], compact: Bool = false) {
        self.days = days
        self.compact = compact
    }

    public var body: some View {
        let peak = max(days.map(\.tokens).max() ?? 0, 1)
        let showLabels = !compact && days.count <= 7
        HStack(alignment: .bottom, spacing: days.count > 14 ? 2 : (compact ? 4 : 6)) {
            ForEach(days) { day in
                let isToday = day.id == days.last?.id
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        VStack {
                            Spacer(minLength: 0)
                            UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                                .fill(Color.accentColor.opacity(isToday ? 1 : 0.55))
                                .frame(height: max(geo.size.height * CGFloat(day.tokens) / CGFloat(peak), day.tokens > 0 ? 2 : 0))
                        }
                    }
                    if showLabels {
                        Text(day.day.formatted(.dateTime.weekday(.abbreviated).locale(Format.locale)))
                            .font(.system(size: 9.5, weight: isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? .primary : .secondary)
                    }
                }
                .help("\(day.day.formatted(.dateTime.weekday(.wide).day().month().locale(Format.locale))): \(Format.tokens(day.tokens)) Tokens")
            }
        }
        .frame(height: compact ? nil : (showLabels ? 72 : 56))
    }
}
