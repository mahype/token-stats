using System.Text;

namespace TokenStats.Tests;

// Zeilenformen wie in ~/.claude/projects und ~/.codex/sessions (Stand 09/2026).

public class ClaudeLogParserTests
{
    internal const string Line = """{"type":"assistant","timestamp":"2026-09-27T20:17:08.072Z","requestId":"req_1","message":{"id":"msg_1","model":"claude-opus-5-5","content":[],"usage":{"input_tokens":2,"cache_creation_input_tokens":24297,"cache_read_input_tokens":24920,"output_tokens":110,"cache_creation":{"ephemeral_1h_input_tokens":24297,"ephemeral_5m_input_tokens":0}}}}""";

    static ReadOnlyMemory<byte> Utf8(string text) => Encoding.UTF8.GetBytes(text);

    [Fact]
    public void ParsesUsageWithCacheSplit()
    {
        var usageEvent = ClaudeLogParser.Parse(Utf8(Line));
        Assert.NotNull(usageEvent);
        Assert.Equal("claude-opus-5-5", usageEvent.Model);
        Assert.Equal("msg_1:req_1", usageEvent.DedupKey);
        Assert.Equal(new TokenCounts(2, 110, 0, 24297, 24920), usageEvent.Counts);
    }

    [Fact]
    public void OlderLinesWithoutSplitCountAs5m()
    {
        const string line = """{"type":"assistant","timestamp":"2026-01-01T10:00:00Z","message":{"model":"claude-sonnet-4-5","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":100}}}""";
        var usageEvent = ClaudeLogParser.Parse(Utf8(line));
        Assert.Equal(100, usageEvent?.Counts.CacheWrite5m);
        Assert.Null(usageEvent?.DedupKey);
    }

    [Fact]
    public void IgnoresOtherLines()
    {
        Assert.Null(ClaudeLogParser.Parse(Utf8("""{"type":"user","message":{"content":"usage"}}""")));
        Assert.Null(ClaudeLogParser.Parse(Utf8(Line.Replace("claude-opus-5-5", "<synthetic>"))));
    }
}

public class CodexLogParserTests
{
    internal static ReadOnlyMemory<byte> TokenCount(long input, long cached, long output, long lastInput = 0, long lastCached = 0, long lastOutput = 0) =>
        Encoding.UTF8.GetBytes(
            """{"timestamp":"2026-09-27T11:12:06.319Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":"""
            + $$"""{"input_tokens":{{input}},"cached_input_tokens":{{cached}},"output_tokens":{{output}}},"""
            + $$"""  "last_token_usage":{"input_tokens":{{lastInput}},"cached_input_tokens":{{lastCached}},"output_tokens":{{lastOutput}}"""
            + "}}}}");

    [Fact]
    public void CountsDeltasOfCumulativeTotals()
    {
        var state = new CodexLogParser.FileState();
        Assert.Null(CodexLogParser.Parse(Encoding.UTF8.GetBytes("""{"type":"turn_context","payload":{"model":"gpt-5.6-sol"}}"""), state));
        Assert.Equal("gpt-5.6-sol", state.Model);

        var first = CodexLogParser.Parse(TokenCount(1000, 800, 50), state);
        Assert.Equal(new TokenCounts(Input: 200, Output: 50, CacheRead: 800), first?.Counts);
        Assert.Equal("gpt-5.6-sol", first?.Model);

        // Wiederholtes Ereignis mit gleichen Summen zählt nicht doppelt.
        Assert.Null(CodexLogParser.Parse(TokenCount(1000, 800, 50), state));

        var second = CodexLogParser.Parse(TokenCount(1500, 1200, 80), state);
        Assert.Equal(new TokenCounts(Input: 100, Output: 30, CacheRead: 400), second?.Counts);
    }

    [Fact]
    public void ResetFallsBackToLastTurn()
    {
        var state = new CodexLogParser.FileState();
        CodexLogParser.Parse(TokenCount(5000, 4000, 100), state);
        var usageEvent = CodexLogParser.Parse(TokenCount(300, 200, 10, 300, 200, 10), state);
        Assert.Equal(new TokenCounts(Input: 100, Output: 10, CacheRead: 200), usageEvent?.Counts);
    }
}

public class PricingTests
{
    internal static readonly PriceTable Table = new(null, new Dictionary<string, PriceTable.Price>
    {
        ["claude-opus-5-5"] = new(4e-6, 20e-6, 0.2e-6, 5e-6, 8e-6),
        ["gpt-5.6"] = new(4e-6, 20e-6, 0.4e-6, 5e-6, 4e-6),
    });

    [Fact]
    public void ValueUsesEveryTokenKind()
    {
        var counts = new TokenCounts(1_000_000, 1_000_000, 1_000_000, 1_000_000, 1_000_000);
        var value = Table.ValueOf(counts, "claude-opus-5-5");
        Assert.NotNull(value);
        Assert.Equal(4 + 20 + 5 + 8 + 0.2, value.Value, 9);
    }

