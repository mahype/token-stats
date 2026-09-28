import Foundation

/// Ein Anbieter = eine Datei, die dieses Protokoll erfüllt (SPEC §7).
protocol UsageProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    /// Credential-Quelle vorhanden?
    func isInstalled() -> Bool
    func fetch() async throws -> ProviderSnapshot
}

enum ProviderError: Error, Equatable {
    case notLoggedIn(hint: String)
    case tokenExpired(hint: String)
    case rateLimited(retryAfter: TimeInterval?)
    case http(status: Int)
    case badResponse
    case network(String)

    var message: String {
        switch self {
        case .notLoggedIn(let hint): "Nicht angemeldet. \(hint)"
        case .tokenExpired(let hint): "Anmeldung abgelaufen. \(hint)"
        case .rateLimited: "Abfragelimit erreicht."
        case .http(let status): "Server antwortet mit HTTP \(status)."
        case .badResponse: "Unerwartete Antwort vom Server."
        case .network(let text): "Keine Verbindung: \(text)"
        }
    }
}
