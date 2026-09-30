using System.Globalization;
using System.Text.Json.Nodes;
using TokenStats.Model;

namespace TokenStats.Providers;

/// <summary>
/// Codex: OAuth-Token aus <c>%USERPROFILE%\.codex\auth.json</c> → <c>chatgpt.com/backend-api/wham/usage</c>.
/// Wie bei Claude wird das Token nur gelesen, nie erneuert – das übernimmt die Codex-CLI.
/// </summary>
public sealed class CodexProvider : IUsageProvider
{
    public string Id => "codex";
    public string DisplayName => "Codex";

    static readonly Uri UsageUrl = new("https://chatgpt.com/backend-api/wham/usage");
    const string Hint = "Codex einmal starten oder »codex login«.";

    static string AuthFile =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex", "auth.json");

    public bool IsInstalled() => File.Exists(AuthFile);

    public async Task<ProviderSnapshot> FetchAsync()
    {
        JsonObject? root;
        try { root = JsonRead.ParseObject(File.ReadAllBytes(AuthFile)); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { root = null; }
        var tokens = root.Obj("tokens");
        var accessToken = tokens.Str("access_token");
        if (string.IsNullOrEmpty(accessToken)) throw ProviderException.NotLoggedIn(Hint);

        if (Jwt.Payload(accessToken).Num("exp") is { } exp && DateTimeOffset.FromUnixTimeSeconds((long)exp) < DateTimeOffset.UtcNow)
            throw ProviderException.TokenExpired(Hint);

        var headers = new Dictionary<string, string> { ["Authorization"] = $"Bearer {accessToken}" };
        if (tokens.Str("account_id") is { Length: > 0 } accountId) headers["chatgpt-account-id"] = accountId;
        var snapshot = Parse(await Http.GetJsonAsync(UsageUrl, headers, Hint), DateTimeOffset.UtcNow);

        var claims = tokens.Str("id_token") is { } idToken ? Jwt.Payload(idToken) : null;
        var plan = claims.Obj("https://api.openai.com/auth").Str("chatgpt_plan_type") ?? snapshot.Account?.Plan;
        snapshot.Account = new AccountInfo(
            claims.Str("email"),
            string.IsNullOrEmpty(plan) ? plan : char.ToUpperInvariant(plan[0]) + plan[1..]);
        return snapshot;
    }

    // Antwort

    public static ProviderSnapshot Parse(byte[] data, DateTimeOffset now)
    {
        var response = JsonRead.ParseObject(data);
        var rateLimit = response.Obj("rate_limit") ?? throw ProviderException.BadResponse();

        static LimitWindow? Window(string id, JsonObject? source, string? name = null)
        {
            if (source.Num("used_percent") is not { } used) return null;
            var length = source.Num("limit_window_seconds");
            var (defaultName, note) = Describe(length);
            return new LimitWindow
            {
                Id = id, Name = name ?? defaultName, ScopeNote = note,
                Percent = used / 100,
                ResetsAt = source.Num("reset_at") is { } reset ? DateTimeOffset.FromUnixTimeSeconds((long)reset) : null,
                WindowLength = length,
            };
        }

        // Neuere Antworten haben nur ein Wochenfenster in `primary_window`;
        // `Describe` benennt es dann anhand der Fensterlänge richtig.
        var windows = new[]
        {
            Window("primary", rateLimit.Obj("primary_window")),
            Window("secondary", rateLimit.Obj("secondary_window")),
            Window("review", response.Obj("code_review_rate_limit").Obj("primary_window"), "Code-Review"),
        }.OfType<LimitWindow>().ToList();

        var additional = response.Arr("additional_rate_limits") ?? [];
        for (var index = 0; index < additional.Count; index++)
        {
            var extra = additional[index];
            var name = extra.Str("limit_name") ?? extra.Str("metered_feature") ?? "Weiteres Limit";
            if (Window($"add-{index}-p", extra.Obj("rate_limit").Obj("primary_window"), name) is { } primary) windows.Add(primary);
            if (Window($"add-{index}-s", extra.Obj("rate_limit").Obj("secondary_window"), name) is { } secondary) windows.Add(secondary);
        }

        var extras = new List<ExtraValue>();
        if (response.Obj("credits") is { } credits)
        {
            if (credits.Bool("unlimited") == true)
                extras.Add(new ExtraValue("credits", "Credits unbegrenzt"));
            else if (credits.Bool("has_credits") == true
                     && double.TryParse(credits.Str("balance"), NumberStyles.Float, CultureInfo.InvariantCulture, out var balance))
                extras.Add(new ExtraValue("credits", $"Credits {Format.Number(balance)}"));
        }

        return new ProviderSnapshot
        {
            Account = new AccountInfo(null, response.Str("plan_type")),
            Windows = windows, Extras = extras, FetchedAt = now,
        };
    }

    /// <summary>18000 s → ("Session", "5 h"), 604800 s → ("Woche", "7 d")</summary>
    public static (string Name, string? Note) Describe(double? seconds)
    {
        if (seconds is not > 0) return ("Limit", null);
        var hours = seconds.Value / 3600;
        static int Round(double value) => (int)Math.Round(value, MidpointRounding.AwayFromZero);
        if (hours >= 24 * 6) return ("Woche", $"{Round(hours / 24)} d");
        if (hours >= 24) return ("Tag", $"{Round(hours / 24)} d");
        return ("Session", $"{Round(hours)} h");
    }
}
