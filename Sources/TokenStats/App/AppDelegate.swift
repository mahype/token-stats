import AppKit
import Observation
import SwiftUI

/// Menüleisten-Symbol: Linksklick öffnet das Popover, Rechtsklick ein Kurzmenü (SPEC §2).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private lazy var store = UsageStore(providers: [ClaudeProvider(), CodexProvider()], settings: settings)
    private lazy var consumption = ConsumptionStore(settings: settings)
    private let updater = Updater()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Als Test-Host weder Endpunkte abfragen noch Logs einlesen.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        #if DEBUG
        if let directory = ProcessInfo.processInfo.environment["TOKENSTATS_SCREENSHOTS"] {
            Screenshots(store: store, consumption: consumption, settings: settings)
                .run(into: URL(filePath: directory))
            return
        }
        #endif

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Token Stats")
        }
        popover.behavior = .transient
        popover.animates = false

        #if DEBUG
        // Für Screenshots: Demo-Werte statt Abfrage und Logs, Einstellungen gleich offen.
        if ProcessInfo.processInfo.environment["TOKENSTATS_OPEN_SETTINGS"] != nil {
            Screenshots(store: store, consumption: consumption, settings: settings).showDemo()
            observeIcon()
            openSettings()
            return
        }
        #endif

        observeIcon()
        store.start()
        consumption.start()
    }

    // MARK: Symbol

    /// Zeichnet das Symbol neu, sobald sich Store oder Einstellungen ändern.
    private func observeIcon() {
        withObservationTracking {
            updateIcon()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeIcon() }
        }
    }

    private func updateIcon() {
        let pick = store.displayed
        let snapshot = pick.flatMap { store.states[$0.providerID]?.snapshot }
        let paused = store.installedProviders.contains { store.states[$0.id]?.isRateLimited == true }
        statusItem.button?.image = StatusIcon.image(.init(
            mode: settings.menuBarMode,
            severity: pick?.window.severity,
            percent: pick?.window.percent,
            bars: snapshot?.windows.prefix(2).map(\.percent) ?? [],
            colored: settings.useStateColor,
            paused: paused
        ))
        statusItem.button?.toolTip = pick.map {
            "\($0.providerName) · \($0.window.name): \(Format.percent($0.window.percent))"
        } ?? "Token Stats"
    }

    // MARK: Klicks

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // Frische View bei jedem Öffnen: knappster Tab aktiv, immer Seite „Limits“.
        consumption.refresh()
        let controller = NSHostingController(rootView: PopoverView(
            store: store, consumption: consumption, settings: settings
        ) { [weak self] in
            self?.openSettings()
        })
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Aktualisieren", action: #selector(refresh), keyEquivalent: "r").target = self

        let modeItem = NSMenuItem(title: "Anzeige-Modus", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for mode in MenuBarMode.allCases {
            let item = NSMenuItem(title: mode.label, action: #selector(setMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settings.menuBarMode == mode ? .on : .off
            modeMenu.addItem(item)
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        let loginItem = NSMenuItem(title: "Bei Anmeldung starten", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = settings.launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        if updater.isAvailable {
            menu.addItem(withTitle: "Nach Updates suchen …", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        }
        menu.addItem(withTitle: "Einstellungen …", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Token Stats beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Menü nur für diesen Klick anhängen, sonst fängt es auch den Linksklick ab.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refresh() { store.refresh(manual: true) }

    @objc private func setMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = MenuBarMode(rawValue: raw) {
            settings.menuBarMode = mode
        }
    }

    @objc private func toggleLaunchAtLogin() { settings.launchAtLogin.toggle() }

    @objc private func checkForUpdates() { updater.checkNow() }

    @objc private func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(
                settings: settings, store: store, consumption: consumption, updater: updater
            ))
            controller.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: controller)
            window.title = "Einstellungen"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
