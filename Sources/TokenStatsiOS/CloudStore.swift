import Foundation
import Observation
import TokenStatsCore
import WidgetKit

/// Hält den Stand aller Macs: aus iCloud geholt, in der App Group für die Widgets abgelegt.
/// `TOKENSTATS_DEMO=1` (Simulator, Screenshots) zeigt Demo-Werte statt iCloud.
@MainActor @Observable
final class CloudStore {
    static let shared = CloudStore()

    private(set) var machines: [WidgetSnapshot] = []
    /// Hinweis statt Daten: nicht angemeldet, noch kein Mac, Fehler.
    private(set) var status: String?
    private(set) var isLoading = false
    private(set) var lastRefresh: Date?

    let isDemo = ProcessInfo.processInfo.environment["TOKENSTATS_DEMO"] != nil

    func start() async {
        if isDemo {
            machines = DemoData.machines(now: .now)
            return
        }
        machines = SnapshotCache.load()
        await refresh()
        try? await SnapshotCloud.subscribe()
    }

    func refresh() async {
        guard !isDemo, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            guard try await SnapshotCloud.accountStatus() == .available else {
                status = "Nicht bei iCloud angemeldet. Die App zeigt den Stand, den dein Mac in deine private iCloud-Datenbank schreibt."
                return
            }
            let fetched = try await SnapshotCloud.fetchAll()
            machines = fetched
            lastRefresh = .now
            status = fetched.isEmpty
                ? "Noch kein Stand. Auf dem Mac in Token Stats → Einstellungen → iPhone „Stand nach iCloud übertragen“ einschalten."
                : nil
            try? SnapshotCache.write(fetched)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            status = "iCloud: \(error.localizedDescription)"
        }
    }

    /// Alle Macs zusammengerechnet, für die Verbrauchsseite.
    func mergedSummary(provider: String?, period: UsagePeriod) -> UsageSummary? {
        let summaries = machines.compactMap { $0.summary(provider: provider, period: period) }
        return summaries.isEmpty ? nil : UsageSummary.merged(summaries)
    }
}
