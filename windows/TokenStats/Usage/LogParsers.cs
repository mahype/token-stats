using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace TokenStats.Usage;

/// <summary>Ein Verbrauchsereignis aus einem Session-Log.</summary>
/// <param name="DedupKey">Schlüssel für die globale Deduplizierung, <c>null</c> = nicht deduplizieren.</param>
public sealed record UsageEvent(DateTimeOffset Timestamp, string Model, TokenCounts Counts, string? DedupKey);

/// <summary>
/// Claude Code: <c>~/.claude/projects/**/*.jsonl</c>, eine Zeile je Inhaltsblock.
/// Dieselbe Antwort steht mehrfach im Log (und in fortgesetzten Sessions erneut),
/// daher Deduplizierung über <c>message.id</c> + <c>requestId</c> wie bei ccusage.
/// </summary>
public static class ClaudeLogParser
{
    public static UsageEvent? Parse(ReadOnlyMemory<byte> line)
    {
        // Schneller Vorfilter, bevor eine Zeile dekodiert wird.
        var span = line.Span;
        if (span.IndexOf("\"type\":\"assistant\""u8) < 0 || span.IndexOf("\"usage\""u8) < 0) return null;

        JsonDocument document;
        try { document = JsonDocument.Parse(line); }
        catch (JsonException) { return null; }
        using (document)
        {
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object || Text(root, "type") != "assistant"
                || !Child(root, "message", out var message) || !Child(message, "usage", out var usage)
                || Text(message, "model") is not { } model || model == "<synthetic>"
                || Timestamp.Parse(Text(root, "timestamp")) is not { } timestamp)
                return null;

            // Cache-Write nach Lebensdauer getrennt, weil 1 h teurer ist als 5 min.
            var write = Int(usage, "cache_creation_input_tokens") ?? 0;
            Child(usage, "cache_creation", out var creation);
            var write1h = Int(creation, "ephemeral_1h_input_tokens") ?? 0;
            var write5m = Int(creation, "ephemeral_5m_input_tokens") ?? Math.Max(write - write1h, 0);
            var counts = new TokenCounts(
                Input: Int(usage, "input_tokens") ?? 0,
                Output: Int(usage, "output_tokens") ?? 0,
                CacheWrite5m: write5m,
                CacheWrite1h: write1h,
                CacheRead: Int(usage, "cache_read_input_tokens") ?? 0);
            if (counts.IsZero) return null;

            var id = Text(message, "id");
            var request = Text(root, "requestId");
            return new UsageEvent(timestamp, model, counts, id is not null && request is not null ? $"{id}:{request}" : null);
        }
    }

    static bool Child(JsonElement element, string name, out JsonElement child)
    {
        child = default;
        return element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out child)
            && child.ValueKind == JsonValueKind.Object;
    }

    static string? Text(JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value)
        && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    static long? Int(JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value)
        && value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out var number) ? number : null;
}

/// <summary>
/// Codex: <c>~/.codex/sessions/**/rollout-*.jsonl</c> (später <c>archived_sessions/</c>).
/// <c>token_count</c>-Ereignisse tragen kumulierte Summen; gezählt wird die Differenz
/// zum vorherigen Stand derselben Datei – robust gegen wiederholte Ereignisse.
/// </summary>
public static class CodexLogParser
{
    /// <summary>Zustand je Datei, wird mit dem Lese-Offset gespeichert.</summary>
    public sealed class FileState
    {
        [JsonPropertyName("model")] public string? Model { get; set; }
        [JsonPropertyName("lastTotal")] public Totals? LastTotal { get; set; }
    }

    public sealed record Totals(
        [property: JsonPropertyName("input_tokens")] long? InputTokens = null,
        [property: JsonPropertyName("cached_input_tokens")] long? CachedInputTokens = null,
        [property: JsonPropertyName("cache_write_input_tokens")] long? CacheWriteInputTokens = null,
        [property: JsonPropertyName("output_tokens")] long? OutputTokens = null)
    {
        [JsonIgnore] public long Input => InputTokens ?? 0;
        [JsonIgnore] public long Cached => CachedInputTokens ?? 0;
        [JsonIgnore] public long CacheWrite => CacheWriteInputTokens ?? 0;
        [JsonIgnore] public long Output => OutputTokens ?? 0;

        public bool IsAtLeast(Totals other) =>
            Input >= other.Input && Cached >= other.Cached && CacheWrite >= other.CacheWrite && Output >= other.Output;
    }

    sealed class Line
    {
        public sealed class PayloadShape
        {
            public sealed class InfoShape
            {
                [JsonPropertyName("total_token_usage")] public Totals? TotalTokenUsage { get; set; }
                [JsonPropertyName("last_token_usage")] public Totals? LastTokenUsage { get; set; }
            }
            [JsonPropertyName("type")] public string? Type { get; set; }
            [JsonPropertyName("model")] public string? Model { get; set; }
            [JsonPropertyName("info")] public InfoShape? Info { get; set; }
        }
        [JsonPropertyName("type")] public string? Type { get; set; }
        [JsonPropertyName("timestamp")] public string? Timestamp { get; set; }
        [JsonPropertyName("payload")] public PayloadShape? Payload { get; set; }
    }

    public static UsageEvent? Parse(ReadOnlyMemory<byte> line, FileState state)
    {
        var span = line.Span;
        if (span.IndexOf("\"token_count\""u8) < 0 && span.IndexOf("\"turn_context\""u8) < 0) return null;

        Line? decoded;
        try { decoded = JsonSerializer.Deserialize<Line>(span); }
        catch (JsonException) { return null; }
        if (decoded?.Payload is not { } payload) return null;

        if (decoded.Type == "turn_context")
        {
            if (!string.IsNullOrEmpty(payload.Model)) state.Model = payload.Model;
            return null;
        }
        if (decoded.Type != "event_msg" || payload.Type != "token_count"
            || payload.Info?.TotalTokenUsage is not { } total
            || Timestamp.Parse(decoded.Timestamp) is not { } timestamp)
            return null;

        Totals delta;
        if (state.LastTotal is { } last && total.IsAtLeast(last))
            delta = new Totals(total.Input - last.Input, total.Cached - last.Cached,
                               total.CacheWrite - last.CacheWrite, total.Output - last.Output);
        else if (state.LastTotal is not null)
            // Zähler zurückgesetzt (z. B. Kontext komprimiert): nur den letzten Turn zählen.
            delta = payload.Info.LastTokenUsage ?? total;
        else
            delta = total;
        state.LastTotal = total;

        // OpenAI zählt Cache-Reads als Teil des Inputs; hier getrennt ausweisen.
        var counts = new TokenCounts(
            Input: Math.Max(delta.Input - delta.Cached - delta.CacheWrite, 0),
            Output: delta.Output,
            CacheWrite5m: delta.CacheWrite,
            CacheWrite1h: 0,
            CacheRead: delta.Cached);
        if (counts.IsZero) return null;
        return new UsageEvent(timestamp, state.Model ?? "codex", counts, null);
    }
}

public static class Timestamp
{
    public static DateTimeOffset? Parse(string? text) =>
        DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date) ? date : null;
}