    [Fact]
    public void LookupFallbacks()
    {
        Assert.NotNull(Table.PriceFor("claude-opus-5-5-20260901"));   // Datums-Suffix
        Assert.NotNull(Table.PriceFor("gpt-5.6-sol"));                // Präfix
        Assert.Null(Table.PriceFor("unbekannt"));
    }

    [Fact]
    public void BundledTableHasCurrentModels()
    {
        var bundled = PriceTable.Bundled;
        Assert.NotNull(bundled.AsOf);
        Assert.NotNull(bundled.PriceFor("claude-opus-5-5"));
        Assert.NotNull(bundled.PriceFor("claude-fable-5-1"));
    }

    [Fact]
    public void DisplayNames()
    {
        Assert.Equal("Opus 5.5", ModelName.Display("claude-opus-5-5"));
        Assert.Equal("Haiku 4.5", ModelName.Display("claude-haiku-4-5-20251001"));
        Assert.Equal("Fable 5", ModelName.Display("claude-fable-5"));
        Assert.Equal("GPT-5.6 Sol", ModelName.Display("gpt-5.6-sol"));
    }

    [Fact]
    public void TokenFormat()
    {
        Assert.Equal("38,4 M", Format.Tokens(38_400_000));
        Assert.Equal("812 k", Format.Tokens(812_345));
        Assert.Equal("950", Format.Tokens(950));
    }
}

public class PeriodTests
{
    [Fact]
    public void BillingMonthStartsAtLastStichtag()
    {
        Assert.Equal(new DateOnly(2026, 9, 15), UsagePeriod.Billing.Range(new DateOnly(2026, 9, 28), 15).From);
        Assert.Equal(new DateOnly(2026, 8, 15), UsagePeriod.Billing.Range(new DateOnly(2026, 9, 10), 15).From);
    }

    [Fact]
    public void BillingDayClampsToShortMonths() =>
        Assert.Equal(new DateOnly(2026, 2, 28), UsagePeriod.Billing.Range(new DateOnly(2026, 3, 5), 31).From);

    [Fact]
    public void SummaryFillsEmptyDays()
    {
        var (from, through) = UsagePeriod.Week.Range(new DateOnly(2026, 9, 28), 1);
        var rows = new[] { new UsageLedger.Row("2026-09-28", "claude-opus-5-5", new TokenCounts(Input: 10, Output: 5)) };
        var summary = UsageSummary.Build(rows, from, through, PricingTests.Table);
        Assert.Equal(7, summary.Days.Count);
        Assert.Equal(15, summary.Days[^1].Tokens);
        Assert.Equal(15, summary.Total.Total);
        Assert.False(summary.HasUnpriced);
    }
}

/// <summary>Ledger gegen ein temporäres Home mit echten Dateien – Windows-spezifisch: Pfade, geteilter Lesezugriff.</summary>
public sealed class LedgerTests : IDisposable
{
    readonly string home = Directory.CreateTempSubdirectory("tokenstats-").FullName;

    public void Dispose()
    {
        Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();
        Directory.Delete(home, recursive: true);
    }

    static string Claude(string id, long output) =>
        ClaudeLogParserTests.Line.Replace("msg_1", id).Replace("\"output_tokens\":110", $"\"output_tokens\":{output}");

    [Fact]
    public void ScansIncrementallyAndCountsOutputGrowthOnce()
    {
        var project = Directory.CreateDirectory(Path.Combine(home, ".claude", "projects", "C--repo")).FullName;
        var log = Path.Combine(project, "session.jsonl");
        // Claude Code schreibt weiter, während gelesen wird.
        using (var writer = new FileStream(log, FileMode.Create, FileAccess.Write, FileShare.ReadWrite))
        {
            writer.Write(Encoding.UTF8.GetBytes(Claude("msg_a", 50) + "\n" + Claude("msg_a", 110) + "\n"));
            writer.Flush();
            using var ledger = new UsageLedger(Path.Combine(home, "usage.sqlite"), home);
            Assert.True(ledger.Scan());

            // Fortsetzung derselben Antwort mit mehr Output, dazu eine unvollständige Zeile.
            writer.Write(Encoding.UTF8.GetBytes(Claude("msg_a", 150) + "\n" + Claude("msg_b", 7)[..40]));
            writer.Flush();
            Assert.True(ledger.Scan());

            var day = UsageSummary.Key(DateOnly.FromDateTime(DateTimeOffset.Parse("2026-09-27T20:17:08.072Z").LocalDateTime));
            var row = Assert.Single(ledger.Rows("claude", day, day));
            Assert.Equal(150, row.Counts.Output);
            Assert.Equal(24920, row.Counts.CacheRead);   // Input und Cache nur einmal
            Assert.False(ledger.Scan());
        }
    }
}
