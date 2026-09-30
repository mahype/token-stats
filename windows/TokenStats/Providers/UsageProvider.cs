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

public enum ProviderErrorKind { NotLoggedIn, TokenExpired, RateLimited, Http, BadResponse, Network }

public sealed class ProviderException(ProviderErrorKind kind, string? detail = null, TimeSpan? retryAfter = null, int status = 0)
    : Exception(Describe(kind, detail, status))
{
    public ProviderErrorKind Kind { get; } = kind;
    public TimeSpan? RetryAfter { get; } = retryAfter;

    public static ProviderException NotLoggedIn(string hint) => new(ProviderErrorKind.NotLoggedIn, hint);
    public static ProviderException TokenExpired(string hint) => new(ProviderErrorKind.TokenExpired, hint);
    public static ProviderException RateLimited(TimeSpan? retryAfter) => new(ProviderErrorKind.RateLimited, retryAfter: retryAfter);
    public static ProviderException Http(int status) => new(ProviderErrorKind.Http, status: status);
    public static ProviderException BadResponse() => new(ProviderErrorKind.BadResponse);
    public static ProviderException Network(string text) => new(ProviderErrorKind.Network, text);

    static string Describe(ProviderErrorKind kind, string? detail, int status) => kind switch
    {
        ProviderErrorKind.NotLoggedIn => $"Nicht angemeldet. {detail}",
        ProviderErrorKind.TokenExpired => $"Anmeldung abgelaufen. {detail}",
        ProviderErrorKind.RateLimited => "Abfragelimit erreicht.",
        ProviderErrorKind.Http => $"Server antwortet mit HTTP {status}.",
        ProviderErrorKind.BadResponse => "Unerwartete Antwort vom Server.",
        _ => $"Keine Verbindung: {detail}",
    };
}
