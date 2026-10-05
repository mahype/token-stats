using System.Text.Json.Serialization;

namespace TokenStats.Model;

/// <summary>Stand eines Anbieters zu einem Abrufzeitpunkt (SPEC §7).</summary>
public sealed class ProviderSnapshot
{
    public AccountInfo? Account { get; set; }
    public List<LimitWindow> Windows { get; set; } = [];
    public List<ExtraValue> Extras { get; set; } = [];
    public DateTimeOffset FetchedAt { get; set; }

    /// <summary>Das knappste Limit dieses Anbieters.</summary>
    [JsonIgnore]
    public LimitWindow? TightestWindow => Windows.MaxBy(w => w.Percent);
}

public sealed record AccountInfo(string? Name, string? Plan);

public sealed class LimitWindow
{
    public string Id { get; set; } = "";
    /// <summary>"Session", "Woche", "Opus"</summary>
    public string Name { get; set; } = "";
    /// <summary>"5 h", "7 d, alle Modelle"</summary>
    public string? ScopeNote { get; set; }
    /// <summary>0…1, kann über 1 liegen.</summary>
    public double Percent { get; set; }
    public DateTimeOffset? ResetsAt { get; set; }
    /// <summary>Fensterlänge in Sekunden.</summary>
    public double? WindowLength { get; set; }

    [JsonIgnore]
    public Severity Severity => SeverityOf.Percent(Percent);

    /// <summary>
    /// Nach dem Reset: 0 % und – bei bekannter Fensterlänge – der nächste Reset.
    /// Liefert true, wenn sich etwas geändert hat.
    /// </summary>
    public bool RollOver(DateTimeOffset now)
    {
        if (ResetsAt is not { } resetsAt || resetsAt > now) return false;
        Percent = 0;
        if (WindowLength is { } length && length > 0)
        {
            var periods = Math.Floor((now - resetsAt).TotalSeconds / length) + 1;
            ResetsAt = resetsAt.AddSeconds(periods * length);
        }
        else
        {
            ResetsAt = null;
        }
        return true;
    }

    /// <summary>Anteil der verstrichenen Fensterzeit, für die Pace-Marke.</summary>
    public double? ElapsedFraction(DateTimeOffset now)
    {
        if (ResetsAt is not { } resetsAt || WindowLength is not { } length || length <= 0) return null;
        var remaining = (resetsAt - now).TotalSeconds;
        return Math.Clamp((length - remaining) / length, 0, 1);
    }
}

/// <summary>Beträge, Guthaben und Kleinwerte unter den Meter-Zeilen.</summary>
public sealed record ExtraValue(string Id, string Text);

public enum Severity { Ok, Warn, Crit }

public static class SeverityOf
{
    /// <summary>Omarchy-Konvention: gelb ab 80 %, rot ab 100 %.</summary>
    public static Severity Percent(double percent) => percent switch
    {
        >= 1 => Severity.Crit,
        >= 0.8 => Severity.Warn,
        _ => Severity.Ok,
    };
}
