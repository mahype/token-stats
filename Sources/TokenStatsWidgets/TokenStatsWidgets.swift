import SwiftUI
import TokenStatsCore
import WidgetKit

/// Widget-Erweiterung (Issue #10): „Verbrauch“ und „Limits“ für Mitteilungszentrale und
/// Schreibtisch. Liest nur `widgets.json` aus der App Group; alles Rechnen bleibt in der App.
@main
struct TokenStatsWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageWidget()
        LimitsWidget()
    }
}

extension WidgetFamily {
    var size: WidgetSize {
        switch self {
        case .systemLarge, .systemExtraLarge: .large
        case .systemMedium: .medium
        default: .small
        }
    }
}
