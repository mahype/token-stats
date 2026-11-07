import Foundation
import Observation
import TokenStatsCore
import WidgetKit

/// Gibt den Widgets den Stand (Issue #10): schreibt `widgets.json` in die App Group, sobald
/// sich Limits, Verbrauch oder die Geld-Einstellung ändern, und lädt dann die Timelines neu.
///
/// Die Erweiterung liest nur diese Datei – keine Zugangsdaten, kein `usage.sqlite`, keine
/// Endpunkte. Ein neuer Limit-Stand lädt sofort neu; Verbrauchsänderungen allein höchstens
/// alle fünf Minuten, wie der Abfragetakt, damit das Neuladen nicht im Minutentakt läuft.
@MainActor
final class WidgetBridge {
    private let store: UsageStore
    private let consumption: ConsumptionStore
    private let settings: AppSettings

    private var lastWritten: WidgetSnapshot?
    private var lastReload: Date = .distantPast
    private var pendingWrite: Task<Void, Never>?
    private var pendingReload: Task<Void, Never>?

    static let usageReloadInterval: TimeInterval = 300

    init(store: UsageStore, consumption: ConsumptionStore, settings: AppSettings) {
        self.store = store
        self.consumption = consumption
        self.settings = settings
    }

    func start() {
        observe()
    }

    /// Baut den Stand neu, sobald sich eine der beobachteten Quellen ändert.
    private func observe() {
        let snapshot = withObservationTracking {
            build()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        schedule(snapshot)
    }

    private func build() -> WidgetSnapshot {
        let providers = store.sortedProviders.map { provider -> WidgetSnapshot.Provider in
            let state = store.states[provider.id]
            return WidgetSnapshot.Provider(
                id: provider.id,
                name: provider.displayName,
                snapshot: state?.snapshot,
                isRateLimited: state?.isRateLimited ?? false,
                message: state?.error ?? state?.note
            )
        }
        let usage = ConsumptionStore.providers.flatMap { provider in
            UsagePeriod.allCases.compactMap { period in
                consumption.summary(provider, period).map { WidgetSnapshot.Usage(provider: provider, period: period, summary: $0) }
            }
        }
        return WidgetSnapshot(showMoney: settings.showMoney, providers: providers, usage: usage)
    }

    /// Kurz sammeln: Mehrere Anbieter antworten oft innerhalb weniger Sekunden.
    private func schedule(_ snapshot: WidgetSnapshot) {
        pendingWrite?.cancel()
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.write(snapshot)
        }
    }

    private func write(_ snapshot: WidgetSnapshot) {
        if let last = lastWritten, last.providers == snapshot.providers, last.usage == snapshot.usage,
           last.showMoney == snapshot.showMoney {
            return
        }
        do {
            try snapshot.write()
            #if DEBUG
            NSLog("Token Stats: Widget-Stand geschrieben (%d Anbieter, %d Verbrauchszeilen)", snapshot.providers.count, snapshot.usage.count)
            #endif
        } catch {
            NSLog("Token Stats: Widget-Stand nicht schreibbar: \(error.localizedDescription)")
            return
        }
        let limitsChanged = lastWritten.map { $0.providers != snapshot.providers || $0.showMoney != snapshot.showMoney } ?? true
        lastWritten = snapshot
        let due = lastReload.addingTimeInterval(Self.usageReloadInterval)
        if limitsChanged || due <= .now {
            reload()
        } else if pendingReload == nil {
            pendingReload = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(due.timeIntervalSinceNow, 1)))
                guard !Task.isCancelled else { return }
                self?.pendingReload = nil
                self?.reload()
            }
        }
    }

    private func reload() {
        pendingReload?.cancel()
        pendingReload = nil
        lastReload = .now
        WidgetCenter.shared.reloadAllTimelines()
    }
}
