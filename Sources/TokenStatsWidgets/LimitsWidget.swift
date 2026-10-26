import AppIntents
import SwiftUI
import TokenStatsCore
import WidgetKit

// MARK: Konfiguration

enum LimitsProviderOption: String, AppEnum {
    case tightest, antigravity, claude, codex, ollama

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Anbieter")
    static let caseDisplayRepresentations: [LimitsProviderOption: DisplayRepresentation] = [
        .tightest: "Knappstes Limit", .antigravity: "Antigravity", .claude: "Claude", .codex: "Codex", .ollama: "Ollama",
    ]

    var providerID: String? { self == .tightest ? nil : rawValue }
}

struct LimitsConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Limits"
    static let description = IntentDescription("Session- und Wochenlimit mit Pace-Marke aus Token Stats.")

    @Parameter(title: "Anbieter", default: .tightest)
    var provider: LimitsProviderOption
}

// MARK: Timeline

struct LimitsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let provider: String?
}

struct LimitsTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LimitsEntry {
        LimitsEntry(date: .now, snapshot: DemoData.widgetSnapshot(now: .now), provider: nil)
    }

    func snapshot(for configuration: LimitsConfigurationIntent, in context: Context) async -> LimitsEntry {
        let snapshot = context.isPreview ? DemoData.widgetSnapshot(now: .now) : WidgetSnapshot.load()
        return LimitsEntry(date: .now, snapshot: snapshot, provider: configuration.provider.providerID)
    }

    func timeline(for configuration: LimitsConfigurationIntent, in context: Context) async -> Timeline<LimitsEntry> {
        let entry = LimitsEntry(date: .now, snapshot: WidgetSnapshot.load(), provider: configuration.provider.providerID)
        return Timeline(entries: [entry], policy: .never)
    }
}

// MARK: Widget

struct LimitsWidget: Widget {
    static let kind = "de.mahype.TokenStats.limits"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: LimitsConfigurationIntent.self, provider: LimitsTimelineProvider()) { entry in
            LimitsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Limits")
        .description("Die Meter eines Anbieters mit Reset-Zeit und Pace-Marke – wie im Popover.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct LimitsWidgetEntryView: View {
    let entry: LimitsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let shown = entry.snapshot.flatMap { LimitsWidgetView.resolve($0, provider: entry.provider) }?.id
        LimitsWidgetView(snapshot: entry.snapshot, provider: entry.provider, size: family.size, now: entry.date)
            .widgetURL(WidgetLink.url(.init(page: .limits, provider: family.size == .large ? nil : shown)))
            .containerBackground(.fill.tertiary, for: .widget)
    }
}
