import Foundation
import Observation
import Sparkle

/// Hält Sparkle für die Laufzeit der App (SPEC §7). Ohne diese Referenz stoppen die
/// Prüfungen im Hintergrund stillschweigend.
///
/// In Debug-Builds bleibt Sparkle aus: `make run` baut dieselbe Version wie das letzte
/// Release und würde sich sonst selbst durch den Download ersetzen.
@MainActor @Observable
final class Updater {
    @ObservationIgnored private let controller: SPUStandardUpdaterController?

    /// Spiegelt Sparkles Einstellung, damit der Schalter sofort reagiert.
    var automaticallyChecks: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    init() {
        #if DEBUG
        controller = nil
        #else
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
        automaticallyChecks = controller?.updater.automaticallyChecksForUpdates ?? false
    }

    var isAvailable: Bool { controller != nil }

    var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }

    func checkNow() {
        controller?.checkForUpdates(nil)
    }
}
