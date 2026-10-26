import Foundation

/// Demo-Werte für README-Bilder und die Widget-Vorschau in der Galerie. Nichts davon wird
/// abgefragt oder aus Logs gelesen; keine echten Limits, Logs oder Kontonamen.
public enum DemoData {
    /// Ein Stand, der alle Zustände zeigt: grün, gelb, Pace vorgegriffen, ungenutzt und im Takt.
    public static func snapshots(now: Date) -> [String: ProviderSnapshot] {
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
            "antigravity": ProviderSnapshot(
                account: AccountInfo(name: "Demo", plan: "Google AI Plus"),
                windows: [
                    LimitWindow(id: "gemini-weekly", name: "Gemini", scopeNote: "Wochenlimit", percent: 0.35,
                                resetsAt: now.addingTimeInterval(5.3 * 24 * hour), windowLength: week),
                    LimitWindow(id: "3p-weekly", name: "Claude & GPT", scopeNote: "Wochenlimit", percent: 0.12,
                                resetsAt: now.addingTimeInterval(5.3 * 24 * hour), windowLength: week),
                ],
                extras: [],
                fetchedAt: now.addingTimeInterval(-60)
            ),
            "ollama": ProviderSnapshot(
                account: AccountInfo(name: "Demo", plan: "Pro"),
                windows: [
                    LimitWindow(id: "session", name: "Session", scopeNote: "5 h", percent: 0.18,
                                resetsAt: nil, windowLength: nil),
                    LimitWindow(id: "weekly", name: "Woche", scopeNote: "7 d", percent: 0.41,
                                resetsAt: nil, windowLength: nil),
                ],
                extras: [
                    ExtraValue(id: "requests-glm-5.3", text: "glm-5.3 · 312 Anfragen"),
                    ExtraValue(id: "requests-kimi-k2.6", text: "kimi-k2.6 · 48 Anfragen"),
                ],
                fetchedAt: now.addingTimeInterval(-60)
            ),
        ]
    }

    /// Anzeigenamen wie in den Providern der App, alphabetisch wie die Tabs.
    public static let providerNames: [(id: String, name: String)] = [
        ("antigravity", "Antigravity"), ("claude", "Claude"), ("codex", "Codex"), ("ollama", "Ollama"),
    ]

    /// Listenpreise der Demo-Modelle, falls keine `pricing.json` im Bundle liegt (Widget-Vorschau).
    public static let prices = PriceTable(asOf: nil, models: [
        "claude-opus-5-5": .init(input: 5e-6, output: 25e-6, cacheRead: 0.5e-6, cacheWrite5m: 6.25e-6, cacheWrite1h: 10e-6),
        "claude-sonnet-5": .init(input: 3e-6, output: 15e-6, cacheRead: 0.1e-6, cacheWrite5m: 3.75e-6, cacheWrite1h: 6e-6),
        "gpt-5.6-sol": .init(input: 1.25e-6, output: 10e-6, cacheRead: 0.125e-6, cacheWrite5m: 1.25e-6, cacheWrite1h: 1.25e-6),
    ])

    /// 30 Tage Verbrauch mit Wochenrhythmus; Cache-Anteil wie bei Claude Code üblich um 80 %.
    public static func usage(now: Date, billingDay: Int, prices: PriceTable,
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
                    UsageRow(day: UsageSummary.key(day, calendar), model: line.model,
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

    /// Der komplette Widget-Stand mit Demo-Werten, für Vorschau und README.
    public static func widgetSnapshot(now: Date, prices: PriceTable = DemoData.prices, showMoney: Bool = true,
                                      machine: String? = nil, age: TimeInterval = 60) -> WidgetSnapshot {
        let snapshots = snapshots(now: now)
        let usage = usage(now: now, billingDay: 1, prices: prices.models.isEmpty ? DemoData.prices : prices)
        return WidgetSnapshot(
            writtenAt: now.addingTimeInterval(-age),
            machine: machine,
            showMoney: showMoney,
            providers: providerNames.map { WidgetSnapshot.Provider(id: $0.id, name: $0.name, snapshot: snapshots[$0.id]) },
            usage: usage.flatMap { provider, periods in
                periods.map { WidgetSnapshot.Usage(provider: provider, period: $0.key, summary: $0.value) }
            }
        )
    }

    /// Zwei Macs, wie sie die iOS-App aus iCloud bekäme (Issue #11).
    public static func machines(now: Date) -> [WidgetSnapshot] {
        [
            widgetSnapshot(now: now, machine: "work", age: 12 * 60),
            widgetSnapshot(now: now, machine: "MacBook Pro", age: 3 * 3600),
        ]
    }
}
