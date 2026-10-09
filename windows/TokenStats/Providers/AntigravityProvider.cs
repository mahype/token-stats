using System.Text;
using System.Text.Json.Nodes;
using TokenStats.Model;

namespace TokenStats.Providers;

/// <summary>
/// Antigravity (Google): OAuth-Token der Antigravity-CLI <c>agy</c> aus der
/// Anmeldeinformationsverwaltung → <c>daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary</c>.
///
/// Google-Tokens leben nur 1 h und werden nur erneuert, während <c>agy</c> auf diesem Rechner
/// läuft – die Antigravity-Desktop-App hat ein eigenes Token. Ein abgelaufenes Token ist
/// kein Fehler: Die App zeigt den letzten Stand mit Hinweis, denn Nutzung auf anderen
/// Geräten oder in der Desktop-App fehlt bis zum nächsten <c>agy</c>-Start. Wie bei Claude
/// wird nichts erneuert und nichts zurückgeschrieben.
/// </summary>
public sealed class AntigravityProvider : IUsageProvider
{
    public string Id => "antigravity";
    public string DisplayName => "Antigravity";

    /// <summary>go-keyring: generische Anmeldeinformation „dienst:konto“.</summary>
    const string CredentialTarget = "gemini:antigravity";
    /// <summary>Google lässt nur Antigravity-Clients durch (sonst 403 „no valid license“); der Zusatz sagt, wer wirklich fragt.</summary>
    const string UserAgent = "antigravity (TokenStats)";
    const string LoginHint = "»agy« im Terminal starten und mit Google anmelden.";
    public const string WaitingHint = "Stand der letzten »agy«-Sitzung. Aktualisiert sich, sobald »agy« auf diesem Rechner läuft – "
                                    + "Nutzung auf anderen Geräten oder in der Antigravity-App fehlt bis dahin.";

    /// <summary>RPC-Endpunkt, wie ihn <c>agy</c> selbst aufruft (<c>…/v1internal:&lt;Methode&gt;</c>).</summary>
    static Uri Endpoint(string method) => new($"https://daily-cloudcode-pa.googleapis.com/v1internal:{method}");

