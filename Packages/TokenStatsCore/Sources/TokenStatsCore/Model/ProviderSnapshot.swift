import Foundation

/// Stand eines Anbieters zu einem Abrufzeitpunkt (SPEC §7).
public struct ProviderSnapshot: Codable, Equatable, Sendable {
    public var account: AccountInfo?
    public var windows: [LimitWindow]
    public var extras: [ExtraValue]
    public var fetchedAt: Date

    public init(account: AccountInfo? = nil, windows: [LimitWindow], extras: [ExtraValue] = [], fetchedAt: Date) {
        self.account = account
        self.windows = windows
        self.extras = extras
        self.fetchedAt = fetchedAt
    }

    /// Das knappste Limit dieses Anbieters.
    public var tightestWindow: LimitWindow? {
        windows.max { $0.percent < $1.percent }
    }
}

public struct AccountInfo: Codable, Equatable, Sendable {
    public var name: String?
    public var plan: String?

    public init(name: String? = nil, plan: String? = nil) {
        self.name = name
        self.plan = plan
    }
}

public struct LimitWindow: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String            // "Session", "Woche", "Opus"
    public var scopeNote: String?      // "5 h", "7 d, alle Modelle"
    public var percent: Double         // 0…1, kann über 1 liegen
    public var resetsAt: Date?
    public var windowLength: TimeInterval?

    public init(id: String, name: String, scopeNote: String? = nil, percent: Double,
                resetsAt: Date? = nil, windowLength: TimeInterval? = nil) {
        self.id = id
        self.name = name
        self.scopeNote = scopeNote
        self.percent = percent
        self.resetsAt = resetsAt
        self.windowLength = windowLength
    }

    public var severity: Severity { Severity(percent: percent) }

    /// Nach dem Reset: 0 % und – bei bekannter Fensterlänge – der nächste Reset.
    public func rolledOver(now: Date = .now) -> LimitWindow {
        guard let resetsAt, resetsAt <= now else { return self }
        var window = self
        window.percent = 0
        if let windowLength, windowLength > 0 {
            let periods = (now.timeIntervalSince(resetsAt) / windowLength).rounded(.down) + 1
            window.resetsAt = resetsAt.addingTimeInterval(periods * windowLength)
        } else {
            window.resetsAt = nil
        }
        return window
    }

    /// Anteil der verstrichenen Fensterzeit, für die Pace-Marke.
    public func elapsedFraction(now: Date = .now) -> Double? {
        guard let resetsAt, let windowLength, windowLength > 0 else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        return min(max((windowLength - remaining) / windowLength, 0), 1)
    }
}

/// Beträge, Guthaben und Kleinwerte unter den Meter-Zeilen.
public struct ExtraValue: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

public enum Severity: Int, Comparable, Sendable {
    case ok, warn, crit

    /// Omarchy-Konvention: gelb ab 80 %, rot ab 100 %.
    public init(percent: Double) {
        switch percent {
        case 1...: self = .crit
        case 0.8...: self = .warn
        default: self = .ok
        }
    }

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
}
