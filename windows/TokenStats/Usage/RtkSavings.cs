using System.Diagnostics;
using System.IO;
using System.Text.Json;

namespace TokenStats.Usage;

/// <summary>Ein Tag aus <c>rtk gain --format json --daily</c>: was rtk an Befehlsausgaben gefiltert hat.</summary>
public sealed record RtkDay(string Day, long Commands, long InputTokens, long SavedTokens);

/// <summary>Ersparnis durch rtk in einem Zeitraum – über alle Clients, rtk kennt den auslösenden Agent nicht.</summary>
public sealed record RtkSummary(long Commands = 0, long InputTokens = 0, long SavedTokens = 0)
{
    /// <summary>Anteil der gesparten an den ungefilterten Tokens; <c>null</c>, wenn nichts gefiltert wurde.</summary>
    public double? SavedFraction => InputTokens > 0 ? (double)SavedTokens / InputTokens : null;
}

/// <summary>
/// Liest die Tageswerte, die <c>rtk gain</c> selbst ausgibt. Bewusst nicht rtks <c>history.db</c>:
/// Das Schema ist undokumentiert, und die Rohsummen dort enthalten Einträge, die <c>rtk gain</c>
/// nicht mitzählt – der Block soll mit <c>rtk gain</c> übereinstimmen.
/// </summary>
public static class RtkSavings
{
    public static readonly string[] Arguments = ["gain", "--format", "json", "--daily"];
    static readonly TimeSpan Timeout = TimeSpan.FromSeconds(10);

    /// <summary><c>null</c> bei kaputter JSON oder fehlendem <c>daily</c>; Tage ohne vollständige Zahlen fallen weg.</summary>
    public static List<RtkDay>? Parse(string json)
    {
        JsonDocument document;
        try { document = JsonDocument.Parse(json); }
        catch (JsonException) { return null; }
        using (document)
        {
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("daily", out var daily)
                || daily.ValueKind != JsonValueKind.Array)
                return null;
            var days = new List<RtkDay>();
            foreach (var entry in daily.EnumerateArray())
            {
                if (entry.ValueKind != JsonValueKind.Object
                    || !entry.TryGetProperty("date", out var date) || date.ValueKind != JsonValueKind.String
                    || Int(entry, "commands") is not { } commands
                    || Int(entry, "input_tokens") is not { } input
                    || Int(entry, "saved_tokens") is not { } saved)
                    continue;
                days.Add(new RtkDay(date.GetString()!, commands, input, saved));
            }
            return days;
        }
    }

    static long? Int(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out var number)
            ? number : null;

    /// <summary>Summe der Tage <paramref name="from"/>…<paramref name="through"/> (einschließlich), Schlüssel wie <c>UsageSummary.Key</c>.</summary>
    public static RtkSummary Summary(IEnumerable<RtkDay> days, string from, string through)
    {
        var inRange = days.Where(day => string.CompareOrdinal(day.Day, from) >= 0 && string.CompareOrdinal(day.Day, through) <= 0).ToList();
        return new RtkSummary(inRange.Sum(day => day.Commands), inRange.Sum(day => day.InputTokens), inRange.Sum(day => day.SavedTokens));
    }

    /// <summary>Je Zeitraum die Summe, mit denselben Grenzen wie die Seite „Verbrauch“.</summary>
    public static Dictionary<UsagePeriod, RtkSummary> Summaries(IReadOnlyList<RtkDay> days, DateOnly today, int billingDay) =>
        UsagePeriods.All.ToDictionary(period => period, period =>
        {
            var (from, through) = period.Range(today, billingDay);
            return Summary(days, UsageSummary.Key(from), UsageSummary.Key(through));
        });

    /// <summary>
    /// Sucht <c>rtk.exe</c> in <c>%USERPROFILE%\.cargo\bin</c>, <c>%USERPROFILE%\.local\bin</c>, dann in jedem
    /// Eintrag von <c>PATH</c>.
    /// </summary>
    public static string? FindExecutable()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var folders = new List<string> { Path.Combine(home, ".cargo", "bin"), Path.Combine(home, ".local", "bin") };
        folders.AddRange((Environment.GetEnvironmentVariable("PATH") ?? "")
            .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));
        foreach (var folder in folders)
        {
            try
            {
                var candidate = Path.Combine(folder, "rtk.exe");
                if (File.Exists(candidate)) return candidate;
            }
            catch (ArgumentException) { }   // ungültiger PATH-Eintrag
        }
        return null;
    }

    /// <summary><c>null</c>, wenn rtk fehlt, fehlschlägt, hängt oder etwas Unlesbares ausgibt – dann fehlt der Block.</summary>
    public static List<RtkDay>? Load()
    {
        if (FindExecutable() is not { } path) return null;
        try
        {
            var start = new ProcessStartInfo(path)
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            foreach (var argument in Arguments) start.ArgumentList.Add(argument);
            using var process = Process.Start(start);
            if (process is null) return null;
            process.ErrorDataReceived += (_, _) => { };
            process.BeginErrorReadLine();
            var output = process.StandardOutput.ReadToEndAsync();
            if (!process.WaitForExit(Timeout))
            {
                process.Kill(entireProcessTree: true);
                return null;
            }
            return process.ExitCode == 0 ? Parse(output.GetAwaiter().GetResult()) : null;
        }
        catch (Exception error) when (error is System.ComponentModel.Win32Exception or InvalidOperationException or IOException)
        {
            Debug.WriteLine($"Token Stats: rtk nicht lesbar: {error.Message}");
            return null;
        }
    }
}
