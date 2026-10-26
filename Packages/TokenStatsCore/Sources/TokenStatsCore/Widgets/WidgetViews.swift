import SwiftUI

/// Widget-Größen ohne WidgetKit-Abhängigkeit, damit die Views auch in der App (Screenshots)
/// und später auf iOS gerendert werden können.
public enum WidgetSize: Sendable {
    case small, medium, large
}

/// Ohne Daten (App noch nie gestartet) statt Nullwerten.
public struct WidgetPlaceholder: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            RobotIcon(size: 22)
            Text("Token Stats öffnen")
                .font(.system(size: 12, weight: .semibold))
            Text("Die App liefert den Stand.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Kopfzeile der Widgets: Roboter · Titel · rechts der Zustandspunkt des knappsten Limits.
struct WidgetHeader: View {
    let title: String
    let detail: String?
    let severity: Severity?

    var body: some View {
        HStack(spacing: 6) {
            RobotIcon(size: 13)
            Text(title).font(.system(size: 12, weight: .bold)).lineLimit(1).fixedSize()
            if let detail {
                Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if let severity {
                Circle().fill(severity.color).frame(width: 7, height: 7)
            }
        }
    }
}

// MARK: - Verbrauch

/// Widget „Verbrauch“: Tokens und API-Vergleichswert für einen Zeitraum (Issue #10).
public struct UsageWidgetView: View {
    public let snapshot: WidgetSnapshot?
    /// `nil` = alle Anbieter zusammen.
    public let provider: String?
    public let period: UsagePeriod
    public let size: WidgetSize

    public init(snapshot: WidgetSnapshot?, provider: String?, period: UsagePeriod, size: WidgetSize) {
        self.snapshot = snapshot
        self.provider = provider
        self.period = period
        self.size = size
    }

    public var body: some View {
        if let snapshot {
            content(snapshot)
        } else {
            WidgetPlaceholder()
        }
    }

    private var title: String {
        provider.flatMap { snapshot?.provider($0)?.name } ?? "Verbrauch"
    }

    @ViewBuilder
    private func content(_ snapshot: WidgetSnapshot) -> some View {
        let summary = snapshot.summary(provider: provider, period: period) ?? UsageSummary()
        let severity = snapshot.tightest?.window.severity
        VStack(alignment: .leading, spacing: size == .small ? 6 : 10) {
            WidgetHeader(title: title, detail: period.label, severity: severity)
            if summary.total.isZero {
                Spacer(minLength: 0)
                Text("Keine Einträge in diesem Zeitraum.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                switch size {
                case .small: small(summary, showMoney: snapshot.showMoney)
                case .medium: medium(summary, showMoney: snapshot.showMoney)
                case .large: large(summary, showMoney: snapshot.showMoney)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func small(_ summary: UsageSummary, showMoney: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            Stat(title: "Tokens", value: Format.tokens(summary.total.total),
                 detail: "\(Format.tokens(summary.total.cacheRead)) Cache-Lesen", large: true)
            if showMoney {
                Stat(title: "API-Vergleichswert", value: Format.money(summary.value) + (summary.hasUnpriced ? "*" : ""),
                     detail: nil, large: false)
            }
        }
    }

    private func medium(_ summary: UsageSummary, showMoney: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Stat(title: "Tokens", value: Format.tokens(summary.total.total),
                     detail: "\(Format.tokens(summary.total.cacheRead)) davon Cache-Lesen", large: true)
                if showMoney {
                    Stat(title: "API-Vergleichswert", value: Format.money(summary.value) + (summary.hasUnpriced ? "*" : ""),
                         detail: nil, large: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            chartOrShare(summary)
                .frame(maxWidth: .infinity)
        }
    }

    private func large(_ summary: UsageSummary, showMoney: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                Stat(title: "Tokens", value: Format.tokens(summary.total.total),
                     detail: "\(Format.tokens(summary.total.cacheRead)) davon Cache-Lesen", large: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showMoney {
                    Stat(title: "API-Vergleichswert", value: Format.money(summary.value) + (summary.hasUnpriced ? "*" : ""),
                         detail: "berechnet, keine Kosten", large: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if summary.days.count > 1 {
                DayChart(days: summary.days, compact: true).frame(height: 44)
            }
            VStack(spacing: 0) {
                ForEach(summary.models.prefix(6)) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ModelName.display(line.model)).font(.system(size: 11, weight: .semibold))
                        Text("\(Format.tokens(line.counts.input)) in · \(Format.tokens(line.counts.output)) out · \(Format.tokens(line.counts.cache)) Cache")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if showMoney {
                            Text(line.value.map(Format.money) ?? "ohne Preis")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(line.value == nil ? .secondary : .primary)
                        }
                    }
                    .monospacedDigit()
                    .padding(.vertical, 4)
                    Divider()
                }
                if summary.models.count > 6 {
                    Text("+\(summary.models.count - 6) weitere Modelle")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Mehrtägige Zeiträume zeigen das Tagesdiagramm, „Heute“ den Cache-Anteil.
    @ViewBuilder
    private func chartOrShare(_ summary: UsageSummary) -> some View {
        if summary.days.count > 1 {
            DayChart(days: summary.days, compact: true)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Stat(title: "Input", value: Format.tokens(summary.total.input), detail: nil, large: false)
                Stat(title: "Output", value: Format.tokens(summary.total.output), detail: nil, large: false)
                Stat(title: "Cache", value: Format.tokens(summary.total.cache), detail: nil, large: false)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct Stat: View {
    let title: String
    let value: String
    let detail: String?
    let large: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 9))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: large ? 20 : 14, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Limits

/// Widget „Limits“: die Meter eines Anbieters mit Pace-Marke, wie auf der Seite „Limits“.
public struct LimitsWidgetView: View {
    public let snapshot: WidgetSnapshot?
    /// `nil` = der Anbieter mit dem knappsten Limit.
    public let provider: String?
    public let size: WidgetSize
    public var now: Date

    public init(snapshot: WidgetSnapshot?, provider: String?, size: WidgetSize, now: Date = .now) {
        self.snapshot = snapshot
        self.provider = provider
        self.size = size
        self.now = now
    }

    public var body: some View {
        if let snapshot {
            content(snapshot)
        } else {
            WidgetPlaceholder()
        }
    }

    /// Welcher Anbieter gezeigt wird – gewählt oder der knappste, sonst der erste mit Stand.
    public static func resolve(_ snapshot: WidgetSnapshot, provider: String?) -> WidgetSnapshot.Provider? {
        if let provider { return snapshot.provider(provider) }
        return snapshot.tightest?.provider ?? snapshot.providers.first { $0.snapshot != nil } ?? snapshot.providers.first
    }

    @ViewBuilder
    private func content(_ snapshot: WidgetSnapshot) -> some View {
        switch size {
        case .large:
            VStack(alignment: .leading, spacing: 12) {
                let providers = snapshot.providers.filter { $0.snapshot != nil }
                if providers.isEmpty {
                    WidgetHeader(title: "Limits", detail: nil, severity: nil)
                    noData(snapshot.providers.first)
                } else {
                    ForEach(providers) { provider in
                        section(provider, columns: 2, maxWindows: 4, compact: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .medium, .small:
            let provider = Self.resolve(snapshot, provider: provider)
            VStack(alignment: .leading, spacing: 8) {
                if let provider, provider.snapshot != nil {
                    section(provider, columns: size == .medium ? 2 : 1, maxWindows: size == .medium ? 4 : 2, compact: true)
                } else {
                    WidgetHeader(title: provider?.name ?? "Limits", detail: nil, severity: nil)
                    noData(provider)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func noData(_ provider: WidgetSnapshot.Provider?) -> some View {
        Text(provider?.message ?? "Noch kein Stand – Token Stats fragt beim nächsten Takt ab.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func section(_ provider: WidgetSnapshot.Provider, columns: Int, maxWindows: Int, compact: Bool) -> some View {
        let windows = Array((provider.snapshot?.windows ?? []).prefix(maxWindows))
        // Die Spalten sind schmal; der Zusatz „7 d, alle Modelle“ passt nur im großen Widget.
        let showScope = size == .large
        WidgetHeader(
            title: provider.name,
            detail: provider.isRateLimited ? "Abfrage pausiert" : provider.snapshot?.account?.plan,
            severity: provider.snapshot?.tightestWindow?.severity
        )
        if columns == 1 {
            ForEach(windows) { MeterRow(window: $0, compact: compact, showScope: showScope, stackDetails: true, now: now) }
        } else {
            let rows = stride(from: 0, to: windows.count, by: columns).map { Array(windows[$0..<min($0 + columns, windows.count)]) }
            ForEach(rows.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 14) {
                    ForEach(rows[index]) { MeterRow(window: $0, compact: compact, showScope: showScope, now: now) }
                    if rows[index].count < columns {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}
