using System.Globalization;

namespace TokenStats.Model;

/// <summary>Deutsche Anzeigeformate: „82 %“, „12,40 $“, „Mi 09:00“.</summary>
public static class Format
{
    public static readonly CultureInfo Culture = CultureInfo.GetCultureInfo("de-DE");

    /// <summary>Abweichung von der Pace-Marke, ab der sie als Fläche und Text erscheint.</summary>
    public const double PaceTolerance = 0.03;

    static int Round(double value) => (int)Math.Round(value, MidpointRounding.AwayFromZero);

    public static string Percent(double fraction) => $"{Round(fraction * 100)} %";

    public static string Dollars(double cents) => $"{(cents / 100).ToString("#,##0.00", Culture)} $";

    public static string Money(double amount) => Dollars(amount * 100);

    /// <summary>„38,4 M“, „812 k“, „950“</summary>
    public static string Tokens(long count) => count switch
    {
        >= 1_000_000_000 => $"{Number(count / 1e9, 1)} Mrd.",
        >= 1_000_000 => $"{Number(count / 1e6, 1)} M",
        >= 1_000 => $"{Number(count / 1e3, 0)} k",
        _ => count.ToString(Culture),
    };

    public static string Number(double value, int digits) =>
        value.ToString(digits == 0 ? "#,##0" : "#,##0." + new string('0', digits), Culture);

    public static string Number(double value) => value.ToString("#,##0.##", Culture);

    /// <summary>Uhrzeit, bei späteren Tagen Wochentag + Uhrzeit – kein Countdown (SPEC §3.4).</summary>
    public static string Reset(DateTimeOffset date, DateTimeOffset now, TimeZoneInfo? zone = null)
    {
        zone ??= TimeZoneInfo.Local;
        var local = TimeZoneInfo.ConvertTime(date, zone).DateTime;
        var today = TimeZoneInfo.ConvertTime(now, zone).Date;
        var time = local.ToString("HH:mm", Culture);
        var days = (local.Date - today).Days;
        if (days == 0) return time;
        if (days == 1) return $"morgen {time}";
        if (days > 0 && days < 7) return $"{local.ToString("ddd", Culture)} {time}";
        return $"{local.ToString("d. MMM", Culture)} {time}";
    }

    public static string Reset(DateTimeOffset date) => Reset(date, DateTimeOffset.Now);

    /// <summary>„vor 1 Min.“</summary>
    public static string Ago(DateTimeOffset date, DateTimeOffset now)
    {
        var seconds = Math.Max(0, (now - date).TotalSeconds);
        if (seconds < 60) return "gerade eben";
        var minutes = (int)(seconds / 60);
        if (minutes < 60) return $"vor {minutes} Min.";
        var hours = minutes / 60;
        if (hours < 24) return $"vor {hours} Std.";
        return $"vor {hours / 24} T.";
    }

    /// <summary>
    /// Abstand zwischen Verbrauch und Pace-Marke als Zeit: „1 Tag vorgegriffen“, „4 Tage ungenutzt“,
    /// „im Takt“ (SPEC §3.4). Zeit statt Prozentpunkten, weil sich darunter niemand etwas vorstellen kann.
    /// </summary>
    public static string Pace(double percent, double elapsed, double windowLength)
    {
        var delta = percent - elapsed;
        if (Math.Abs(delta) < PaceTolerance) return "im Takt";
        var span = Duration(Math.Abs(delta) * windowLength);
        return delta > 0 ? $"{span} vorgegriffen" : $"{span} ungenutzt";
    }

    /// <summary>„40 Min.“, „5 Std.“, „1 Tag“, „4 Tage“ – bewusst grob, es geht um die Größenordnung.</summary>
    public static string Duration(double seconds)
    {
        var minutes = seconds / 60;
        if (minutes < 90) return $"{Math.Max(1, Round(minutes))} Min.";
        var hours = minutes / 60;
        if (hours < 24) return $"{Round(hours)} Std.";
        var days = Round(hours / 24);
        return days == 1 ? "1 Tag" : $"{days} Tage";
    }
}
