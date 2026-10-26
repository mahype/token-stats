#if os(iOS)
import SwiftUI
import TokenStatsCore
import WidgetKit

/// Sperrbildschirm und StandBy (Issue #11): rund die Gauge des knappsten Limits, rechteckig
/// Session und Woche mit Reset, inline „Claude 62 % · Reset 14:30“.
struct LockScreenLimitsView: View {
    let entry: LimitsEntry
    @Environment(\.widgetFamily) private var family

    private var provider: WidgetSnapshot.Provider? {
        entry.snapshot.flatMap { LimitsWidgetView.resolve($0, provider: entry.provider) }
    }

    private var tightest: LimitWindow? { provider?.snapshot?.tightestWindow }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: min(max(tightest?.percent ?? 0, 0), 1)) {
                Text(provider?.name.prefix(2) ?? "–")
            } currentValueLabel: {
                Text(tightest.map { "\(Int(($0.percent * 100).rounded()))" } ?? "–")
                    .font(.system(size: 15, weight: .semibold))
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(provider?.name ?? "Token Stats").font(.headline)
                if let windows = provider?.snapshot?.windows, !windows.isEmpty {
                    ForEach(windows.prefix(2)) { window in
                        Text(line(window)).font(.caption).lineLimit(1)
                    }
                } else {
                    Text("Token Stats öffnen").font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Text(inline)
        }
    }

    private func line(_ window: LimitWindow) -> String {
        var text = "\(window.name) \(Format.percent(window.percent))"
        if let reset = window.resetsAt { text += " · Reset \(Format.reset(reset, now: entry.date))" }
        return text
    }

    private var inline: String {
        guard let provider, let tightest else { return "Token Stats öffnen" }
        var text = "\(provider.name) \(Format.percent(tightest.percent))"
        if let reset = tightest.resetsAt { text += " · Reset \(Format.reset(reset, now: entry.date))" }
        return text
    }
}
#endif
