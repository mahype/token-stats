using System.Text;

namespace TokenStats.Tests;

// Antwortformen nach den Fixtures von claudebar/codexbar – dieselben wie in Tests/TokenStatsTests.

public class ClaudeParserTests
{
    static byte[] Utf8(string text) => Encoding.UTF8.GetBytes(text);

    [Fact]
    public void ParsesWindowsAndModelLimits()
    {
        const string json = """
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
            """;
        var snapshot = ClaudeProvider.Parse(Utf8(json), DateTimeOffset.UtcNow);

        Assert.Equal(["Session", "Woche", "Sonnet", "Opus"], snapshot.Windows.Select(w => w.Name));
        Assert.Equal(0.41, snapshot.Windows[0].Percent);
        Assert.Equal(5 * 3600, snapshot.Windows[0].WindowLength);
        Assert.NotNull(snapshot.Windows[1].ResetsAt);   // Datum mit Sekundenbruchteilen
        Assert.Equal("Opus", snapshot.TightestWindow?.Name);
        Assert.Equal(["Extra 12,40 $ / 50,00 $"], snapshot.Extras.Select(e => e.Text));
    }

    [Fact]
    public void RejectsUnexpectedShape()
    {
        var error = Assert.Throws<ProviderException>(() => ClaudeProvider.Parse(Utf8("""{"error":{"message":"nope"}}"""), DateTimeOffset.UtcNow));
        Assert.Equal(ProviderErrorKind.BadResponse, error.Kind);
    }

    [Fact]
    public void DisabledExtraUsageIsHidden()
    {
        const string json = """{"five_hour":{"utilization":6},"extra_usage":{"is_enabled":false,"monthly_limit":20500,"used_credits":572}}""";
        Assert.Empty(ClaudeProvider.Parse(Utf8(json), DateTimeOffset.UtcNow).Extras);
    }

    [Fact]
    public void CredentialsAndPlan()
    {
        const string json = """{"claudeAiOauth":{"accessToken":"t","expiresAt":1893456000000,"subscriptionType":"max","rateLimitTier":"default_claude_max_20x"}}""";
        var credentials = ClaudeProvider.ParseCredentials(Utf8(json));
        Assert.Equal("Max 20×", credentials?.Plan);
        Assert.Equal(DateTimeOffset.FromUnixTimeSeconds(1_893_456_000), credentials?.ExpiresAt);
        Assert.Null(ClaudeProvider.ParseCredentials(Utf8("{}")));
        Assert.Equal("Pro", ClaudeProvider.PlanName("pro", "default_claude_ai"));
    }
}

public class CodexParserTests
{
    static byte[] Utf8(string text) => Encoding.UTF8.GetBytes(text);

    [Fact]
    public void ParsesSessionWeekReviewAndCredits()
    {
        const string json = """
            {"plan_type":"plus",
             "rate_limit":{"primary_window":{"used_percent":10,"reset_at":1893456000,"limit_window_seconds":18000},
                           "secondary_window":{"used_percent":35,"reset_at":1893456000,"limit_window_seconds":604800}},
             "code_review_rate_limit":{"primary_window":{"used_percent":5,"reset_at":1893456000,"limit_window_seconds":604800}},
             "additional_rate_limits":[{"limit_name":"Spark","rate_limit":{"primary_window":{"used_percent":80,"reset_at":1893456000,"limit_window_seconds":18000}}}],
             "credits":{"has_credits":true,"unlimited":false,"balance":"12.5"}}
            """;
        var snapshot = CodexProvider.Parse(Utf8(json), DateTimeOffset.UtcNow);

        Assert.Equal(["Session", "Woche", "Code-Review", "Spark"], snapshot.Windows.Select(w => w.Name));
        Assert.Equal(["5 h", "7 d", "7 d", "5 h"], snapshot.Windows.Select(w => w.ScopeNote));
        Assert.Equal(DateTimeOffset.FromUnixTimeSeconds(1_893_456_000), snapshot.Windows[0].ResetsAt);
        Assert.Equal("Spark", snapshot.TightestWindow?.Name);
        Assert.Equal(["Credits 12,5"], snapshot.Extras.Select(e => e.Text));
        Assert.Equal("plus", snapshot.Account?.Plan);
    }

    [Fact]
    public void SingleWeeklyWindowIsNamedWeek()
    {
        const string json = """{"rate_limit":{"primary_window":{"used_percent":30,"reset_at":9999999999,"limit_window_seconds":604800},"secondary_window":null}}""";
        Assert.Equal(["Woche"], CodexProvider.Parse(Utf8(json), DateTimeOffset.UtcNow).Windows.Select(w => w.Name));
    }

    [Fact]
    public void RejectsUnexpectedShape()
    {
        var error = Assert.Throws<ProviderException>(() => CodexProvider.Parse(Utf8("[]"), DateTimeOffset.UtcNow));
        Assert.Equal(ProviderErrorKind.BadResponse, error.Kind);
    }
}

