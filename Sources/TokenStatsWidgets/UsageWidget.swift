import AppIntents
import SwiftUI
import TokenStatsCore
import WidgetKit

// MARK: Konfiguration

enum PeriodOption: String, AppEnum {
    case today, week, month, billing

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Zeitraum")
    static let caseDisplayRepresentations: [PeriodOption: DisplayRepresentation] = [
        .today: "Heute", .week: "7 Tage", .month: "30 Tage", .billing: "Abrechnungsmonat",
    ]

    var period: UsagePeriod { UsagePeriod(rawValue: rawValue) ?? .today }
}

enum UsageProviderOption: String, AppEnum {
    case all, claude, codex

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Anbieter")
    static let caseDisplayRepresentations: [UsageProviderOption: DisplayRepresentation] = [
        .all: "Alle Anbieter", .claude: "Claude", .codex: "Codex",
    ]

    var providerID: String? { self == .all ? nil : rawValue }
}

struct UsageConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Verbrauch"
    static let description = IntentDescription("Tokens und API-Vergleichswert aus Token Stats.")

    @Parameter(title: "Zeitraum", default: .today)
    var period: PeriodOption

    @Parameter(title: "Anbieter", default: .all)
    var provider: UsageProviderOption
}

// MARK: Timeline

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let provider: String?
    let period: UsagePeriod
}

/// Eine Entry je Aktualisierung, `.never`: Die App stößt das Neuladen an, sobald sie
/// einen neuen Stand geschrieben hat.
struct UsageTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: DemoData.widgetSnapshot(now: .now), provider: nil, period: .today)
    }

    func snapshot(for configuration: UsageConfigurationIntent, in context: Context) async -> UsageEntry {
        let snapshot = context.isPreview ? DemoData.widgetSnapshot(now: .now) : WidgetSnapshot.loadForWidgets()
        return UsageEntry(date: .now, snapshot: snapshot, provider: configuration.provider.providerID,
                          period: configuration.period.period)
    }

    func timeline(for configuration: UsageConfigurationIntent, in context: Context) async -> Timeline<UsageEntry> {
        let entry = UsageEntry(date: .now, snapshot: WidgetSnapshot.loadForWidgets(), provider: configuration.provider.providerID,
                               period: configuration.period.period)
        return Timeline(entries: [entry], policy: .never)
    }
}

// MARK: Widget

struct UsageWidget: Widget {
    static let kind = "de.mahype.TokenStats.usage"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: UsageConfigurationIntent.self, provider: UsageTimelineProvider()) { entry in
            UsageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Verbrauch")
        .description("Tokens und API-Vergleichswert für Heute, 7 Tage, 30 Tage oder den Abrechnungsmonat.")
        .supportedFamilies(WidgetFamily.systemFamilies)
    }
}

struct UsageWidgetEntryView: View {
    let entry: UsageEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        UsageWidgetView(snapshot: entry.snapshot, provider: entry.provider, period: entry.period, size: family.size)
            .widgetURL(WidgetLink.url(.init(page: .usage, provider: entry.provider, period: entry.period)))
            .containerBackground(.fill.tertiary, for: .widget)
    }
}
