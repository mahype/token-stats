import CryptoKit
import Foundation
import Testing
@testable import TokenStats

// Antwortformen nach den Fixtures von claudebar/codexbar.

@Suite struct ClaudeParserTests {
    @Test func parsesWindowsAndModelLimits() throws {
        let json = """
        {"five_hour":{"utilization":41,"resets_at":"2030-01-01T23:40:00+00:00"},
         "seven_day":{"utilization":82,"resets_at":"2030-01-02T09:00:00.000+00:00"},
         "seven_day_opus":null,
         "seven_day_sonnet":{"utilization":54,"resets_at":"2030-01-02T09:00:00+00:00"},
         "limits":[
           {"kind":"weekly_scoped","percent":54,"resets_at":"2030-01-02T09:00:00+00:00","scope":{"model":{"display_name":"Sonnet"}}},
           {"kind":"weekly_scoped","percent":96,"resets_at":"2030-01-02T09:00:00+00:00","scope":{"model":{"display_name":"Opus"}}},
           {"kind":"weekly_scoped","percent":80,"scope":{"model":null,"surface":"cowork"}}
         ],
         "extra_usage":{"is_enabled":true,"monthly_limit":5000,"used_credits":1240}}
        """
        let snapshot = try ClaudeProvider.parse(Data(json.utf8))

        #expect(snapshot.windows.map(\.name) == ["Session", "Woche", "Sonnet", "Opus"])
        #expect(snapshot.windows[0].percent == 0.41)
        #expect(snapshot.windows[0].windowLength == TimeInterval(5 * 3600))
        #expect(snapshot.windows[1].resetsAt != nil, "Datum mit Sekundenbruchteilen")
        #expect(snapshot.tightestWindow?.name == "Opus")
        #expect(snapshot.extras.map(\.text) == ["Extra 12,40 $ / 50,00 $"])
    }

    @Test func recognizesSignedOutKeychainEntry() {
        let signedOut = #"{"claudeAiOauth":{"accessToken":"","refreshToken":"","expiresAt":0,"subscriptionType":"max"},"mcpOAuth":{}}"#
        let signedIn = #"{"claudeAiOauth":{"accessToken":"sk-ant-demo","expiresAt":1900000000000}}"#
        #expect(ClaudeProvider.isSignedOut(Data(signedOut.utf8)))
        #expect(!ClaudeProvider.isSignedOut(Data(signedIn.utf8)))
        #expect(!ClaudeProvider.isSignedOut(Data(#"{"mcpOAuth":{}}"#.utf8)), "ohne Claude-Eintrag: Datei als Fallback")
        #expect(ClaudeProvider.parseCredentials(Data(signedOut.utf8)) == nil)
    }

    @Test func rejectsUnexpectedShape() {
        #expect(throws: ProviderError.badResponse) {
            try ClaudeProvider.parse(Data(#"{"error":{"message":"nope"}}"#.utf8))
        }
    }

    @Test func disabledExtraUsageIsHidden() throws {
        let json = #"{"five_hour":{"utilization":6},"extra_usage":{"is_enabled":false,"monthly_limit":20500,"used_credits":572}}"#
        #expect(try ClaudeProvider.parse(Data(json.utf8)).extras.isEmpty)
    }

    @Test func credentialsAndPlan() {
        let json = #"{"claudeAiOauth":{"accessToken":"t","expiresAt":1893456000000,"subscriptionType":"max","rateLimitTier":"default_claude_max_20x"}}"#
        let credentials = ClaudeProvider.parseCredentials(Data(json.utf8))
        #expect(credentials?.plan == "Max 20×")
        #expect(credentials?.expiresAt == Date(timeIntervalSince1970: 1_893_456_000))
        #expect(ClaudeProvider.parseCredentials(Data("{}".utf8)) == nil)
        #expect(ClaudeProvider.planName(subscription: "pro", tier: "default_claude_ai") == "Pro")
    }
}

@Suite struct CodexParserTests {
    @Test func parsesSessionWeekReviewAndCredits() throws {
        let json = """
        {"plan_type":"plus",
         "rate_limit":{"primary_window":{"used_percent":10,"reset_at":1893456000,"limit_window_seconds":18000},
                       "secondary_window":{"used_percent":35,"reset_at":1893456000,"limit_window_seconds":604800}},
         "code_review_rate_limit":{"primary_window":{"used_percent":5,"reset_at":1893456000,"limit_window_seconds":604800}},
         "additional_rate_limits":[{"limit_name":"Spark","rate_limit":{"primary_window":{"used_percent":80,"reset_at":1893456000,"limit_window_seconds":18000}}}],
         "credits":{"has_credits":true,"unlimited":false,"balance":"12.5"}}
        """
        let snapshot = try CodexProvider.parse(Data(json.utf8))

        #expect(snapshot.windows.map(\.name) == ["Session", "Woche", "Code-Review", "Spark"])
        #expect(snapshot.windows.map(\.scopeNote) == ["5 h", "7 d", "7 d", "5 h"])
        #expect(snapshot.windows[0].resetsAt == Date(timeIntervalSince1970: 1_893_456_000))
        #expect(snapshot.tightestWindow?.name == "Spark")
        #expect(snapshot.extras.map(\.text) == ["Credits 12,5"])
        #expect(snapshot.account?.plan == "plus")
    }