public class FormatTests
{
    [Fact]
    public void SeverityThresholds()
    {
        Assert.Equal(Severity.Ok, SeverityOf.Percent(0.49));
        Assert.Equal(Severity.Ok, SeverityOf.Percent(0.79));
        Assert.Equal(Severity.Warn, SeverityOf.Percent(0.80));
        Assert.Equal(Severity.Warn, SeverityOf.Percent(0.99));
        Assert.Equal(Severity.Crit, SeverityOf.Percent(1.0));
    }

    [Fact]
    public void PaceText()
    {
        const double week = 7 * 24 * 3600;
        const double session = 5 * 3600;
        Assert.Equal("1 Tag vorgegriffen", Format.Pace(0.82, 0.64, week));
        Assert.Equal("4 Tage ungenutzt", Format.Pace(0.11, 0.70, week));
        Assert.Equal("im Takt", Format.Pace(0.50, 0.51, week));
        Assert.Equal("54 Min. vorgegriffen", Format.Pace(0.60, 0.42, session));
        Assert.Equal("3 Std. ungenutzt", Format.Pace(0.20, 0.80, session));
        Assert.Equal("17 Std. ungenutzt", Format.Pace(0.30, 0.40, week));
    }

    [Fact]
    public void ElapsedFraction()
    {
        var now = DateTimeOffset.FromUnixTimeSeconds(1_000_000);
        var window = new LimitWindow { Id = "w", Name = "Session", Percent = 0.5, ResetsAt = now.AddHours(1), WindowLength = 5 * 3600 };
        Assert.Equal(0.8, window.ElapsedFraction(now));
    }

    [Fact]
    public void ResetTime()
    {
        var berlin = TimeZoneInfo.FindSystemTimeZoneById("Europe/Berlin");
        DateTimeOffset At(int day, int hour) => new(new DateTime(2026, 9, day, hour, 0, 0), berlin.GetUtcOffset(new DateTime(2026, 9, day)));
        var now = At(27, 21);   // Sonntag
        Assert.Equal("23:00", Format.Reset(now.AddHours(2), now, berlin));
        Assert.Equal("morgen 09:00", Format.Reset(At(28, 9), now, berlin));
        Assert.Equal("Mi 09:00", Format.Reset(At(30, 9), now, berlin));
    }

    [Fact]
    public void RetryAfterHeader()
    {
        var now = DateTimeOffset.FromUnixTimeSeconds(1_700_000_000);
        Assert.Equal(TimeSpan.FromSeconds(120), Http.RetryAfter("120", now));
        Assert.Null(Http.RetryAfter("0", now));
        Assert.Equal(TimeSpan.FromHours(6), Http.RetryAfter("999999", now));
        Assert.Equal(TimeSpan.FromSeconds(120), Http.RetryAfter("Tue, 14 Nov 2023 22:15:20 GMT", now));
    }
}

// Antwortformen live geprüft am 05.10.2026 (Google AI Plus, Antigravity-CLI 1.2.17) – wie in Tests/TokenStatsTests.
public class AntigravityParserTests
{
    static byte[] Utf8(string text) => Encoding.UTF8.GetBytes(text);

    [Fact]
    public void ParsesQuotaSummary()
    {
        const string json = """
            {"groups":[
              {"displayName":"Gemini Models","buckets":[
                {"bucketId":"gemini-weekly","displayName":"Weekly Limit Remaining","window":"weekly",
                 "resetTime":"2030-01-08T09:40:51Z","remainingFraction":0.9731712}]},
              {"displayName":"Claude and GPT models","buckets":[
                {"bucketId":"3p-weekly","displayName":"Weekly Limit Remaining","window":"weekly",
                 "resetTime":"2030-01-08T09:43:03Z"}]}
            ]}
            """;
        var snapshot = AntigravityProvider.ParseSummary(Utf8(json), DateTimeOffset.UtcNow);

        Assert.Equal(["Gemini", "Claude & GPT"], snapshot.Windows.Select(w => w.Name));
        Assert.Equal(0.0268288, snapshot.Windows[0].Percent, 6);
        Assert.Equal("Wochenlimit", snapshot.Windows[0].ScopeNote);
        Assert.Equal(7 * 24 * 3600, snapshot.Windows[0].WindowLength);
        Assert.NotNull(snapshot.Windows[0].ResetsAt);
        Assert.Equal(1, snapshot.Windows[1].Percent);   // proto3 lässt remainingFraction 0 weg
    }

    [Fact]
    public void RejectsEmptySummary()
    {
        var error = Assert.Throws<ProviderException>(() => AntigravityProvider.ParseSummary(Utf8("""{"groups":[]}"""), DateTimeOffset.UtcNow));
        Assert.Equal(ProviderErrorKind.BadResponse, error.Kind);
    }

