import Foundation
import Observation

/// Hält den letzten Stand je Anbieter, fragt im Takt ab und respektiert Rate-Limits.
@MainActor @Observable
final class UsageStore {
    struct ProviderState: Codable, Equatable {
        var snapshot: ProviderSnapshot?
        var error: String?
        var lastAttempt: Date?
        /// Bis hierhin keine Abfrage – aus Retry-After nach HTTP 429.
        var retryAt: Date?

        var isRateLimited: Bool { retryAt.map { $0 > .now } ?? false }
    }

    struct Pick: Equatable {
        var providerID: String
        var providerName: String
        var window: LimitWindow
    }

    let providers: [any UsageProvider]
    private(set) var states: [String: ProviderState] = [:]
    private(set) var loading: Set<String> = []

    private let settings: AppSettings
    private var timer: Timer?

    /// Abstand zwischen zwei manuellen Aktualisierungen.
    static let manualFloor: TimeInterval = 60

    init(providers: [any UsageProvider], settings: AppSettings) {
        self.providers = providers
        self.settings = settings
        states = Self.loadCache()
    }

    var installedProviders: [any UsageProvider] {
        providers.filter { $0.isInstalled() }
    }

    /// Nach Dringlichkeit sortiert: knappster Anbieter zuerst (SPEC §3.2).
    var sortedProviders: [any UsageProvider] {
        installedProviders.enumerated().sorted { lhs, rhs in
            let l = states[lhs.element.id]?.snapshot?.tightestWindow?.percent ?? -1
            let r = states[rhs.element.id]?.snapshot?.tightestWindow?.percent ?? -1
            return l == r ? lhs.offset < rhs.offset : l > r
        }.map(\.element)
    }

    /// Wert für Menüleiste und Popover-Kopf – beide zeigen immer denselben.
    var displayed: Pick? {
        if let fixed = settings.fixedWindow, let pick = pick(for: fixed) { return pick }
        return tightest
    }

    var tightest: Pick? {
        installedProviders.compactMap { provider -> Pick? in
            guard let window = states[provider.id]?.snapshot?.tightestWindow else { return nil }
            return Pick(providerID: provider.id, providerName: provider.displayName, window: window)
        }.max { $0.window.percent < $1.window.percent }
    }

    func pick(for key: String) -> Pick? {
        let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let provider = providers.first(where: { $0.id == parts[0] }),
              let window = states[provider.id]?.snapshot?.windows.first(where: { $0.id == parts[1] })
        else { return nil }
        return Pick(providerID: provider.id, providerName: provider.displayName, window: window)
    }

    var lastUpdate: Date? {
        states.values.compactMap(\.snapshot?.fetchedAt).max()
    }

    // MARK: Abruf

    func start() {
        refresh(manual: false)
        // Der Timer prüft nur, ob etwas fällig ist; der eigentliche Takt ist refreshInterval.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(manual: false) }
        }
    }

    func refresh(manual: Bool) {
        let now = Date.now
        for provider in installedProviders where !loading.contains(provider.id) {
            let state = states[provider.id] ?? ProviderState()
            if state.isRateLimited { continue }
            let spacing = manual ? Self.manualFloor : settings.refreshInterval
            if let last = state.lastAttempt, now.timeIntervalSince(last) < spacing { continue }
            fetch(provider)
        }
    }

    private func fetch(_ provider: any UsageProvider) {
        loading.insert(provider.id)
        states[provider.id, default: ProviderState()].lastAttempt = .now
        Task {
            var state = states[provider.id] ?? ProviderState()
            do {
                state.snapshot = try await provider.fetch()
                state.error = nil
                state.retryAt = nil
            } catch let error as ProviderError {
                // Letzte Werte bleiben stehen, nie eine leere Anzeige.
                state.error = error.message
                if case .rateLimited(let retryAfter) = error {
                    state.retryAt = .now.addingTimeInterval(retryAfter ?? settings.refreshInterval)
                }
            } catch {
                state.error = error.localizedDescription
            }
            states[provider.id] = state
            loading.remove(provider.id)
            saveCache()
        }
    }

    // MARK: Cache
    // Nur Prozentwerte und Reset-Zeiten – keine Zugangsdaten. Überlebt Neustarts,
    // damit ein Neustart der App keine zusätzliche Abfrage auslöst.

    private static var cacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "TokenStats/state.json")
    }

    private static func loadCache() -> [String: ProviderState] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [:] }
        return (try? JSONDecoder().decode([String: ProviderState].self, from: data)) ?? [:]
    }

    private func saveCache() {
        let url = Self.cacheURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(states) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
