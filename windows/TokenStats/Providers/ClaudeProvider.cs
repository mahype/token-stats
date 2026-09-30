using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using TokenStats.Model;

namespace TokenStats.Providers;

/// <summary>
/// Claude Code: OAuth-Token aus <c>%USERPROFILE%\.claude\.credentials.json</c>
/// → <c>api.anthropic.com/api/oauth/usage</c>.
///
/// Unter Windows gibt es keinen Schlüsselbund-Eintrag; Claude Code schreibt die Zugangsdaten
/// in diese Datei. Das Token wird nur gelesen und nie erneuert: Ein Refresh rotiert das
/// Refresh-Token, und ohne Zurückschreiben wäre Claude Code danach abgemeldet.
/// Läuft es ab, erneuert Claude Code es beim nächsten Start selbst.
/// </summary>
public sealed partial class ClaudeProvider : IUsageProvider
{
    public string Id => "claude";
    public string DisplayName => "Claude";

    static readonly Uri UsageUrl = new("https://api.anthropic.com/api/oauth/usage");
    const string Hint = "Claude Code einmal starten.";

    static string Home => Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    static string CredentialsFile => Path.Combine(Home, ".claude", ".credentials.json");

    public bool IsInstalled() => Directory.Exists(Path.Combine(Home, ".claude"));

    public async Task<ProviderSnapshot> FetchAsync()
    {
        var credentials = LoadCredentials() ?? throw ProviderException.NotLoggedIn(Hint);
        if (credentials.ExpiresAt is { } expiresAt && expiresAt < DateTimeOffset.UtcNow)
            throw ProviderException.TokenExpired(Hint);

        var data = await Http.GetJsonAsync(UsageUrl, new Dictionary<string, string>
        {
            ["Authorization"] = $"Bearer {credentials.AccessToken}",
            ["anthropic-beta"] = "oauth-2025-04-20",
        }, Hint);
        var snapshot = Parse(data, DateTimeOffset.UtcNow);
        snapshot.Account = new AccountInfo(AccountName(), credentials.Plan);
        return snapshot;
    }

    // Zugangsdaten

    public sealed record Credentials(string AccessToken, DateTimeOffset? ExpiresAt, string? Plan);

    static Credentials? LoadCredentials()
    {
        try { return ParseCredentials(File.ReadAllBytes(CredentialsFile)); }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }

    public static Credentials? ParseCredentials(byte[] data)
    {
        var oauth = JsonRead.ParseObject(data).Obj("claudeAiOauth");
        var token = oauth.Str("accessToken");
        if (string.IsNullOrEmpty(token)) return null;
        var expiresAt = oauth.Num("expiresAt") is { } ms ? DateTimeOffset.FromUnixTimeMilliseconds((long)ms) : (DateTimeOffset?)null;
        return new Credentials(token, expiresAt, PlanName(oauth.Str("subscriptionType"), oauth.Str("rateLimitTier")));
    }

    /// <summary>"max" + "default_claude_max_20x" → "Max 20×"</summary>
    public static string? PlanName(string? subscription, string? tier)
    {
        if (string.IsNullOrEmpty(subscription)) return null;
        var name = char.ToUpperInvariant(subscription[0]) + subscription[1..];
        if (tier is not null && TierPattern().Match(tier) is { Success: true } match)
            name += $" {match.Groups[1].Value}×";
        return name;
    }

    [GeneratedRegex(@"_(\d+)x$")]
    private static partial Regex TierPattern();

    /// <summary>Anzeigename aus <c>~/.claude.json</c> (Kontodaten, keine Zugangsdaten).</summary>
    static string? AccountName()
    {
        try
        {
            var account = JsonRead.ParseObject(File.ReadAllBytes(Path.Combine(Home, ".claude.json"))).Obj("oauthAccount");
            var name = account.Str("displayName") ?? account.Str("emailAddress");
            return string.IsNullOrEmpty(name) ? null : name;
        }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }

    // Antwort

    public static ProviderSnapshot Parse(byte[] data, DateTimeOffset now)
    {
        var response = JsonRead.ParseObject(data);
        var fiveHour = response.Obj("five_hour") ?? throw ProviderException.BadResponse();

        const double week = 7 * 24 * 3600;
        static LimitWindow? Window(string id, string name, string note, JsonObject? source, double length)
        {
            if (source.Num("utilization") is not { } utilization) return null;
            return new LimitWindow
            {
                Id = id, Name = name, ScopeNote = note,
                Percent = utilization / 100,
                ResetsAt = JsonRead.Date(source.Str("resets_at")),
                WindowLength = length,
            };
        }

        var windows = new[]
        {
            Window("session", "Session", "5 h", fiveHour, 5 * 3600),
            Window("week", "Woche", "7 d, alle Modelle", response.Obj("seven_day"), week),
            Window("opus", "Opus", "Wochenlimit", response.Obj("seven_day_opus"), week),
            Window("sonnet", "Sonnet", "Wochenlimit", response.Obj("seven_day_sonnet"), week),
        }.OfType<LimitWindow>().ToList();

        // Neuere Antworten führen Modell-Limits zusätzlich in `limits`.
        foreach (var limit in response.Arr("limits") ?? [])
        {
            if (limit.Str("kind") != "weekly_scoped") continue;
            var name = limit.Obj("scope").Obj("model").Str("display_name");
            if (string.IsNullOrEmpty(name) || limit.Num("percent") is not { } percent
                || windows.Any(w => string.Equals(w.Name, name, StringComparison.OrdinalIgnoreCase)))
                continue;
            windows.Add(new LimitWindow
            {
                Id = $"model-{name.ToLowerInvariant()}", Name = name, ScopeNote = "Wochenlimit",
                Percent = percent / 100, ResetsAt = JsonRead.Date(limit.Str("resets_at")), WindowLength = week,
            });
        }

        var extras = new List<ExtraValue>();
        var extra = response.Obj("extra_usage");
        if (extra.Bool("is_enabled") == true && extra.Num("monthly_limit") is { } monthly and > 0)
        {
            var used = extra.Num("used_credits") ?? 0;
            extras.Add(new ExtraValue("extra", $"Extra {Format.Dollars(used)} / {Format.Dollars(monthly)}"));
        }

        return new ProviderSnapshot { Windows = windows, Extras = extras, FetchedAt = now };
    }
}
