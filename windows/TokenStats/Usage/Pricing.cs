using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace TokenStats.Usage;

/// <summary>Tokenzahlen eines Ereignisses oder einer Summe, Cache getrennt (SPEC §3.5).</summary>
public readonly record struct TokenCounts(
    long Input = 0,          // ohne Cache
    long Output = 0,
    long CacheWrite5m = 0,
    long CacheWrite1h = 0,
    long CacheRead = 0)
{
    public long CacheWrite => CacheWrite5m + CacheWrite1h;
    public long Cache => CacheWrite + CacheRead;
    public long Total => Input + Output + Cache;
    public bool IsZero => Total == 0;

    public static TokenCounts operator +(TokenCounts lhs, TokenCounts rhs) => new(
        lhs.Input + rhs.Input, lhs.Output + rhs.Output,
        lhs.CacheWrite5m + rhs.CacheWrite5m, lhs.CacheWrite1h + rhs.CacheWrite1h,
        lhs.CacheRead + rhs.CacheRead);
}

/// <summary>
/// Mitgelieferte Listenpreise mit Datumsstempel (<c>Scripts/update-pricing.sh</c>).
/// Der Betrag daraus ist ein API-Vergleichswert, keine Kosten.
/// </summary>
public sealed partial class PriceTable(DateOnly? asOf, IReadOnlyDictionary<string, PriceTable.Price> models)
{
    public sealed record Price(double Input, double Output, double CacheRead, double CacheWrite5m, double CacheWrite1h);

    sealed record FileShape(string AsOf, Dictionary<string, Price> Models);

    public DateOnly? AsOf { get; } = asOf;
    public IReadOnlyDictionary<string, Price> Models { get; } = models;

    /// <summary>Die Tabelle aus <c>Sources/TokenStats/Resources/pricing.json</c>, als Ressource eingebettet.</summary>
    public static PriceTable Bundled { get; } = LoadBundled();

    static PriceTable LoadBundled()
    {
        using var stream = typeof(PriceTable).Assembly.GetManifestResourceStream("pricing.json");
        if (stream is null) return new PriceTable(null, new Dictionary<string, Price>());
        using var reader = new StreamReader(stream);
        return FromJson(reader.ReadToEnd());
    }

    public static PriceTable FromJson(string json)
    {
        var file = JsonSerializer.Deserialize<FileShape>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true })!;
        var asOf = DateOnly.TryParseExact(file.AsOf, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var date)
            ? date : (DateOnly?)null;
        return new PriceTable(asOf, file.Models);
    }

    /// <summary>Exakter Name, sonst ohne Datums-Suffix, sonst längster bekannter Präfix.</summary>
    public Price? PriceFor(string model)
    {
        if (Models.TryGetValue(model, out var price)) return price;
        if (Models.TryGetValue(DateSuffix().Replace(model, ""), out price)) return price;
        var prefix = Models.Keys.Where(model.StartsWith).MaxBy(key => key.Length);
        return prefix is null ? null : Models[prefix];
    }

    /// <summary>Dollar-Betrag, <c>null</c> wenn das Modell nicht in der Tabelle steht.</summary>
    public double? ValueOf(TokenCounts counts, string model)
    {
        if (PriceFor(model) is not { } price) return null;
        return counts.Input * price.Input
            + counts.Output * price.Output
            + counts.CacheWrite5m * price.CacheWrite5m
            + counts.CacheWrite1h * price.CacheWrite1h
            + counts.CacheRead * price.CacheRead;
    }

    [GeneratedRegex(@"-\d{8}$")]
    internal static partial Regex DateSuffix();
}

/// <summary>"claude-opus-5-5" → "Opus 5.5", "gpt-5.6-sol" → "GPT-5.6 Sol"</summary>
public static class ModelName
{
    static string Capitalized(string text) => text.Length == 0 ? text : char.ToUpperInvariant(text[0]) + text[1..];

    public static string Display(string model)
    {
        var name = PriceTable.DateSuffix().Replace(model, "");
        if (name.StartsWith("claude-", StringComparison.Ordinal))
        {
            var parts = name["claude-".Length..].Split('-', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 0) return model;
            var version = string.Join('.', parts.Skip(1));
            return Capitalized(parts[0]) + (version.Length == 0 ? "" : $" {version}");
        }
        if (name.StartsWith("gpt-", StringComparison.Ordinal))
        {
            var parts = name.Split('-', StringSplitOptions.RemoveEmptyEntries);
            var head = "GPT-" + (parts.Length > 1 ? parts[1] : "");
            return string.Join(' ', new[] { head }.Concat(parts.Skip(2).Select(Capitalized)));
        }
        return model;
    }
}
