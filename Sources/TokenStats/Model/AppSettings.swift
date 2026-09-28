import Foundation
import Observation
import ServiceManagement

enum MenuBarMode: String, CaseIterable, Identifiable {
    case icon, iconPercent = "icon+pct", iconBars = "icon+bars"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .icon: "Nur Icon"
        case .iconPercent: "Icon + %"
        case .iconBars: "Icon + Balken"
        }
    }
}

/// Einstellungen, in UserDefaults gespeichert.
@MainActor @Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    var menuBarMode: MenuBarMode {
        didSet { defaults.set(menuBarMode.rawValue, forKey: "menuBarMode") }
    }
    /// `nil` = knappstes Limit, sonst "providerID/windowID".
    var fixedWindow: String? {
        didSet { defaults.set(fixedWindow, forKey: "fixedWindow") }
    }
    var useStateColor: Bool {
        didSet { defaults.set(useStateColor, forKey: "useStateColor") }
    }
    /// Abfrageintervall in Sekunden, nie unter 300 (Endpunkte sind hart rate-limitiert).
    var refreshInterval: TimeInterval {
        didSet {
            if refreshInterval < Self.minimumInterval { refreshInterval = Self.minimumInterval }
            defaults.set(refreshInterval, forKey: "refreshInterval")
        }
    }

    static let minimumInterval: TimeInterval = 300

    init() {
        menuBarMode = MenuBarMode(rawValue: defaults.string(forKey: "menuBarMode") ?? "") ?? .icon
        fixedWindow = defaults.string(forKey: "fixedWindow")
        useStateColor = defaults.object(forKey: "useStateColor") as? Bool ?? true
        refreshInterval = max(defaults.double(forKey: "refreshInterval"), Self.minimumInterval)
    }

    // Bei Anmeldung starten – Zustand liegt bei SMAppService, nicht in UserDefaults.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Token Stats: Autostart nicht änderbar: \(error.localizedDescription)")
            }
        }
    }
}
