import Foundation
import Observation

enum UsagePeriod: String, CaseIterable, Identifiable, Sendable {
    case today, week, month, billing
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Heute"
        case .week: "7 Tage"
        case .month: "30 Tage"
        case .billing: "Abrechnungsmonat"
        }
    }

    /// Erster und letzter Tag (einschließlich), lokale Zeit.
    func range(now: Date = .now, billingDay: Int, calendar: Calendar = .current) -> (from: Date, through: Date) {
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

/// Zusammenfassung für die Seite „Verbrauch“.
struct UsageSummary: Equatable, Sendable {
    struct ModelLine: Equatable, Sendable, Identifiable {
        var model: String
        var counts: TokenCounts
        var value: Double?          // nil = kein Preis bekannt
        var id: String { model }
    }

    struct DayTotal: Equatable, Sendable, Identifiable {
        var day: Date
        var tokens: Int
        var id: Date { day }
    }

    var total = TokenCounts()
    var value: Double = 0
    var hasUnpriced = false
    var models: [ModelLine] = []
    var days: [DayTotal] = []

    static func build(rows: [UsageLedger.Row], from: Date, through: Date, prices: PriceTable,
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
        }.sorted { ($0.value ?? -1, $0.counts.total) > ($1.value ?? -1, $1.counts.total) }
        summary.value = summary.models.compactMap(\.value).reduce(0, +)
        summary.hasUnpriced = summary.models.contains { $0.value == nil }

        var day = from
        while day <= through {
            summary.days.append(DayTotal(day: day, tokens: perDay[UsageSummary.key(day, calendar)] ?? 0))
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return summary
    }

    static func key(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Hält den Ledger aktuell und stellt Zusammenfassungen für die UI bereit.
@MainActor @Observable
final class ConsumptionStore {
    private(set) var summaries: [String: [UsagePeriod: UsageSummary]] = [:]
    private(set) var isScanning = false
    private(set) var hasScannedOnce = false
    private(set) var failure: String?

    let prices = PriceTable.bundled
    private let ledger: UsageLedger?
    private let settings: AppSettings
    private var timer: Timer?

    /// Lokale Dateien, kein Netz – ein kurzer Takt ist unkritisch.
    static let scanInterval: TimeInterval = 60

    init(settings: AppSettings) {
        self.settings = settings
        do {
            ledger = try UsageLedger()
        } catch {
            ledger = nil
            failure = "Verbrauchsdatenbank nicht verfügbar: \(error)"
        }
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.scanInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func summary(_ provider: String, _ period: UsagePeriod) -> UsageSummary? {
        summaries[provider]?[period]
    }

    func refresh() {
        guard let ledger, !isScanning else { return }
        isScanning = true
        let billingDay = settings.billingDay
        let prices = prices
        Task {
            await ledger.scan()
            var result: [String: [UsagePeriod: UsageSummary]] = [:]
            for provider in ["claude", "codex"] {
                for period in UsagePeriod.allCases {
                    let range = period.range(billingDay: billingDay)
                    let rows = await ledger.rows(
                        provider: provider,
                        from: UsageSummary.key(range.from, .current),
                        through: UsageSummary.key(range.through, .current)
                    )
                    result[provider, default: [:]][period] = UsageSummary.build(
                        rows: rows, from: range.from, through: range.through, prices: prices
                    )
                }
            }
            summaries = result
            isScanning = false
            hasScannedOnce = true
        }
    }
}

/// Monatspreis des Abos für den Vergleich, soweit bekannt.
enum SubscriptionPrice {
    static func dollars(provider: String, plan: String?) -> Int? {
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
