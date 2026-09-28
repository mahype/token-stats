#if DEBUG
import AppKit
import SwiftUI

/// `make screenshots`: rendert Popover und Menüleisten-Symbol als PNG für die README.
///
/// Die App zeichnet ihre eigenen Views, deshalb braucht das keine Freigabe für
/// Bildschirmaufnahme. Limits und Verbrauch sind Demo-Werte: keine Abfrage, kein Cache,
/// keine Logs, keine Kontonamen.
@MainActor
struct Screenshots {
    let store: UsageStore
    let consumption: ConsumptionStore
    let settings: AppSettings

    func run(into directory: URL) {
        Task {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try await capture(into: directory)
                NSApp.terminate(nil)
            } catch {
                FileHandle.standardError.write(Data("Screenshots fehlgeschlagen: \(error)\n".utf8))
                exit(1)
            }
        }
    }

    /// Demo-Werte für Limits und Verbrauch; nichts wird abgefragt oder aus den Logs gelesen.
    func showDemo(now: Date = .now) {
        store.showDemo(Self.demoSnapshots(now: now))
        consumption.showDemo(Self.demoUsage(now: now, billingDay: settings.billingDay, prices: consumption.prices))
    }

    private func capture(into directory: URL) async throws {
        showDemo()

        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            func file(_ name: String) -> URL { directory.appending(path: "\(name)-\(suffix).png") }

            try await render(card(popover(selected: "claude")), appearance, to: file("limits"))
            try await render(card(popover(selected: "codex")), appearance, to: file("limits-codex"))
            try await render(card(popover(selected: "claude", usage: true)), appearance, to: file("usage"))
            try await render(menuBar, appearance, to: file("menubar"))
        }
    }

    // MARK: Inhalte

    private func popover(selected: String, usage: Bool = false) -> some View {
        PopoverView(
            store: store, consumption: consumption, settings: settings,
            selectedID: selected, showUsage: usage
        ) {}
    }

    /// Popover-Rahmen nachgebildet: NSPopover selbst lässt sich nicht offscreen zeichnen.
    private func card(_ content: some View) -> some View {
        content
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
            .padding(1)
    }

    /// Die drei Anzeige-Modi nebeneinander, in einem Stück Menüleiste.
    private var menuBar: some View {
        let claude = Self.demoSnapshots(now: .now)["claude"]!.windows
        return HStack(spacing: 22) {
            ForEach(MenuBarMode.allCases) { mode in
                VStack(spacing: 8) {
                    Image(nsImage: StatusIcon.image(.init(
                        mode: mode, severity: .warn, percent: claude[1].percent,
                        bars: claude.prefix(2).map(\.percent), colored: true, paused: false
                    )))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
                    Text(mode.label).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .padding(1)
    }

    // MARK: Zeichnen

    /// Zeichnet in 3× als Vektor, unabhängig vom Bildschirm – scharf auch in der halb breiten
    /// README-Tabelle. Über ein Offscreen-Fenster käme auf einem Nicht-Retina-Bildschirm nur
    /// ein hochskaliertes 1×-Bild heraus.
    private func render(_ view: some View, _ appearance: NSAppearance.Name, to url: URL) async throws {
        let scheme: ColorScheme = appearance == .darkAqua ? .dark : .light
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
        renderer.scale = 3
        renderer.isOpaque = false
        var image: CGImage?
        // Dynamische NSColors (Zustandsfarben, Fensterhintergrund) lösen über die aktuelle Appearance auf.
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            image = renderer.cgImage
        }
        guard let image,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
        print(url.lastPathComponent)
    }

    // MARK: Demo-Werte

    /// Ein Stand, der alle Zustände zeigt: grün, gelb, Pace-Marke über Plan.
    static func demoSnapshots(now: Date) -> [String: ProviderSnapshot] {
        let hour: TimeInterval = 3600
        let week = 7 * 24 * hour
        let weekReset = now.addingTimeInterval(2.6 * 24 * hour)
        return [
            "claude": ProviderSnapshot(
                account: AccountInfo(name: "Demo", plan: "Max 20×"),
                windows: [
                    LimitWindow(id: "session", name: "Session", scopeNote: "5 h", percent: 0.42,
                                resetsAt: now.addingTimeInterval(2.2 * hour), windowLength: 5 * hour),
                    LimitWindow(id: "week", name: "Woche", scopeNote: "7 d, alle Modelle", percent: 0.82,
                                resetsAt: weekReset, windowLength: week),
                    LimitWindow(id: "model-opus", name: "Opus", scopeNote: "Wochenlimit", percent: 0.64,
                                resetsAt: weekReset, windowLength: week),
                ],
                extras: [ExtraValue(id: "extra", text: "Extra 12,40 $ / 50,00 $")],
                fetchedAt: now.addingTimeInterval(-60)
            ),
            "codex": ProviderSnapshot(
                account: AccountInfo(name: "Demo", plan: "Pro"),
                windows: [
                    LimitWindow(id: "primary", name: "Woche", scopeNote: "7 d", percent: 0.37,
                                resetsAt: now.addingTimeInterval(4.1 * 24 * hour), windowLength: week),
                    LimitWindow(id: "review", name: "Code-Review", scopeNote: "7 d", percent: 0.08,
                                resetsAt: now.addingTimeInterval(4.1 * 24 * hour), windowLength: week),
                ],
                extras: [ExtraValue(id: "credits", text: "Credits unbegrenzt")],
                fetchedAt: now.addingTimeInterval(-60)
            ),
        ]
    }

    /// 30 Tage Verbrauch mit Wochenrhythmus; Cache-Anteil wie bei Claude Code üblich um 80 %.
    static func demoUsage(now: Date, billingDay: Int, prices: PriceTable,
                          calendar: Calendar = .current) -> [String: [UsagePeriod: UsageSummary]] {
        // Tagesfaktoren, heute zuletzt; die Nullen sind freie Tage.
        let pattern: [Double] = [0.9, 1.2, 0.7, 1.4, 0.3, 0, 0.5, 1.1, 1.3, 0.8, 1.6, 0.9, 0.2, 0,
                                 1.0, 0.6, 1.5, 1.2, 0.7, 0.4, 0.1, 1.3, 0.9, 1.1, 1.8, 1.0, 0, 0.6, 1.4, 0.8]
        let models: [String: [(model: String, share: Double, perDay: TokenCounts)]] = [
            "claude": [
                ("claude-opus-5-5", 0.7, TokenCounts(input: 9_000, output: 310_000, cacheWrite5m: 1_900_000,
                                                     cacheWrite1h: 600_000, cacheRead: 38_000_000)),
                ("claude-sonnet-5", 0.3, TokenCounts(input: 14_000, output: 240_000, cacheWrite5m: 1_400_000,
                                                     cacheWrite1h: 0, cacheRead: 21_000_000)),
            ],
            "codex": [
                ("gpt-5.6-sol", 1, TokenCounts(input: 1_100_000, output: 180_000, cacheRead: 9_500_000)),
            ],
        ]
        let today = calendar.startOfDay(for: now)
        func scaled(_ counts: TokenCounts, _ factor: Double) -> TokenCounts {
            func s(_ value: Int) -> Int { Int(Double(value) * factor) }
            return TokenCounts(input: s(counts.input), output: s(counts.output), cacheWrite5m: s(counts.cacheWrite5m),
                               cacheWrite1h: s(counts.cacheWrite1h), cacheRead: s(counts.cacheRead))
        }

        return models.mapValues { lines in
            let rows = pattern.enumerated().flatMap { index, factor in
                let day = calendar.date(byAdding: .day, value: index - (pattern.count - 1), to: today)!
                return lines.map { line in
                    UsageLedger.Row(day: UsageSummary.key(day, calendar), model: line.model,
                                    counts: scaled(line.perDay, factor * line.share * 2))
                }
            }
            return Dictionary(uniqueKeysWithValues: UsagePeriod.allCases.map { period in
                let range = period.range(now: now, billingDay: billingDay, calendar: calendar)
                let from = UsageSummary.key(range.from, calendar), through = UsageSummary.key(range.through, calendar)
                let inRange = rows.filter { $0.day >= from && $0.day <= through }
                return (period, UsageSummary.build(rows: inRange, from: range.from, through: range.through,
                                                   prices: prices, calendar: calendar))
            })
        }
    }
}
#endif
