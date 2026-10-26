import SwiftUI
import TokenStatsCore
import WidgetKit

/// Widget-Erweiterung (Issue #10): „Verbrauch“ und „Limits“ für Mitteilungszentrale und
/// Schreibtisch. Liest nur `widgets.json` aus der App Group; alles Rechnen bleibt in der App.
/// Auf iOS (Issue #11) dieselben Quellen: Homescreen-Widgets aus dem iCloud-Cache der App,
/// dazu die Sperrbildschirm-Familien in LockScreenWidgets.swift.
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

    /// Sperrbildschirm und StandBy (nur iOS).
    var isAccessory: Bool {
        #if os(iOS)
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: true
        default: false
        }
        #else
        false
        #endif
    }

    static let systemFamilies: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]

    static var limitsFamilies: [WidgetFamily] {
        #if os(iOS)
        systemFamilies + [.accessoryCircular, .accessoryRectangular, .accessoryInline]
        #else
        systemFamilies
        #endif
    }
}
