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
