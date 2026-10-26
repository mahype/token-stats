import SwiftUI
import TokenStatsCore

/// Zwei Tabs wie die Seiten des Popovers: Limits und Verbrauch, je ein Abschnitt pro Mac.
struct ContentView: View {
    let store: CloudStore
    /// `TOKENSTATS_TAB=usage` startet auf „Verbrauch“ – für Screenshots im Simulator.
    @State private var tab = ProcessInfo.processInfo.environment["TOKENSTATS_TAB"] ?? "limits"

    var body: some View {
        TabView(selection: $tab) {
            LimitsScreen(store: store)
                .tabItem { Label("Limits", systemImage: "gauge.with.dots.needle.33percent") }
                .tag("limits")
            UsageScreen(store: store)
                .tabItem { Label("Verbrauch", systemImage: "chart.bar") }
                .tag("usage")
        }
    }
}

// MARK: - Limits

struct LimitsScreen: View {
    let store: CloudStore

    var body: some View {
        NavigationStack {
            List {
                StatusSection(store: store)
                ForEach(store.machines, id: \.writtenAt) { machine in
                    Section {
                        let providers = machine.providers.filter { $0.snapshot != nil }
                        if providers.isEmpty {
                            Text("Noch kein Limit-Stand auf diesem Mac.").foregroundStyle(.secondary)
                        }
                        ForEach(providers) { provider in
                            ProviderLimits(provider: provider)
                        }
                    } header: {
                        MachineHeader(machine: machine)
                    }
                }
            }
            .navigationTitle("Limits")
            .refreshable { await store.refresh() }
        }
    }
}

/// Kopf und Meter eines Anbieters, wie die Seite „Limits“ im Popover.
private struct ProviderLimits: View {
    let provider: WidgetSnapshot.Provider

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text(provider.name).font(.headline)
                if let plan = provider.snapshot?.account?.plan {
                    Text(plan).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                if let tightest = provider.snapshot?.tightestWindow {
                    Text(Format.percent(tightest.percent))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tightest.severity.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(tightest.severity.color))
                }
            }
            if provider.isRateLimited {
                Label("Abfrage pausiert (Rate-Limit)", systemImage: "pause.circle")
                    .font(.caption).foregroundStyle(Severity.warn.color)
            } else if let message = provider.message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(provider.snapshot?.windows ?? []) { MeterRow(window: $0) }
            if let extras = provider.snapshot?.extras, !extras.isEmpty {
                Text(extras.map(\.text).joined(separator: " · "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Verbrauch

struct UsageScreen: View {
    let store: CloudStore

    @State private var period: UsagePeriod = .week
    @State private var provider: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Zeitraum", selection: $period) {
                        ForEach(UsagePeriod.allCases) { Text($0.shortLabel).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                    Picker("Anbieter", selection: $provider) {
                        Text("Alle Anbieter").tag(String?.none)
                        Text("Claude").tag(Optional("claude"))
                        Text("Codex").tag(Optional("codex"))
                    }
                }
                StatusSection(store: store)
                if store.machines.count > 1, let merged = store.mergedSummary(provider: provider, period: period) {
                    Section("Alle Macs") {
                        UsageSection(summary: merged, showMoney: store.machines.contains { $0.showMoney }, period: period)
                    }
                }
                ForEach(store.machines, id: \.writtenAt) { machine in
                    Section {
                        if let summary = machine.summary(provider: provider, period: period), !summary.total.isZero {
                            UsageSection(summary: summary, showMoney: machine.showMoney, period: period)
                        } else {
                            Text("Keine Einträge in diesem Zeitraum.").foregroundStyle(.secondary)
                        }
                    } header: {
                        MachineHeader(machine: machine)
                    }
                }
                if !store.machines.isEmpty {
                    Section {
                        Text("Tokenzahlen aus den Session-Logs der Macs × Listenpreis, inkl. Cache-Tarife. Keine Abrechnungsdaten – nur, was derselbe Verbrauch über die API gekostet hätte.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Verbrauch")
            .refreshable { await store.refresh() }
        }
    }
}

/// Kennzahlen, Tagesdiagramm und Modelle – wie die Seite „Verbrauch“ im Popover.
private struct UsageSection: View {
    let summary: UsageSummary
    let showMoney: Bool
    let period: UsagePeriod

    var body: some View {
        HStack(spacing: 12) {
            Tile(title: "Tokens", value: Format.tokens(summary.total.total),
                 detail: "\(Format.tokens(summary.total.cacheRead)) davon Cache-Lesen")
            if showMoney {
                Tile(title: "API-Vergleichswert", value: Format.money(summary.value) + (summary.hasUnpriced ? "*" : ""),
                     detail: "berechnet, keine Kosten")
            }
        }
        .listRowSeparator(.hidden)
        if summary.days.count > 1 {
            DayChart(days: summary.days)
                .listRowSeparator(.hidden)
        }
        ForEach(summary.models) { line in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ModelName.display(line.model)).font(.subheadline.weight(.semibold))
                    Text("\(Format.tokens(line.counts.input)) in · \(Format.tokens(line.counts.output)) out · \(Format.tokens(line.counts.cache)) Cache")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if showMoney {
                    Text(line.value.map(Format.money) ?? "ohne Preis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(line.value == nil ? .secondary : .primary)
                }
            }
            .monospacedDigit()
        }
        HStack {
            Text("\(period.label) · \(Format.tokens(summary.total.total)) Tokens")
            Spacer()
            if showMoney { Text(Format.money(summary.value)) }
        }
        .font(.subheadline.weight(.bold))
        .monospacedDigit()
    }
}

private struct Tile: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption2).tracking(0.6).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

// MARK: - Gemeinsames

/// „work · vor 12 Min.“ – der Mac kann zwischendurch schlafen, darum steht das Alter dabei.
private struct MachineHeader: View {
    let machine: WidgetSnapshot

    var body: some View {
        HStack {
            Text(machine.machine ?? "Mac")
            Spacer()
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(Format.ago(machine.writtenAt, now: context.date))
            }
            .monospacedDigit()
        }
    }
}

private struct StatusSection: View {
    let store: CloudStore

    var body: some View {
        if let status = store.status {
            Section {
                Label(status, systemImage: "icloud")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else if store.machines.isEmpty, store.isLoading {
            Section {
                HStack(spacing: 8) { ProgressView(); Text("Stand wird geladen …") }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
