import AppKit
import SwiftUI

/// Seite „Verbrauch“: Tokens und API-Vergleichswert je Zeitraum (SPEC §3.5).
struct UsageView: View {
    let providerID: String
    let consumption: ConsumptionStore
    let showMoney: Bool
    let subscription: Int?

    @State private var period: UsagePeriod = .week
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !ConsumptionStore.providers.contains(providerID) {
                placeholder("Für diesen Anbieter gibt es noch keine Verbrauchsauswertung.")
            } else {
                periodPicker
                periodContent
            }
        }
    }

    @ViewBuilder
    private var periodContent: some View {
        if let summary = consumption.summary(providerID, period) {
            if summary.total.isZero {
                placeholder("Keine Einträge in diesem Zeitraum.")
            } else {
                content(summary)
            }
        } else if let failure = consumption.failure {
            placeholder(failure)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Verbrauch wird eingelesen …")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private var periodPicker: some View {
        HStack(spacing: 12) {
            ForEach(UsagePeriod.allCases) { option in
                Button(option.label) { period = option }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: option == period ? .bold : .regular))
                    .foregroundStyle(option == period ? .primary : .secondary)
                    .fixedSize()
            }
            Spacer()
            if let summary = consumption.summary(providerID, period), !summary.total.isZero {
                copyButton(summary)
            }
        }
    }

    /// Kopiert den Zeitraum als CSV – je Modell und je Tag – in die Zwischenablage,
    /// für Tabellenkalkulation oder Abrechnung.
    private func copyButton(_ summary: UsageSummary) -> some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(UsageCSV.render(summary, showMoney: showMoney), forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            // Beide Beschriftungen liegen übereinander, damit der Button beim Wechsel
            // auf „Kopiert“ nicht breiter wird und die Zeitraum-Labels verschiebt.
            ZStack(alignment: .trailing) {
                Label("Kopiert", systemImage: "checkmark").opacity(copied ? 1 : 0)
                Label("CSV", systemImage: "doc.on.doc").opacity(copied ? 0 : 1)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize()
        }
        .buttonStyle(.plain)
        .help("Verbrauch dieses Zeitraums als CSV kopieren")
        .accessibilityLabel("Verbrauch als CSV kopieren")
    }

    @ViewBuilder
    private func content(_ summary: UsageSummary) -> some View {
        HStack(spacing: 10) {
            Tile(
                title: "Tokens",
                value: Format.tokens(summary.total.total),
                detail: "\(Format.tokens(summary.total.cacheRead)) davon Cache-Lesen"
            )
            if showMoney {
                Tile(
                    title: "API-Vergleichswert",
                    value: Format.money(summary.value) + (summary.hasUnpriced ? "*" : ""),
                    detail: subscription.map { "Abo \($0) $ / Monat" } ?? "berechnet"
                )
            }
        }

        if summary.days.count > 1 {
            DayChart(days: summary.days)
        }

        VStack(spacing: 0) {
            ForEach(summary.models) { line in
                ModelRow(line: line, showMoney: showMoney)
                Divider()
            }
            HStack {
                Text("\(period.label) · \(Format.tokens(summary.total.total)) Tokens")
                Spacer()
                if showMoney { Text(Format.money(summary.value)) }
            }
            .font(.system(size: 12, weight: .bold))
            .monospacedDigit()
            .padding(.top, 8)
        }

        Text(footnote(summary))
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func footnote(_ summary: UsageSummary) -> String {
        var text = "Tokenzahlen aus den Session-Logs dieses Macs – Nutzung auf anderen Geräten fehlt"
        if showMoney {
            let asOf = consumption.prices.asOf.map { " (Stand \($0.formatted(.dateTime.month(.twoDigits).year().locale(Format.locale))))" } ?? ""
            text += " × Listenpreis\(asOf), inkl. Cache-Tarife. Keine Abrechnungsdaten – nur, was derselbe Verbrauch über die API gekostet hätte."
            if summary.hasUnpriced { text += " * Modelle ohne Listenpreis sind nicht eingerechnet." }
        } else {
            text += "."
        }
        return text
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }
}

private struct Tile: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .monospacedDigit()
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 8).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }
}

/// Eine Säule pro Tag, der heutige Tag hervorgehoben.
private struct DayChart: View {
    let days: [UsageSummary.DayTotal]

    var body: some View {
        let peak = max(days.map(\.tokens).max() ?? 0, 1)
        let showLabels = days.count <= 7
        HStack(alignment: .bottom, spacing: days.count > 14 ? 2 : 6) {
            ForEach(days) { day in
                let isToday = day.id == days.last?.id
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        VStack {
                            Spacer(minLength: 0)
                            UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                                .fill(Color.accentColor.opacity(isToday ? 1 : 0.55))
                                .frame(height: max(geo.size.height * CGFloat(day.tokens) / CGFloat(peak), day.tokens > 0 ? 2 : 0))
                        }
                    }
                    if showLabels {
                        Text(day.day.formatted(.dateTime.weekday(.abbreviated).locale(Format.locale)))
                            .font(.system(size: 9.5, weight: isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? .primary : .secondary)
                    }
                }
                .help("\(day.day.formatted(.dateTime.weekday(.wide).day().month().locale(Format.locale))): \(Format.tokens(day.tokens)) Tokens")
            }
        }
        .frame(height: showLabels ? 72 : 56)
    }
}

private struct ModelRow: View {
    let line: UsageSummary.ModelLine
    let showMoney: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ModelName.display(line.model)).font(.system(size: 12, weight: .semibold))
                Text("\(Format.tokens(line.counts.input)) in · \(Format.tokens(line.counts.output)) out · \(Format.tokens(line.counts.cache)) Cache")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .help("Cache-Schreiben \(Format.tokens(line.counts.cacheWrite)) · Cache-Lesen \(Format.tokens(line.counts.cacheRead))")
            }
            Spacer()
            if showMoney {
                Text(line.value.map(Format.money) ?? "ohne Preis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(line.value == nil ? .secondary : .primary)
            }
        }
        .monospacedDigit()
        .padding(.vertical, 7)
    }
}
