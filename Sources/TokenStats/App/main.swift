import AppKit

// Agent-App ohne Dock-Icon (LSUIElement); alles hängt am Menüleisten-Symbol.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