    static string IdToken() =>
        "e30." + Convert.ToBase64String(Utf8("""{"email":"demo@example.com"}""")) + ".sig";

    static string CredentialJson() =>
        $$"""{"token":{"access_token":"ya29.demo","token_type":"Bearer","refresh_token":"1//demo","expiry":"2030-01-01T12:40:22.44965+02:00"},"auth_method":"consumer","id_token":"{{IdToken()}}"}""";

    [Fact]
    public void ReadsPlainJsonFromCredentialManager()
    {
        var credentials = AntigravityProvider.ParseCredentials(Utf8(CredentialJson()));
        Assert.NotNull(credentials);
        Assert.Equal("ya29.demo", credentials.AccessToken);
        Assert.Equal(DateTimeOffset.Parse("2030-01-01T10:40:22.44965Z"), credentials.ExpiresAt);
        Assert.Equal("demo@example.com", credentials.Email);
    }

    [Fact]
    public void ReadsGoKeyringBase64AndHex()
    {
        var base64 = "go-keyring-base64:" + Convert.ToBase64String(Utf8(CredentialJson()));
        var hex = "go-keyring-encoded:" + Convert.ToHexString(Utf8(CredentialJson()));
        Assert.Equal("ya29.demo", AntigravityProvider.ParseCredentials(Utf8(base64))?.AccessToken);
        Assert.Equal("ya29.demo", AntigravityProvider.ParseCredentials(Utf8(hex))?.AccessToken);
    }

    [Fact]
    public void PrefersPaidPlan()
    {
        Assert.Equal("Google AI Plus", AntigravityProvider.ParsePlan(Utf8(
            """{"currentTier":{"id":"free-tier","name":"Antigravity"},"paidTier":{"id":"g1-plus-tier","name":"Google AI Plus"}}""")));
        Assert.Equal("Kostenlos", AntigravityProvider.ParsePlan(Utf8("""{"currentTier":{"id":"free-tier","name":"Antigravity"}}""")));
    }
}

// Antwortformen live geprüft am 05.10.2026 (Ollama 0.34.4, Plan Pro).
// Die Schlüssel sind Wegwerf-Testschlüssel, mit ssh-keygen nur für diese Tests erzeugt – dieselben wie in Tests/TokenStatsTests.
public class OllamaParserTests
{
    static byte[] Utf8(string text) => Encoding.UTF8.GetBytes(text);

    const string TestKey = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
        QyNTUxOQAAACCFGWt6KtdxdL80acjgaOMXtFJyQ6a27gXvrnhipQVXgwAAAJj6EFwj+hBc
        IwAAAAtzc2gtZWQyNTUxOQAAACCFGWt6KtdxdL80acjgaOMXtFJyQ6a27gXvrnhipQVXgw
        AAAEBztlei+ykNm/xS6NUAkFFBysiODcemxYaHSHVhmn/H7oUZa3oq13F0vzRpyOBo4xe0
        UnJDprbuBe+ueGKlBVeDAAAAD3Rva2Vuc3RhdHMtdGVzdAECAwQFBg==
        -----END OPENSSH PRIVATE KEY-----
        """;
    const string TestPublicBlob = "AAAAC3NzaC1lZDI1NTE5AAAAIIUZa3oq13F0vzRpyOBo4xe0UnJDprbuBe+ueGKlBVeD";
    const string EncryptedKey = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABC5axZag5
        HGvJKHGHN8DlKIAAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAICBrYw60CgLyyLUU
        ZwFPxoI+SA/oiGQZQZ83qeTtzG6rAAAAoIFkts3nJposHT6K4w7my0AixN5PiEtLOr7FzD
        Tc5T6EEW4RLz5/RBFk2zup5OZwTb2q55NufEJ9XS4ssRUykbEGq89OB8To3k17rqS/ATUa
        Zd43AvzJEe+M1JNg+0kEn2xdcHWpSeOxltSKOJVPmcBFP0MvOF82xD1QQBgBkF1LvcuqTK
        A9anyo2g9iyJeMEhNI1y0wf5sRDR+qTibdGcg=
        -----END OPENSSH PRIVATE KEY-----
        """;

    [Fact]
    public void SignsLikeOllamaCli()
    {
        var key = OllamaProvider.ParsePrivateKey(TestKey);
        Assert.NotNull(key);
        Assert.Equal(TestPublicBlob, Convert.ToBase64String(key.PublicBlob));

        var header = key.Authorization("GET", "/api/usage", "1790000000");
        var parts = header.Split(':');
        Assert.Equal(2, parts.Length);
        Assert.Equal(TestPublicBlob, parts[0]);

        // Öffentlicher Schlüssel = letzte 32 Byte des SSH-Blobs.
        var verifier = new Org.BouncyCastle.Crypto.Signers.Ed25519Signer();
        verifier.Init(false, new Org.BouncyCastle.Crypto.Parameters.Ed25519PublicKeyParameters(key.PublicBlob[^32..], 0));
        var message = Utf8("GET,/api/usage?ts=1790000000");
        verifier.BlockUpdate(message, 0, message.Length);
        Assert.True(verifier.VerifySignature(Convert.FromBase64String(parts[1])));
    }

