using System.Windows.Threading;
using TokenStats.Model;

namespace TokenStats.Usage;

public enum UsagePeriod { Today, Week, Month, Billing }

public static class UsagePeriods
{
    public static readonly UsagePeriod[] All = [UsagePeriod.Today, UsagePeriod.Week, UsagePeriod.Month, UsagePeriod.Billing];

    public static string Label(this UsagePeriod period) => period switch
    {
        UsagePeriod.Today => "Heute",
        UsagePeriod.Week => "7 Tage",
        UsagePeriod.Month => "30 Tage",
        _ => "Abrechnungsmonat",
    };

    /// <summary>Erster und letzter Tag (einschließlich), lokale Zeit.</summary>
    public static (DateOnly From, DateOnly Through) Range(this UsagePeriod period, DateOnly today, int billingDay)
    {
        switch (period)
        {
            case UsagePeriod.Today: return (today, today);
            case UsagePeriod.Week: return (today.AddDays(-6), today);
            case UsagePeriod.Month: return (today.AddDays(-29), today);
            default:
                // Letzter Stichtag ≤ heute; in kurzen Monaten der Monatsletzte.
                DateOnly Stichtag(int monthsBack)
                {
                    var month = today.AddMonths(-monthsBack);
                    return new DateOnly(month.Year, month.Month, Math.Min(billingDay, DateTime.DaysInMonth(month.Year, month.Month)));
                }
                var start = Stichtag(0) <= today ? Stichtag(0) : Stichtag(1);
                return (start, today);
        }
    }
}

/// <summary>Zusammenfassung für die Seite „Verbrauch“.</summary>
public sealed class UsageSummary
{
    /// <param name="Value"><c>null</c> = kein Preis bekannt.</param>
    public sealed record ModelLine(string Model, TokenCounts Counts, double? Value);

    public sealed record DayTotal(DateOnly Day, long Tokens);

    public TokenCounts Total { get; private set; }
    public double Value { get; private set; }
    public bool HasUnpriced { get; private set; }
    public List<ModelLine> Models { get; private set; } = [];
    public List<DayTotal> Days { get; } = [];

    public static UsageSummary Build(IEnumerable<UsageLedger.Row> rows, DateOnly from, DateOnly through, PriceTable prices)
    {
        var summary = new UsageSummary();
        var perModel = new Dictionary<string, TokenCounts>();
        var perDay = new Dictionary<string, long>();
        foreach (var row in rows)
        {
            perModel[row.Model] = perModel.GetValueOrDefault(row.Model) + row.Counts;
            perDay[row.Day] = perDay.GetValueOrDefault(row.Day) + row.Counts.Total;
            summary.Total += row.Counts;
        }
        summary.Models = perModel
            .Select(pair => new ModelLine(pair.Key, pair.Value, prices.ValueOf(pair.Value, pair.Key)))
            .OrderByDescending(line => line.Value ?? -1)
            .ThenByDescending(line => line.Counts.Total)
            .ToList();
        summary.Value = summary.Models.Sum(line => line.Value ?? 0);
        summary.HasUnpriced = summary.Models.Any(line => line.Value is null);

        for (var day = from; day <= through; day = day.AddDays(1))
            summary.Days.Add(new DayTotal(day, perDay.GetValueOrDefault(Key(day))));
        return summary;
    }

    public static string Key(DateOnly day) => day.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture);
}

/// <summary>Hält den Ledger aktuell und stellt Zusammenfassungen für die UI bereit.</summary>
public sealed class ConsumptionStore
{
    public static readonly string[] ProviderIds = ["claude", "codex"];

    /// <summary>Lokale Dateien, kein Netz – ein kurzer Takt ist unkritisch.</summary>
    static readonly TimeSpan ScanInterval = TimeSpan.FromSeconds(60);

    public PriceTable Prices { get; } = PriceTable.Bundled;
    public bool IsScanning { get; private set; }
    public string? Failure { get; private set; }

    public event Action? Changed;

    Dictionary<string, Dictionary<UsagePeriod, UsageSummary>> summaries = [];
    readonly UsageLedger? ledger;
    readonly AppSettings settings;
    DispatcherTimer? timer;

    public ConsumptionStore(AppSettings settings, string? ledgerPath)
    {
        this.settings = settings;
        if (ledgerPath is null) return;
        try
        {
            ledger = new UsageLedger(ledgerPath);
        }
        catch (Exception error)
        {
            Failure = $"Verbrauchsdatenbank nicht verfügbar: {error.Message}";
        }
    }

    public void Start()
    {
        Refresh();
        timer = new DispatcherTimer { Interval = ScanInterval };
        timer.Tick += (_, _) => Refresh();
        timer.Start();
    }

    public UsageSummary? Summary(string provider, UsagePeriod period) =>
        summaries.TryGetValue(provider, out var byPeriod) && byPeriod.TryGetValue(period, out var summary) ? summary : null;

    /// <summary>Nur für Screenshots: feste Zusammenfassungen, ohne die Logs zu lesen.</summary>
    public void ShowDemo(Dictionary<string, Dictionary<UsagePeriod, UsageSummary>> demo)
    {
        timer?.Stop();
        summaries = demo;
        Changed?.Invoke();
    }

    public void Refresh()
    {
        if (ledger is null || IsScanning) return;
        IsScanning = true;
        var billingDay = settings.BillingDay;
        Task.Run(() =>
        {
            ledger.Scan();
            var today = DateOnly.FromDateTime(DateTime.Now);
            var result = new Dictionary<string, Dictionary<UsagePeriod, UsageSummary>>();
            foreach (var provider in ProviderIds)
            {
                result[provider] = [];
                foreach (var period in UsagePeriods.All)
                {
                    var (from, through) = period.Range(today, billingDay);
                    var rows = ledger.Rows(provider, UsageSummary.Key(from), UsageSummary.Key(through));
                    result[provider][period] = UsageSummary.Build(rows, from, through, Prices);
                }
            }
            return result;
        }).ContinueWith(task =>
        {
            if (task.IsCompletedSuccessfully) summaries = task.Result;
            else Failure ??= task.Exception?.GetBaseException().Message;
            IsScanning = false;
            Changed?.Invoke();
        }, TaskScheduler.FromCurrentSynchronizationContext());
    }
}

/// <summary>Monatspreis des Abos für den Vergleich, soweit bekannt.</summary>
public static class SubscriptionPrice
{
    public static int? Dollars(string provider, string? plan) => (provider, plan?.ToLowerInvariant()) switch
    {
        ("claude", "max 20×") => 200,
        ("claude", "max 5×") => 100,
        ("claude", "pro") => 20,
        ("codex", "pro") => 200,
        ("codex", "plus") => 20,
        _ => null,
    };
}