    @Test func singleWeeklyWindowIsNamedWeek() throws {
        let json = #"{"rate_limit":{"primary_window":{"used_percent":30,"reset_at":9999999999,"limit_window_seconds":604800},"secondary_window":null}}"#
        let snapshot = try CodexProvider.parse(Data(json.utf8))
        #expect(snapshot.windows.map(\.name) == ["Woche"])
    }

    @Test func rejectsUnexpectedShape() {
        #expect(throws: ProviderError.badResponse) { try CodexProvider.parse(Data("[]".utf8)) }
    }
}

// Antwortformen live geprüft am 05.10.2026 (Google AI Plus, Antigravity-CLI 1.2.17).
@Suite struct AntigravityParserTests {
    @Test func parsesQuotaSummary() throws {
        let json = """
        {"groups":[
          {"displayName":"Gemini Models","buckets":[
            {"bucketId":"gemini-weekly","displayName":"Weekly Limit Remaining","window":"weekly",
             "resetTime":"2030-01-08T09:40:51Z","remainingFraction":0.9731712}]},
          {"displayName":"Claude and GPT models","buckets":[
            {"bucketId":"3p-weekly","displayName":"Weekly Limit Remaining","window":"weekly",
             "resetTime":"2030-01-08T09:43:03Z"}]}
        ]}
        """
        let snapshot = try AntigravityProvider.parseSummary(Data(json.utf8))

        #expect(snapshot.windows.map(\.name) == ["Gemini", "Claude & GPT"])
        #expect(abs(snapshot.windows[0].percent - 0.0268288) < 1e-6)
        #expect(snapshot.windows[0].scopeNote == "Wochenlimit")
        #expect(snapshot.windows[0].windowLength == TimeInterval(7 * 24 * 3600))
        #expect(snapshot.windows[0].resetsAt != nil)
        #expect(snapshot.windows[1].percent == 1, "proto3 lässt remainingFraction 0 weg")
    }

