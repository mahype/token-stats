import SwiftUI
import TokenStatsCore
import UIKit
import WidgetKit

/// iOS-App (Issue #11): zeigt den Stand der Macs aus iCloud – Limits und Verbrauch –, rechnet
/// nichts selbst und fragt keinen Anbieter ab. Alles nur lesend.
@main
struct TokenStatsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            ContentView(store: CloudStore.shared)
                .task { await CloudStore.shared.start() }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    Task { await CloudStore.shared.refresh() }
                }
        }
    }
}

/// Stiller Push aus CloudKit: nachladen und die Widgets anstoßen. Keine sichtbare
/// Mitteilung, darum auch keine Berechtigungsabfrage.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await CloudStore.shared.refresh()
        return .newData
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        NSLog("Token Stats: kein Push – \(error.localizedDescription)")
    }
}
