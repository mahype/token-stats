import Foundation

/// Ein Tag aus `rtk gain --format json --daily`: was rtk an Befehlsausgaben gefiltert hat.
public struct RtkDay: Equatable, Sendable {
    public var day: String          // "2026-11-20", Tagesgrenze von rtk
    public var commands: Int
    public var inputTokens: Int
    public var savedTokens: Int

    public init(day: String, commands: Int, inputTokens: Int, savedTokens: Int) {
        self.day = day
        self.commands = commands
        self.inputTokens = inputTokens
        self.savedTokens = savedTokens
    }
}

/// Ersparnis durch rtk in einem Zeitraum – über alle Clients, rtk kennt den auslösenden Agent nicht.
public struct RtkSummary: Equatable, Sendable {
    public var commands: Int
    public var inputTokens: Int
    public var savedTokens: Int

    public init(commands: Int = 0, inputTokens: Int = 0, savedTokens: Int = 0) {
        self.commands = commands
        self.inputTokens = inputTokens
        self.savedTokens = savedTokens
    }

    /// Anteil der gesparten an den ungefilterten Tokens; `nil`, wenn nichts gefiltert wurde.
    public var savedFraction: Double? {
        inputTokens > 0 ? Double(savedTokens) / Double(inputTokens) : nil
    }
}

/// Liest die Tageswerte, die `rtk gain` selbst ausgibt. Bewusst nicht rtks `history.db`:
/// Das Schema ist undokumentiert, und die Rohsummen dort enthalten Einträge, die `rtk gain`
/// nicht mitzählt – der Block soll mit `rtk gain` übereinstimmen.
public enum RtkSavings {
    public static let arguments = ["gain", "--format", "json", "--daily"]

    /// `nil` bei kaputter JSON oder fehlendem `daily`; Tage ohne vollständige Zahlen fallen weg.
    public static func parse(_ data: Data) -> [RtkDay]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let daily = object["daily"] as? [[String: Any]]
        else { return nil }
        return daily.compactMap { entry in
            guard let day = entry["date"] as? String,
                  let commands = (entry["commands"] as? NSNumber)?.intValue,
                  let input = (entry["input_tokens"] as? NSNumber)?.intValue,
                  let saved = (entry["saved_tokens"] as? NSNumber)?.intValue
            else { return nil }
            return RtkDay(day: day, commands: commands, inputTokens: input, savedTokens: saved)
        }
    }

    /// Summe der Tage `from…through` (einschließlich), Schlüssel wie `UsageSummary.key`.
    public static func summary(_ days: [RtkDay], from: String, through: String) -> RtkSummary {
        days.filter { $0.day >= from && $0.day <= through }.reduce(into: RtkSummary()) { sum, day in
            sum.commands += day.commands
            sum.inputTokens += day.inputTokens
            sum.savedTokens += day.savedTokens
        }
    }

    /// Je Zeitraum die Summe, mit denselben Grenzen wie die Seite „Verbrauch“.
    public static func summaries(_ days: [RtkDay], now: Date = .now, billingDay: Int,
                                 calendar: Calendar = .current) -> [UsagePeriod: RtkSummary] {
        Dictionary(uniqueKeysWithValues: UsagePeriod.allCases.map { period in
            let range = period.range(now: now, billingDay: billingDay, calendar: calendar)
            return (period, summary(days, from: UsageSummary.key(range.from, calendar),
                                    through: UsageSummary.key(range.through, calendar)))
        })
    }
}