    @Test func rejectsEmptySummary() {
        #expect(throws: ProviderError.badResponse) {
            try AntigravityProvider.parseSummary(Data(#"{"groups":[]}"#.utf8))
        }
    }

    @Test func readsGoKeyringCredentials() throws {
        let payload = #"{"email":"demo@example.com"}"#
        let idToken = "e30." + Data(payload.utf8).base64EncodedString() + ".sig"
        let json = #"{"token":{"access_token":"ya29.demo","token_type":"Bearer","refresh_token":"1//demo","#
            + #""expiry":"2030-01-01T12:40:22.44965+02:00"},"auth_method":"consumer","id_token":"\#(idToken)"}"#
        let stored = "go-keyring-base64:" + Data(json.utf8).base64EncodedString()
        let credentials = try #require(AntigravityProvider.parseCredentials(Data(stored.utf8)))

        #expect(credentials.accessToken == "ya29.demo")
        let expected = try #require(ISO8601DateFormatter().date(from: "2030-01-01T10:40:22Z"))
        let expiresAt = try #require(credentials.expiresAt, "Datum mit Sekundenbruchteilen und Zeitzone")
        #expect(abs(expiresAt.timeIntervalSince(expected)) < 1)
        #expect(credentials.email == "demo@example.com")
    }

    @Test func prefersPaidPlan() {
        let paid = #"{"currentTier":{"id":"free-tier","name":"Antigravity"},"paidTier":{"id":"g1-plus-tier","name":"Google AI Plus"}}"#
        let free = #"{"currentTier":{"id":"free-tier","name":"Antigravity"}}"#
        #expect(AntigravityProvider.parsePlan(Data(paid.utf8)) == "Google AI Plus")
        #expect(AntigravityProvider.parsePlan(Data(free.utf8)) == "Kostenlos")
    }
}

// Antwortformen live geprüft am 05.10.2026 (Ollama 0.34.4, Plan Pro).
// Die Schlüssel sind Wegwerf-Testschlüssel, mit ssh-keygen nur für diese Tests erzeugt.
@Suite struct OllamaParserTests {
    static let testKey = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACCFGWt6KtdxdL80acjgaOMXtFJyQ6a27gXvrnhipQVXgwAAAJj6EFwj+hBc
    IwAAAAtzc2gtZWQyNTUxOQAAACCFGWt6KtdxdL80acjgaOMXtFJyQ6a27gXvrnhipQVXgw
    AAAEBztlei+ykNm/xS6NUAkFFBysiODcemxYaHSHVhmn/H7oUZa3oq13F0vzRpyOBo4xe0
    UnJDprbuBe+ueGKlBVeDAAAAD3Rva2Vuc3RhdHMtdGVzdAECAwQFBg==
    -----END OPENSSH PRIVATE KEY-----
    """
    static let testPublicBlob = "AAAAC3NzaC1lZDI1NTE5AAAAIIUZa3oq13F0vzRpyOBo4xe0UnJDprbuBe+ueGKlBVeD"
    static let encryptedKey = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABC5axZag5
    HGvJKHGHN8DlKIAAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAICBrYw60CgLyyLUU
    ZwFPxoI+SA/oiGQZQZ83qeTtzG6rAAAAoIFkts3nJposHT6K4w7my0AixN5PiEtLOr7FzD
    Tc5T6EEW4RLz5/RBFk2zup5OZwTb2q55NufEJ9XS4ssRUykbEGq89OB8To3k17rqS/ATUa
    Zd43AvzJEe+M1JNg+0kEn2xdcHWpSeOxltSKOJVPmcBFP0MvOF82xD1QQBgBkF1LvcuqTK
    A9anyo2g9iyJeMEhNI1y0wf5sRDR+qTibdGcg=
    -----END OPENSSH PRIVATE KEY-----
    """

    @Test func signsLikeOllamaCLI() throws {
        let key = try #require(OllamaProvider.parsePrivateKey(Self.testKey))
        #expect(key.publicBlob.base64EncodedString() == Self.testPublicBlob)

        let header = try key.authorization(method: "GET", path: "/api/usage", timestamp: "1790000000")
        let parts = header.split(separator: ":").map(String.init)
        #expect(parts.count == 2)
        #expect(parts[0] == Self.testPublicBlob)

        // Öffentlicher Schlüssel = letzte 32 Byte des SSH-Blobs.
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: key.publicBlob.suffix(32))
        let signature = try #require(Data(base64Encoded: parts[1]))
        #expect(publicKey.isValidSignature(signature, for: Data("GET,/api/usage?ts=1790000000".utf8)))
    }

    @Test func rejectsEncryptedKey() {
        #expect(OllamaProvider.parsePrivateKey(Self.encryptedKey) == nil)
        #expect(OllamaProvider.parsePrivateKey("kein Schlüssel") == nil)
    }