    [Fact]
    public void RejectsEncryptedKey()
    {
        Assert.Null(OllamaProvider.ParsePrivateKey(EncryptedKey));
        Assert.Null(OllamaProvider.ParsePrivateKey("kein Schlüssel"));
    }

    [Fact]
    public void ParsesUsage()
    {
        const string json = """
            {"limits":{"session":{"usage":0,"models":[]},
                        "weekly":{"usage":0.031,"models":[{"name":"minimax-m3","request_count":4},
                                                          {"name":"glm-5.3","request_count":71}]}},
             "activity":{"cost":"1.25000","models":[],"period":{"type":"last_4_weeks"}}}
            """;
        var snapshot = OllamaProvider.ParseUsage(Utf8(json), DateTimeOffset.UtcNow);

        Assert.Equal(["Session", "Woche"], snapshot.Windows.Select(w => w.Name));
        Assert.Equal(0.031, snapshot.Windows[1].Percent);
        Assert.All(snapshot.Windows, window => Assert.Null(window.ResetsAt));
        Assert.Equal(["glm-5.3 · 71 Anfragen", "minimax-m3 · 4 Anfragen", "Abgerechnet 1,25 $ / 4 Wochen"],
                     snapshot.Extras.Select(e => e.Text));
    }

    [Fact]
    public void FreeAccountWithMonthlyOnly()
    {
        var snapshot = OllamaProvider.ParseUsage(Utf8("""{"limits":{"monthly":{"usage":0.5}},"activity":{"cost":"0.00000"}}"""), DateTimeOffset.UtcNow);
        Assert.Equal(["Monat"], snapshot.Windows.Select(w => w.Name));
        Assert.Empty(snapshot.Extras);
    }

    [Fact]
    public void RejectsMissingLimits()
    {
        var error = Assert.Throws<ProviderException>(() => OllamaProvider.ParseUsage(Utf8("""{"activity":{"cost":"0"}}"""), DateTimeOffset.UtcNow));
        Assert.Equal(ProviderErrorKind.BadResponse, error.Kind);
    }

    [Fact]
    public void ReadsPlan()
    {
        Assert.Equal(new AccountInfo("demo", "Pro"),
                     OllamaProvider.ParseAccount(Utf8("""{"Name":"demo","Email":"demo@example.com","Plan":"pro"}""")));
    }
}

public class StoreBehaviorTests
{
    [Fact]
    public void WindowResetsToZeroAfterResetTime()
    {
        var now = DateTimeOffset.FromUnixTimeSeconds(1_000_000);
        const double week = 7 * 24 * 3600;
        var window = new LimitWindow { Id = "w", Name = "Gemini", Percent = 0.4, ResetsAt = now.AddHours(-1), WindowLength = week };

        Assert.False(new LimitWindow { Percent = 0.4, ResetsAt = now.AddHours(1), WindowLength = week }.RollOver(now));
        Assert.True(window.RollOver(now));
        Assert.Equal(0, window.Percent);
        Assert.Equal(now.AddSeconds(week - 3600), window.ResetsAt);
    }

    [Fact]
    public void LocalErrorsDoNotCountAgainstInterval()
    {
        Assert.True(ProviderException.TokenExpired("x").IsLocal);
        Assert.True(ProviderException.WaitingForToken("x").IsLocal);
        Assert.True(ProviderException.NotLoggedIn("x").IsLocal);
        Assert.False(ProviderException.Unauthorized("x").IsLocal);
        Assert.Equal("Anmeldung abgelaufen. x", ProviderException.Unauthorized("x").Message);
    }

    sealed class FakeProvider(string id, string name) : IUsageProvider
    {
        public string Id => id;
        public string DisplayName => name;
        public bool IsInstalled() => true;
        public Task<ProviderSnapshot> FetchAsync() => throw new NotSupportedException();
    }

    [Fact]
    public void TabsAreSortedByName()
    {
        var store = new UsageStore(
            [new FakeProvider("ollama", "Ollama"), new FakeProvider("claude", "Claude"), new FakeProvider("antigravity", "Antigravity"), new FakeProvider("codex", "Codex")],
            new AppSettings(), cachePath: null);
        Assert.Equal(["Antigravity", "Claude", "Codex", "Ollama"], store.SortedProviders.Select(p => p.DisplayName));
    }
}
