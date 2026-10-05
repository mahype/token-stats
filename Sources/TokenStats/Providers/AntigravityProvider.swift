import Foundation

/// Antigravity (Google): OAuth-Token der Antigravity-CLI `agy` aus dem Schlüsselbund
/// → `daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary`.
///
/// Google-Tokens leben nur 1 h und werden nur erneuert, während `agy` auf diesem Mac
/// läuft – die Antigravity-Desktop-App hat ein eigenes Token. Ein abgelaufenes Token ist
/// kein Fehler: Die App zeigt den letzten Stand mit Hinweis, denn Nutzung auf anderen
/// Geräten oder in der Desktop-App fehlt bis zum nächsten `agy`-Start. Wie bei Claude
/// wird nichts erneuert und nichts zurückgeschrieben.
struct AntigravityProvider: UsageProvider {
    let id = "antigravity"
    let displayName = "Antigravity"

    /// RPC-Endpunkt, wie ihn `agy` selbst aufruft (`…/v1internal:<Methode>`).
    static func endpoint(_ method: String) -> URL {
        URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:\(method)")!
    }

    static let keychainService = "gemini"
    static let keychainAccount = "antigravity"
    static let userAgent = "antigravity (TokenStats)"
    static let loginHint = "»agy« im Terminal starten und mit Google anmelden."
    static let waitingHint = "Stand der letzten »agy«-Sitzung. Aktualisiert sich, sobald »agy« auf diesem Mac läuft – Nutzung auf anderen Geräten oder in der Antigravity-App fehlt bis dahin."

    private var cliDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".gemini/antigravity-cli")
    }

    func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: cliDirectory.path)
    }

    func fetch() async throws -> ProviderSnapshot {
        guard let credentials = Keychain.password(service: Self.keychainService, account: Self.keychainAccount)
                .flatMap(Self.parseCredentials),
              let project = projectID()
        else { throw ProviderError.notLoggedIn(hint: Self.loginHint) }
        if let expiresAt = credentials.expiresAt, expiresAt < .now {
            throw ProviderError.waitingForToken(hint: Self.waitingHint)
        }

        let headers = [
            "Authorization": "Bearer \(credentials.accessToken)",
            // Google lässt nur Antigravity-Clients durch (sonst 403 „no valid license“);
            // der Zusatz in Klammern sagt, wer wirklich fragt.
            "User-Agent": Self.userAgent,
        ]
        let data = try await HTTP.postJSON(
            Self.endpoint("retrieveUserQuotaSummary"),
            body: ["project": project], headers: headers, expiredHint: Self.loginHint
        )
        var snapshot = try Self.parseSummary(data)
        // Plan ist Beiwerk: Scheitert die zweite Abfrage, bleiben die Limits trotzdem stehen.
        let tier = try? await HTTP.postJSON(
            Self.endpoint("loadCodeAssist"),
            body: ["metadata": ["ideType": "ANTIGRAVITY"]], headers: headers, expiredHint: Self.loginHint
        )
        snapshot.account = AccountInfo(name: credentials.email, plan: tier.flatMap(Self.parsePlan))
        return snapshot
    }

    /// Von `agy` beim Anmelden zwischengespeichert; ohne Projekt gibt es kein Kontingent.
    private func projectID() -> String? {
        let file = cliDirectory.appending(path: "cache/default_project_id.txt")
        let id = (try? String(contentsOf: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return id?.isEmpty == false ? id : nil
    }

    // MARK: Zugangsdaten

    struct Credentials {
        var accessToken: String
        var expiresAt: Date?
        var email: String?
    }

    /// go-keyring legt `go-keyring-base64:<Base64(JSON)>` ab; ältere Fassungen reines JSON.
    static func parseCredentials(_ data: Data) -> Credentials? {
        var data = data
        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           text.hasPrefix("go-keyring-base64:") {
            var base64 = String(text.dropFirst("go-keyring-base64:".count))
            while base64.count % 4 != 0 { base64 += "=" }
            guard let decoded = Data(base64Encoded: base64) else { return nil }
            data = decoded
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = root["token"] as? [String: Any],
              let accessToken = token["access_token"] as? String, !accessToken.isEmpty
        else { return nil }
        return Credentials(
            accessToken: accessToken,
            expiresAt: (token["expiry"] as? String).flatMap(parseDate),
            email: (root["id_token"] as? String).flatMap(JWT.payload)?["email"] as? String
        )
    }

    // MARK: Antwort

    private struct Summary: Decodable {
        struct Group: Decodable {
            var displayName: String?
            var buckets: [Bucket]?
        }
        struct Bucket: Decodable {
            var bucketId: String?
            var window: String?
            var resetTime: String?
            var remainingFraction: Double?
        }
        var groups: [Group]?
    }

    static func parseSummary(_ data: Data, now: Date = .now) throws -> ProviderSnapshot {
        guard let summary = try? JSONDecoder().decode(Summary.self, from: data), let groups = summary.groups
        else { throw ProviderError.badResponse }

        var windows: [LimitWindow] = []
        for group in groups {
            let name = groupName(group.displayName)
            for bucket in group.buckets ?? [] {
                let window = bucket.window ?? ""
                windows.append(LimitWindow(
                    id: bucket.bucketId ?? "\(name)-\(window)",
                    name: name,
                    scopeNote: scopeNote(window),
                    // proto3 lässt Nullwerte weg: fehlender Rest heißt ausgeschöpft.
                    percent: 1 - (bucket.remainingFraction ?? 0),
                    resetsAt: bucket.resetTime.flatMap(parseDate),
                    windowLength: windowLength(window)
                ))
            }
        }
        guard !windows.isEmpty else { throw ProviderError.badResponse }
        return ProviderSnapshot(account: nil, windows: windows, extras: [], fetchedAt: now)
    }

    /// Bezahlter Plan („Google AI Plus“) vor der Antigravity-Stufe, die nur „Antigravity“ heißt.
    static func parsePlan(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let paid = (root["paidTier"] as? [String: Any])?["name"] as? String, !paid.isEmpty { return paid }
        let current = root["currentTier"] as? [String: Any]
        return (current?["id"] as? String) == "free-tier" ? "Kostenlos" : current?["name"] as? String
    }

    static func groupName(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "Kontingent" }
        switch name.lowercased() {
        case "gemini models": return "Gemini"
        case "claude and gpt models": return "Claude & GPT"
        default: return name
        }
    }

    static func scopeNote(_ window: String) -> String? {
        switch window.lowercased() {
        case "weekly": "Wochenlimit"
        case "daily": "Tageslimit"
        case let other where other.contains("5h") || other.contains("five"): "5 h"
        case "": nil
        default: window
        }
    }

    static func windowLength(_ window: String) -> TimeInterval? {
        switch window.lowercased() {
        case "weekly": 7 * 24 * 3600
        case "daily": 24 * 3600
        case let other where other.contains("5h") || other.contains("five"): 5 * 3600
        default: nil
        }
    }

    private static func parseDate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
