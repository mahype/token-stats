using System.Globalization;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json.Nodes;

namespace TokenStats.Providers;

public static class Http
{
    /// <summary>Keine Cookies, kein Cache – nichts bleibt liegen.</summary>
    static readonly HttpClient Client = new(new SocketsHttpHandler { UseCookies = false })
    {
        Timeout = TimeSpan.FromSeconds(15),
    };

    /// <summary>GET mit Bearer-Token. Wirft <see cref="ProviderException"/> für alles außer 200.</summary>
    public static async Task<byte[]> GetJsonAsync(Uri url, IReadOnlyDictionary<string, string> headers, string expiredHint)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.TryAddWithoutValidation("Accept", "application/json");
        foreach (var (key, value) in headers) request.Headers.TryAddWithoutValidation(key, value);

        HttpResponseMessage response;
        try
        {
            response = await Client.SendAsync(request);
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException)
        {
            throw ProviderException.Network(error.Message);
        }
        using (response)
        {
            switch (response.StatusCode)
            {
                case HttpStatusCode.OK:
                    return await response.Content.ReadAsByteArrayAsync();
                case HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden:
                    throw ProviderException.TokenExpired(expiredHint);
                case HttpStatusCode.TooManyRequests:
                    var header = response.Headers.TryGetValues("Retry-After", out var values) ? values.FirstOrDefault() : null;
                    throw ProviderException.RateLimited(RetryAfter(header, DateTimeOffset.UtcNow));
                default:
                    throw ProviderException.Http((int)response.StatusCode);
            }
        }
    }

    /// <summary>Retry-After als Sekunden oder HTTP-Datum; auf 6 h begrenzt.</summary>
    public static TimeSpan? RetryAfter(string? header, DateTimeOffset now)
    {
        header = header?.Trim();
        if (string.IsNullOrEmpty(header)) return null;
        double? seconds = null;
        if (double.TryParse(header, NumberStyles.Float, CultureInfo.InvariantCulture, out var value))
            seconds = value;
        else if (DateTimeOffset.TryParseExact(header, "r", CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date))
            seconds = (date - now).TotalSeconds;
        if (seconds is not > 0) return null;
        return TimeSpan.FromSeconds(Math.Min(seconds.Value, 6 * 3600));
    }
}

public static class Jwt
{
    /// <summary>Payload eines JWT ohne Signaturprüfung – nur für Ablaufzeit und Plan.</summary>
    public static JsonObject? Payload(string token)
    {
        var parts = token.Split('.');
        if (parts.Length < 2) return null;
        var base64 = parts[1].Replace('-', '+').Replace('_', '/');
        base64 = base64.PadRight(base64.Length + (4 - base64.Length % 4) % 4, '=');
        try
        {
            return JsonNode.Parse(Encoding.UTF8.GetString(Convert.FromBase64String(base64))) as JsonObject;
        }
        catch (Exception error) when (error is FormatException or System.Text.Json.JsonException)
        {
            return null;
        }
    }
}

/// <summary>Tolerantes Lesen von JSON-Feldern: falscher Typ oder fehlendes Feld = null.</summary>
public static class JsonRead
{
    public static JsonObject? Obj(this JsonNode? node, string key) => (node as JsonObject)?[key] as JsonObject;

    public static JsonArray? Arr(this JsonNode? node, string key) => (node as JsonObject)?[key] as JsonArray;

    public static string? Str(this JsonNode? node, string key) =>
        (node as JsonObject)?[key] is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;

    public static double? Num(this JsonNode? node, string key) =>
        (node as JsonObject)?[key] is JsonValue value && value.TryGetValue<double>(out var number) ? number : null;

    public static bool? Bool(this JsonNode? node, string key) =>
        (node as JsonObject)?[key] is JsonValue value && value.TryGetValue<bool>(out var flag) ? flag : null;

    public static JsonObject? ParseObject(byte[] data)
    {
        try { return JsonNode.Parse(data) as JsonObject; }
        catch (System.Text.Json.JsonException) { return null; }
    }

    public static DateTimeOffset? Date(string? text) =>
        DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date) ? date : null;
}
