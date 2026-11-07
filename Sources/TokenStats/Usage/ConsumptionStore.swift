import Foundation
import Observation
import TokenStatsCore

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

    /// Anbieter, deren Logs ausgewertet werden.
    static let providers = ["claude", "codex"]

    func summary(_ provider: String, _ period: UsagePeriod) -> UsageSummary? {
        summaries[provider]?[period]
    }

    #if DEBUG
    /// Nur für Screenshots: feste Zusammenfassungen, ohne die Logs zu lesen.
    func showDemo(_ demo: [String: [UsagePeriod: UsageSummary]]) {
        timer?.invalidate()
        summaries = demo
        hasScannedOnce = true
    }
    #endif

    func refresh() {
        guard let ledger, !isScanning else { return }
        isScanning = true
        let billingDay = settings.billingDay
        let prices = prices
        Task {
            await ledger.scan()
            var result: [String: [UsagePeriod: UsageSummary]] = [:]
            for provider in Self.providers {
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
