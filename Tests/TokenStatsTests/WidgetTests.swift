import Foundation
import Testing
import TokenStatsCore
@testable import TokenStats

// Widget-Stand (Issue #10): Datei in der App Group, Zusammenrechnen über Anbieter, Links.

@Suite struct WidgetSnapshotTests {
    @Test func roundTripsThroughFile() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let snapshot = DemoData.widgetSnapshot(now: now)
        let url = FileManager.default.temporaryDirectory.appending(path: "widget-test-\(UUID().uuidString)/widgets.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try snapshot.write(to: url)
        let loaded = try #require(WidgetSnapshot.load(from: url))
        #expect(loaded.providers == snapshot.providers)
        #expect(loaded.usage == snapshot.usage)
        #expect(loaded.showMoney)
        // ISO 8601 ohne Sekundenbruchteile – auf die Sekunde reicht für „Stand vor 12 Min.“.
        #expect(abs(loaded.writtenAt.timeIntervalSince(snapshot.writtenAt)) < 1)
    }

    @Test func rejectsMissingFileAndOtherVersions() throws {
        #expect(WidgetSnapshot.load(from: URL(filePath: "/nonexistent/widgets.json")) == nil)
        let url = FileManager.default.temporaryDirectory.appending(path: "widget-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"version":99,"writtenAt":"2026-10-26T10:00:00Z","showMoney":true,"providers":[],"usage":[]}"#.utf8).write(to: url)
        #expect(WidgetSnapshot.load(from: url) == nil)
    }

    @Test func tightestSpansProviders() {
        let snapshot = DemoData.widgetSnapshot(now: .now)
        let tightest = snapshot.tightest
        #expect(tightest?.provider.id == "claude")
        #expect(tightest?.window.id == "week")
    }

    @Test func mergesUsageAcrossProviders() throws {
        let snapshot = DemoData.widgetSnapshot(now: .now)
        let claude = try #require(snapshot.summary(provider: "claude", period: .week))
        let codex = try #require(snapshot.summary(provider: "codex", period: .week))
        let all = try #require(snapshot.summary(provider: nil, period: .week))
        #expect(all.total == claude.total + codex.total)
        #expect(abs(all.value - (claude.value + codex.value)) < 0.001)
        #expect(all.models.count == claude.models.count + codex.models.count)
        #expect(all.days.count == 7)
        #expect(all.days.map(\.tokens) == zip(claude.days, codex.days).map { $0.tokens + $1.tokens })
        // Teuerstes Modell zuerst, wie auf der Verbrauchsseite.
        #expect(all.models.map { $0.value ?? -1 } == all.models.map { $0.value ?? -1 }.sorted(by: >))
        #expect(snapshot.summary(provider: "ollama", period: .week) == nil)
    }
}

@Suite struct WidgetLinkTests {
    @Test func buildsAndParsesLinks() throws {
        let usage = WidgetLink.url(.init(page: .usage, provider: "claude", period: .week))
        #expect(usage.absoluteString == "tokenstats://usage?provider=claude&period=week")
        #expect(WidgetLink.parse(usage) == .init(page: .usage, provider: "claude", period: .week))

        let limits = WidgetLink.url(.init(page: .limits))
        #expect(limits.absoluteString == "tokenstats://limits")
        #expect(WidgetLink.parse(limits) == .init(page: .limits))
    }

    @Test func ignoresForeignLinks() throws {
        #expect(WidgetLink.parse(try #require(URL(string: "https://example.org/usage"))) == nil)
        #expect(WidgetLink.parse(try #require(URL(string: "tokenstats://settings"))) == nil)
    }
}
