#if DEBUG
import AppKit
import SwiftUI
import TokenStatsCore

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
            try await render(card(popover(selected: "antigravity")), appearance, to: file("limits-antigravity"))
            try await render(card(popover(selected: "ollama")), appearance, to: file("limits-ollama"))
            try await render(card(popover(selected: "claude", usage: true)), appearance, to: file("usage"))
            try await render(menuBar, appearance, to: file("menubar"))
            try await render(widgets, appearance, to: file("widgets"))
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

    /// Die Widgets „Verbrauch“ und „Limits“ in Klein, Mittel und Groß, mit denselben Demo-Werten.
    private var widgets: some View {
        let snapshot = DemoData.widgetSnapshot(now: .now, prices: consumption.prices)
        func tile(_ content: some View, width: CGFloat, height: CGFloat) -> some View {
            content
                .padding(14)
                .frame(width: width, height: height)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .windowBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator))
        }
        return VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                tile(UsageWidgetView(snapshot: snapshot, provider: nil, period: .today, size: .small), width: 160, height: 160)
                tile(UsageWidgetView(snapshot: snapshot, provider: nil, period: .week, size: .medium), width: 340, height: 160)
            }
            HStack(alignment: .top, spacing: 16) {
                tile(LimitsWidgetView(snapshot: snapshot, provider: nil, size: .small), width: 160, height: 160)
                tile(LimitsWidgetView(snapshot: snapshot, provider: "claude", size: .medium), width: 340, height: 160)
            }
            tile(UsageWidgetView(snapshot: snapshot, provider: "claude", period: .month, size: .large), width: 516, height: 330)
        }
        .padding(20)
        .background(Color(nsColor: .underPageBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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

    // MARK: Demo-Werte – liegen in TokenStatsCore (DemoData), weil auch die Widget-Vorschau sie zeigt.

    static func demoSnapshots(now: Date) -> [String: ProviderSnapshot] { DemoData.snapshots(now: now) }

    static func demoUsage(now: Date, billingDay: Int, prices: PriceTable) -> [String: [UsagePeriod: UsageSummary]] {
        DemoData.usage(now: now, billingDay: billingDay, prices: prices)
    }
}
#endif
