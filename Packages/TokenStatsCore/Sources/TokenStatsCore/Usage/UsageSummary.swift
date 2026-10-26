import Foundation

public enum UsagePeriod: String, CaseIterable, Identifiable, Codable, Sendable {
    case today, week, month, billing
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .today: "Heute"
        case .week: "7 Tage"
        case .month: "30 Tage"
        case .billing: "Abrechnungsmonat"
        }
    }

    /// Für schmale Umschalter (iPhone).
    public var shortLabel: String {
        self == .billing ? "Abo-Monat" : label
    }

    /// Erster und letzter Tag (einschließlich), lokale Zeit.
    public func range(now: Date = .now, billingDay: Int, calendar: Calendar = .current) -> (from: Date, through: Date) {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .today: return (today, today)
        case .week: return (calendar.date(byAdding: .day, value: -6, to: today)!, today)
        case .month: return (calendar.date(byAdding: .day, value: -29, to: today)!, today)
        case .billing:
            // Letzter Stichtag ≤ heute; in kurzen Monaten der Monatsletzte.
            func stichtag(monthsBack: Int) -> Date {
                let month = calendar.date(byAdding: .month, value: -monthsBack, to: today)!
                let days = calendar.range(of: .day, in: .month, for: month)!.count
                var parts = calendar.dateComponents([.year, .month], from: month)
                parts.day = min(billingDay, days)
                return calendar.date(from: parts)!
            }
            let start = stichtag(monthsBack: 0) <= today ? stichtag(monthsBack: 0) : stichtag(monthsBack: 1)
            return (start, today)
        }
    }
}

/// Eine Zeile des Tagesaggregats: Tokens eines Modells an einem Tag.
public struct UsageRow: Equatable, Sendable {
    public var day: String         // "2026-09-28", lokale Zeit
    public var model: String
    public var counts: TokenCounts

    public init(day: String, model: String, counts: TokenCounts) {
        self.day = day
        self.model = model
        self.counts = counts
    }
}

/// Zusammenfassung für die Seite „Verbrauch“ – und, fertig gerechnet, für die Widgets.
public struct UsageSummary: Codable, Equatable, Sendable {
    public struct ModelLine: Codable, Equatable, Sendable, Identifiable {
        public var model: String
        public var counts: TokenCounts
        public var value: Double?          // nil = kein Preis bekannt
        public var id: String { model }

        public init(model: String, counts: TokenCounts, value: Double?) {
            self.model = model
            self.counts = counts
            self.value = value
        }
    }

    public struct DayTotal: Codable, Equatable, Sendable, Identifiable {
        public var day: Date
        public var tokens: Int
        public var id: Date { day }

        public init(day: Date, tokens: Int) {
            self.day = day
            self.tokens = tokens
        }
    }

    public var total = TokenCounts()
    public var value: Double = 0
    public var hasUnpriced = false
    public var models: [ModelLine] = []
    public var days: [DayTotal] = []

    public init() {}

    public static func build(rows: [UsageRow], from: Date, through: Date, prices: PriceTable,
                             calendar: Calendar = .current) -> UsageSummary {
        var summary = UsageSummary()
        var perModel: [String: TokenCounts] = [:]
        var perDay: [String: Int] = [:]
        for row in rows {
            perModel[row.model, default: TokenCounts()] = perModel[row.model, default: TokenCounts()] + row.counts
            perDay[row.day, default: 0] += row.counts.total
            summary.total = summary.total + row.counts
        }
        summary.models = perModel.map { model, counts in
            ModelLine(model: model, counts: counts, value: prices.value(of: counts, model: model))
        }
        summary.sortModels()
        summary.value = summary.models.compactMap(\.value).reduce(0, +)
        summary.hasUnpriced = summary.models.contains { $0.value == nil }

        var day = from
        while day <= through {
            summary.days.append(DayTotal(day: day, tokens: perDay[UsageSummary.key(day, calendar)] ?? 0))
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return summary
    }

    /// Mehrere Anbieter oder Macs zusammengerechnet (Widget „Alle Anbieter“, iPhone „Alle Macs“).
    /// Gleiche Modelle werden addiert; die Tagesreihen decken denselben Zeitraum ab, darum
    /// lassen sie sich Tag für Tag addieren.
    public static func merged(_ summaries: [UsageSummary]) -> UsageSummary {
        guard summaries.count > 1 else { return summaries.first ?? UsageSummary() }
        var result = UsageSummary()
        var perModel: [String: ModelLine] = [:]
        var perDay: [Date: Int] = [:]
        for summary in summaries {
            result.total = result.total + summary.total
            result.value += summary.value
            result.hasUnpriced = result.hasUnpriced || summary.hasUnpriced
            for line in summary.models {
                if let known = perModel[line.model] {
                    perModel[line.model] = ModelLine(
                        model: line.model, counts: known.counts + line.counts,
                        value: known.value.flatMap { k in line.value.map { k + $0 } }
                    )
                } else {
                    perModel[line.model] = line
                }
            }
            for day in summary.days {
                perDay[day.day, default: 0] += day.tokens
            }
        }
        result.models = Array(perModel.values)
        result.sortModels()
        result.days = perDay.keys.sorted().map { DayTotal(day: $0, tokens: perDay[$0] ?? 0) }
        return result
    }

    private mutating func sortModels() {
        models.sort { ($0.value ?? -1, $0.counts.total) > ($1.value ?? -1, $1.counts.total) }
    }

    public static func key(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Monatspreis des Abos für den Vergleich, soweit bekannt.
public enum SubscriptionPrice {
    public static func dollars(provider: String, plan: String?) -> Int? {
        guard let plan = plan?.lowercased() else { return nil }
        switch (provider, plan) {
        case ("claude", "max 20×"): return 200
        case ("claude", "max 5×"): return 100
        case ("claude", "pro"): return 20
        case ("codex", "pro"): return 200
        case ("codex", "plus"): return 20
        default: return nil
        }
    }
}