    static string CliDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".gemini", "antigravity-cli");

    public bool IsInstalled() => Directory.Exists(CliDirectory);

    public async Task<ProviderSnapshot> FetchAsync()
    {
        var credentials = CredentialManager.ReadGeneric(CredentialTarget) is { } blob ? ParseCredentials(blob) : null;
        var project = ProjectId();
        if (credentials is null || project is null) throw ProviderException.NotLoggedIn(LoginHint);
        if (credentials.ExpiresAt is { } expiresAt && expiresAt < DateTimeOffset.UtcNow)
            throw ProviderException.WaitingForToken(WaitingHint);

        var headers = new Dictionary<string, string>
        {
            ["Authorization"] = $"Bearer {credentials.AccessToken}",
            ["User-Agent"] = UserAgent,
        };
        var data = await Http.PostJsonAsync(Endpoint("retrieveUserQuotaSummary"), new JsonObject { ["project"] = project },
                                            headers, LoginHint);
        var snapshot = ParseSummary(data, DateTimeOffset.UtcNow);
        // Plan ist Beiwerk: Scheitert die zweite Abfrage, bleiben die Limits trotzdem stehen.
        string? plan = null;
        try
        {
            var tier = await Http.PostJsonAsync(Endpoint("loadCodeAssist"),
                                                new JsonObject { ["metadata"] = new JsonObject { ["ideType"] = "ANTIGRAVITY" } },
                                                headers, LoginHint);
            plan = ParsePlan(tier);
        }
        catch (ProviderException) { }
        snapshot.Account = new AccountInfo(credentials.Email, plan);
        return snapshot;
    }

    /// <summary>Von <c>agy</c> beim Anmelden zwischengespeichert; ohne Projekt gibt es kein Kontingent.</summary>
    static string? ProjectId()
    {
        try
        {
            var id = File.ReadAllText(Path.Combine(CliDirectory, "cache", "default_project_id.txt")).Trim();
            return id.Length > 0 ? id : null;
        }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }

    // Zugangsdaten

    public sealed record Credentials(string AccessToken, DateTimeOffset? ExpiresAt, string? Email);

    /// <summary>
    /// Unter Windows reines JSON; go-keyring kennt außerdem <c>go-keyring-base64:</c> (macOS)
    /// und <c>go-keyring-encoded:</c> (Hex) – beides wird mitgelesen.
    /// </summary>
    public static Credentials? ParseCredentials(byte[] data)
    {
        var text = Encoding.UTF8.GetString(data).Trim();
        try
        {
            if (text.StartsWith("go-keyring-base64:", StringComparison.Ordinal))
                data = Convert.FromBase64String(text["go-keyring-base64:".Length..]);
            else if (text.StartsWith("go-keyring-encoded:", StringComparison.Ordinal))
                data = Convert.FromHexString(text["go-keyring-encoded:".Length..]);
        }
        catch (FormatException) { return null; }

        var root = JsonRead.ParseObject(data);
        var token = root.Obj("token");
        var accessToken = token.Str("access_token");
        if (string.IsNullOrEmpty(accessToken)) return null;
        var idToken = root.Str("id_token");
        return new Credentials(
            accessToken,
            JsonRead.Date(token.Str("expiry")),
            idToken is null ? null : Jwt.Payload(idToken).Str("email"));
    }

    // Antwort

    public static ProviderSnapshot ParseSummary(byte[] data, DateTimeOffset now)
    {
        var groups = JsonRead.ParseObject(data).Arr("groups") ?? throw ProviderException.BadResponse();
        var windows = new List<LimitWindow>();
        foreach (var group in groups)
        {
            var name = GroupName(group.Str("displayName"));
            foreach (var bucket in group.Arr("buckets") ?? [])
            {
                var window = bucket.Str("window") ?? "";
                windows.Add(new LimitWindow
                {
                    Id = bucket.Str("bucketId") ?? $"{name}-{window}",
                    Name = name,
                    ScopeNote = ScopeNote(window),
                    // proto3 lässt Nullwerte weg: fehlender Rest heißt ausgeschöpft.
                    Percent = 1 - (bucket.Num("remainingFraction") ?? 0),
                    ResetsAt = JsonRead.Date(bucket.Str("resetTime")),
                    WindowLength = WindowLength(window),
                });
            }
        }
        if (windows.Count == 0) throw ProviderException.BadResponse();
        return new ProviderSnapshot { Windows = windows, FetchedAt = now };
    }

    /// <summary>Bezahlter Plan („Google AI Plus“) vor der Antigravity-Stufe, die nur „Antigravity“ heißt.</summary>
    public static string? ParsePlan(byte[] data)
    {
        var root = JsonRead.ParseObject(data);
        if (root.Obj("paidTier").Str("name") is { Length: > 0 } paid) return paid;
        var current = root.Obj("currentTier");
        return current.Str("id") == "free-tier" ? "Kostenlos" : current.Str("name");
    }

    public static string GroupName(string? name)
    {
        if (string.IsNullOrEmpty(name)) return "Kontingent";
        return name.ToLowerInvariant() switch
        {
            "gemini models" => "Gemini",
            "claude and gpt models" => "Claude & GPT",
            _ => name,
        };
    }

    public static string? ScopeNote(string window) => window.ToLowerInvariant() switch
    {
        "" => null,
        "weekly" => "Wochenlimit",
        "daily" => "Tageslimit",
        var other when other.Contains("5h") || other.Contains("five") => "5 h",
        _ => window,
    };

    public static double? WindowLength(string window) => window.ToLowerInvariant() switch
    {
        "weekly" => 7 * 24 * 3600,
        "daily" => 24 * 3600,
        var other when other.Contains("5h") || other.Contains("five") => 5 * 3600,
        _ => null,
    };
}