    @Test func parsesUsage() throws {
        let json = """
        {"limits":{"session":{"usage":0,"models":[]},
                    "weekly":{"usage":0.031,"models":[{"name":"minimax-m3","request_count":4},
                                                      {"name":"glm-5.3","request_count":71}]}},
         "activity":{"cost":"1.25000","models":[],"period":{"type":"last_4_weeks"}}}
        """
        let snapshot = try OllamaProvider.parseUsage(Data(json.utf8))

        #expect(snapshot.windows.map(\.name) == ["Session", "Woche"])
        #expect(snapshot.windows[1].percent == 0.031)
        #expect(snapshot.windows.allSatisfy { $0.resetsAt == nil })
        #expect(snapshot.extras.map(\.text) == [
            "glm-5.3 · 71 Anfragen", "minimax-m3 · 4 Anfragen", "Abgerechnet 1,25 $ / 4 Wochen",
        ])
    }

    @Test func freeAccountWithMonthlyOnly() throws {
        let json = #"{"limits":{"monthly":{"usage":0.5}},"activity":{"cost":"0.00000"}}"#
        let snapshot = try OllamaProvider.parseUsage(Data(json.utf8))
        #expect(snapshot.windows.map(\.name) == ["Monat"])
        #expect(snapshot.extras.isEmpty)
    }

    @Test func rejectsMissingLimits() {
        #expect(throws: ProviderError.badResponse) {
            try OllamaProvider.parseUsage(Data(#"{"activity":{"cost":"0"}}"#.utf8))
        }
    }

    @Test func readsPlan() {
        let me = #"{"Name":"demo","Email":"demo@example.com","Plan":"pro"}"#
        #expect(OllamaProvider.parseAccount(Data(me.utf8)) == AccountInfo(name: "demo", plan: "Pro"))
    }
}

@Suite struct RolloverTests {
    @Test func windowResetsToZeroAfterResetTime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let week: TimeInterval = 7 * 24 * 3600
        let window = LimitWindow(id: "w", name: "Gemini", scopeNote: nil, percent: 0.4,
                                 resetsAt: now.addingTimeInterval(-3600), windowLength: week)
        let rolled = window.rolledOver(now: now)

        #expect(rolled.percent == 0)
        #expect(rolled.resetsAt == now.addingTimeInterval(week - 3600))
        #expect(window.rolledOver(now: now.addingTimeInterval(-7200)) == window, "vor dem Reset unverändert")
    }
}

@Suite struct FormatTests {
    @Test func severityThresholds() {
        #expect(Severity(percent: 0.49) == .ok)
        #expect(Severity(percent: 0.79) == .ok)
        #expect(Severity(percent: 0.80) == .warn)
        #expect(Severity(percent: 0.99) == .warn)
        #expect(Severity(percent: 1.0) == .crit)
    }

    @Test func paceText() {
        let week: TimeInterval = 7 * 24 * 3600
        let session: TimeInterval = 5 * 3600
        #expect(Format.pace(percent: 0.82, elapsed: 0.64, windowLength: week) == "1 Tag vorgegriffen")
        #expect(Format.pace(percent: 0.11, elapsed: 0.70, windowLength: week) == "4 Tage ungenutzt")
        #expect(Format.pace(percent: 0.50, elapsed: 0.51, windowLength: week) == "im Takt")
        #expect(Format.pace(percent: 0.60, elapsed: 0.42, windowLength: session) == "54 Min. vorgegriffen")
        #expect(Format.pace(percent: 0.20, elapsed: 0.80, windowLength: session) == "3 Std. ungenutzt")
        #expect(Format.pace(percent: 0.30, elapsed: 0.40, windowLength: week) == "17 Std. ungenutzt")
    }

    @Test func elapsedFraction() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let window = LimitWindow(id: "w", name: "Session", percent: 0.5,
                                 resetsAt: now.addingTimeInterval(3600), windowLength: 5 * 3600)
        #expect(window.elapsedFraction(now: now) == 0.8)
    }

    @Test func resetTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 21))!  // Sonntag
        let later = calendar.date(byAdding: .hour, value: 2, to: now)!
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 9))!
        #expect(Format.reset(later, now: now, calendar: calendar) == "23:00")
        #expect(Format.reset(wednesday, now: now, calendar: calendar) == "Mi 09:00")
    }

    @Test func retryAfterHeader() {
        #expect(HTTP.retryAfter("120") == 120)
        #expect(HTTP.retryAfter("0") == nil)
        #expect(HTTP.retryAfter("999999") == TimeInterval(6 * 3600))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(HTTP.retryAfter("Tue, 14 Nov 2023 22:15:20 GMT", now: now) == 120)
    }
}
