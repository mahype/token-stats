#if DEBUG
import AppKit
import SwiftUI

/// `make screenshots`: rendert Popover und Menüleisten-Symbol als PNG für die README.
///
/// Die App zeichnet ihre eigenen Views, deshalb braucht das keine Freigabe für
/// Bildschirmaufnahme. Limits kommen aus festen Demo-Werten (keine Abfrage, kein Cache,
/// keine Kontonamen), der Verbrauch aus dem echten Ledger.
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

    private func capture(into directory: URL) async throws {
        store.showDemo(Self.demoSnapshots(now: .now))
        consumption.refresh()
        while !consumption.hasScannedOnce { try await Task.sleep(for: .milliseconds(200)) }

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

    private func render(_ view: some View, _ appearance: NSAppearance.Name, to url: URL) async throws {
        let hosting = NSHostingView(rootView: view)
        hosting.frame.size = hosting.fittingSize
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        window.appearance = NSAppearance(named: appearance)
        window.isReleasedWhenClosed = false
        // Außerhalb des sichtbaren Bereichs, aber eingeblendet – sonst zeichnet SwiftUI nicht.
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(600))
        hosting.layoutSubtreeIfNeeded()

        // Immer 2×: offscreen hängt das Fenster an keinem Retina-Bildschirm.
        let scale: CGFloat = 2
        let bounds = hosting.bounds
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw CocoaError(.fileWriteUnknown) }
        rep.size = bounds.size
        hosting.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
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
}
#endif
