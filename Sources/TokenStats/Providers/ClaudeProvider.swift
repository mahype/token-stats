import Foundation

/// Claude Code: OAuth-Token aus Schlüsselbund bzw. `~/.claude/.credentials.json`
/// → `api.anthropic.com/api/oauth/usage`.
///
/// Das Token wird nur gelesen und nie erneuert: Ein Refresh rotiert das
/// Refresh-Token, und ohne Zurückschreiben wäre Claude Code danach abgemeldet.
/// Läuft es ab, erneuert Claude Code es beim nächsten Start selbst.
struct ClaudeProvider: UsageProvider {
    let id = "claude"
    let displayName = "Claude"

    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let keychainService = "Claude Code-credentials"
    static let hint = "Claude Code einmal starten."

    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private var credentialsFile: URL { home.appending(path: ".claude/.credentials.json") }

    func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: home.appending(path: ".claude").path)
    }

    func fetch() async throws -> ProviderSnapshot {
        guard let credentials = loadCredentials() else { throw ProviderError.notLoggedIn(hint: Self.hint) }
        if let expiresAt = credentials.expiresAt, expiresAt < .now {
            throw ProviderError.tokenExpired(hint: Self.hint)
        }
        let data = try await HTTP.getJSON(
            Self.usageURL,
            headers: [
                "Authorization": "Bearer \(credentials.accessToken)",
                "anthropic-beta": "oauth-2025-04-20",
            ],
            expiredHint: Self.hint
        )
        var snapshot = try Self.parse(data)
        snapshot.account = AccountInfo(name: accountName(), plan: credentials.plan)
        return snapshot
    }

    // MARK: Zugangsdaten

    struct Credentials {
        var accessToken: String
        var expiresAt: Date?
        var plan: String?
    }

    /// Schlüsselbund und Datei lesen, die länger gültige Quelle gewinnt.
    /// Auf macOS ist der Schlüsselbund maßgeblich; die Datei kann veraltet sein.
    private func loadCredentials() -> Credentials? {
        let candidates = [keychainData(), try? Data(contentsOf: credentialsFile)]
            .compactMap { $0 }
            .compactMap(Self.parseCredentials)
        return candidates.max { ($0.expiresAt ?? .distantPast) < ($1.expiresAt ?? .distantPast) }
    }

    private func keychainData() -> Data? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", Self.keychainService, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    static func parseCredentials(_ data: Data) -> Credentials? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        let expiresAt = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return Credentials(
            accessToken: token,
            expiresAt: expiresAt,
            plan: planName(subscription: oauth["subscriptionType"] as? String, tier: oauth["rateLimitTier"] as? String)
        )
    }

    /// "max" + "default_claude_max_20x" → "Max 20×"
    static func planName(subscription: String?, tier: String?) -> String? {
        guard let subscription, !subscription.isEmpty else { return nil }
        var name = subscription.prefix(1).uppercased() + subscription.dropFirst()
        if let tier, let match = tier.firstMatch(of: /_(\d+)x$/) {
            name += " \(match.1)×"
        }
        return name
    }

    /// Anzeigename aus `~/.claude.json` (Kontodaten, keine Zugangsdaten).
    private func accountName() -> String? {
        guard let data = try? Data(contentsOf: home.appending(path: ".claude.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["oauthAccount"] as? [String: Any]
        else { return nil }
        let name = (account["displayName"] as? String) ?? (account["emailAddress"] as? String)
        return name?.isEmpty == false ? name : nil
    }

    // MARK: Antwort

    private struct Response: Decodable {
        struct Window: Decodable {
            var utilization: Double?
            var resets_at: String?
        }
        struct ScopedLimit: Decodable {
            struct Scope: Decodable {
                struct Model: Decodable { var display_name: String? }
                var model: Model?
            }
            var kind: String?
            var percent: Double?
            var resets_at: String?
            var scope: Scope?
        }
        struct Extra: Decodable {
            var is_enabled: Bool?
            var monthly_limit: Double?
            var used_credits: Double?
        }
        var five_hour: Window?
        var seven_day: Window?
        var seven_day_opus: Window?
        var seven_day_sonnet: Window?
        var limits: [ScopedLimit]?
        var extra_usage: Extra?
    }

    static func parse(_ data: Data, now: Date = .now) throws -> ProviderSnapshot {
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let fiveHour = response.five_hour
        else { throw ProviderError.badResponse }

        let week: TimeInterval = 7 * 24 * 3600
        func window(_ id: String, _ name: String, _ note: String, _ source: Response.Window?, length: TimeInterval) -> LimitWindow? {
            guard let source, let utilization = source.utilization else { return nil }
            return LimitWindow(
                id: id, name: name, scopeNote: note,
                percent: utilization / 100,
                resetsAt: source.resets_at.flatMap(parseDate),
                windowLength: length
            )
        }

        var windows = [
            window("session", "Session", "5 h", fiveHour, length: 5 * 3600),
            window("week", "Woche", "7 d, alle Modelle", response.seven_day, length: week),
            window("opus", "Opus", "Wochenlimit", response.seven_day_opus, length: week),
            window("sonnet", "Sonnet", "Wochenlimit", response.seven_day_sonnet, length: week),
        ].compactMap { $0 }

        // Neuere Antworten führen Modell-Limits zusätzlich in `limits`.
        for limit in response.limits ?? [] where limit.kind == "weekly_scoped" {
            guard let name = limit.scope?.model?.display_name, !name.isEmpty,
                  let percent = limit.percent,
                  !windows.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
            else { continue }
            windows.append(LimitWindow(
                id: "model-\(name.lowercased())", name: name, scopeNote: "Wochenlimit",
                percent: percent / 100, resetsAt: limit.resets_at.flatMap(parseDate), windowLength: week
            ))
        }

        var extras: [ExtraValue] = []
        if let extra = response.extra_usage, extra.is_enabled == true,
           let limit = extra.monthly_limit, limit > 0 {
            let used = extra.used_credits ?? 0
            extras.append(ExtraValue(id: "extra", text: "Extra \(Format.dollars(cents: used)) / \(Format.dollars(cents: limit))"))
        }

        return ProviderSnapshot(account: nil, windows: windows, extras: extras, fetchedAt: now)
    }

    private static func parseDate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
