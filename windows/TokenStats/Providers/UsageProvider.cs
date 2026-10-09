using TokenStats.Model;

namespace TokenStats.Providers;

/// <summary>Ein Anbieter = eine Datei, die dieses Interface erfüllt (SPEC §7).</summary>
public interface IUsageProvider
{
    string Id { get; }
    string DisplayName { get; }
    /// <summary>Credential-Quelle vorhanden?</summary>
    bool IsInstalled();
    Task<ProviderSnapshot> FetchAsync();
}

public enum ProviderErrorKind
{
    NotLoggedIn,
    /// <summary>Ablaufzeit laut Zugangsdaten vorbei – ohne Anfrage erkannt.</summary>
    TokenExpired,
    /// <summary>Server hat das Token abgewiesen (HTTP 401/403).</summary>
    Unauthorized,
    /// <summary>
    /// Token abgelaufen, aber kein Fehler: Erneuert wird es erst bei der nächsten Nutzung der
    /// CLI, bis dahin gilt der letzte Stand (Antigravity).
    /// </summary>
    WaitingForToken,
    RateLimited,
    Http,
    BadResponse,
    Network,
}

public sealed class ProviderException(ProviderErrorKind kind, string? detail = null, TimeSpan? retryAfter = null, int status = 0)
    : Exception(Describe(kind, detail, status))
{
    public ProviderErrorKind Kind { get; } = kind;
    public TimeSpan? RetryAfter { get; } = retryAfter;

    /// <summary>
    /// Fehler aus der lokalen Prüfung der Zugangsdaten: Es ging keine Anfrage raus,
    /// also zählt der Versuch nicht gegen das Abfrageintervall.
    /// </summary>
    public bool IsLocal => Kind is ProviderErrorKind.NotLoggedIn or ProviderErrorKind.TokenExpired or ProviderErrorKind.WaitingForToken;

    public static ProviderException NotLoggedIn(string hint) => new(ProviderErrorKind.NotLoggedIn, hint);
    public static ProviderException TokenExpired(string hint) => new(ProviderErrorKind.TokenExpired, hint);
    public static ProviderException Unauthorized(string hint) => new(ProviderErrorKind.Unauthorized, hint);
    public static ProviderException WaitingForToken(string hint) => new(ProviderErrorKind.WaitingForToken, hint);
    public static ProviderException RateLimited(TimeSpan? retryAfter) => new(ProviderErrorKind.RateLimited, retryAfter: retryAfter);
    public static ProviderException Http(int status) => new(ProviderErrorKind.Http, status: status);
    public static ProviderException BadResponse() => new(ProviderErrorKind.BadResponse);
    public static ProviderException Network(string text) => new(ProviderErrorKind.Network, text);

    static string Describe(ProviderErrorKind kind, string? detail, int status) => kind switch
    {
        ProviderErrorKind.NotLoggedIn => $"Nicht angemeldet. {detail}",
        ProviderErrorKind.TokenExpired or ProviderErrorKind.Unauthorized => $"Anmeldung abgelaufen. {detail}",
        ProviderErrorKind.WaitingForToken => detail ?? "",
        ProviderErrorKind.RateLimited => "Abfragelimit erreicht.",
        ProviderErrorKind.Http => $"Server antwortet mit HTTP {status}.",
        ProviderErrorKind.BadResponse => "Unerwartete Antwort vom Server.",
        _ => $"Keine Verbindung: {detail}",
    };
}
