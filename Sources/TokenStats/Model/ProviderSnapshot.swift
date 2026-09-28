import Foundation

/// Stand eines Anbieters zu einem Abrufzeitpunkt (SPEC §7).
struct ProviderSnapshot: Codable, Equatable, Sendable {
    var account: AccountInfo?
    var windows: [LimitWindow]
    var extras: [ExtraValue]
    var fetchedAt: Date

    /// Das knappste Limit dieses Anbieters.
    var tightestWindow: LimitWindow? {
        windows.max { $0.percent < $1.percent }
    }
}

struct AccountInfo: Codable, Equatable, Sendable {
    var name: String?
    var plan: String?
}

struct LimitWindow: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String            // "Session", "Woche", "Opus"
    var scopeNote: String?      // "5 h", "7 d, alle Modelle"
    var percent: Double         // 0…1, kann über 1 liegen
    var resetsAt: Date?
    var windowLength: TimeInterval?

    var severity: Severity { Severity(percent: percent) }

    /// Anteil der verstrichenen Fensterzeit, für die Pace-Marke.
    func elapsedFraction(now: Date = .now) -> Double? {
        guard let resetsAt, let windowLength, windowLength > 0 else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        return min(max((windowLength - remaining) / windowLength, 0), 1)
    }
}

/// Beträge, Guthaben und Kleinwerte unter den Meter-Zeilen.
struct ExtraValue: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var text: String
}

enum Severity: Int, Comparable, Sendable {
    case ok, warn, crit

    /// Omarchy-Konvention: gelb ab 80 %, rot ab 100 %.
    init(percent: Double) {
        switch percent {
        case 1...: self = .crit
        case 0.8...: self = .warn
        default: self = .ok
        }
    }

    static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
}
