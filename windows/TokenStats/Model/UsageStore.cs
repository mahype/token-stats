using System.Text.Json;
using System.Windows.Threading;
using TokenStats.Providers;

namespace TokenStats.Model;

/// <summary>
/// Hält den letzten Stand je Anbieter, fragt im Takt ab und respektiert Rate-Limits.
/// Läuft auf dem UI-Thread; <see cref="Changed"/> meldet jede Änderung.
/// </summary>
public sealed class UsageStore
{
    public sealed class ProviderState
    {
        public ProviderSnapshot? Snapshot { get; set; }
        public string? Error { get; set; }
        /// <summary>Hinweis ohne Fehlercharakter, z. B. „Stand der letzten »agy«-Sitzung“.</summary>
        public string? Note { get; set; }
        /// <summary>Letzte Anfrage, die tatsächlich an den Endpunkt ging – Basis für den Takt.</summary>
        public DateTimeOffset? LastAttempt { get; set; }
        /// <summary>Bis hierhin keine Abfrage – aus Retry-After nach HTTP 429.</summary>
        public DateTimeOffset? RetryAt { get; set; }

        public bool IsRateLimited => RetryAt is { } retryAt && retryAt > DateTimeOffset.UtcNow;
    }

    public sealed record Pick(string ProviderId, string ProviderName, LimitWindow Window);

    /// <summary>Abstand zwischen zwei manuellen Aktualisierungen.</summary>
    public static readonly TimeSpan ManualFloor = TimeSpan.FromSeconds(60);

    public IReadOnlyList<IUsageProvider> Providers { get; }
    public Dictionary<string, ProviderState> States { get; private set; }
    public HashSet<string> Loading { get; } = [];

    public event Action? Changed;

    readonly AppSettings settings;
    readonly string? cachePath;
    DispatcherTimer? timer;

    public UsageStore(IReadOnlyList<IUsageProvider> providers, AppSettings settings, string? cachePath)
    {
        Providers = providers;
        this.settings = settings;
        this.cachePath = cachePath;
        States = LoadCache(cachePath);
    }

    public ProviderState State(string id) => States.TryGetValue(id, out var state) ? state : new ProviderState();

    public IEnumerable<IUsageProvider> InstalledProviders => Providers.Where(p => p.IsInstalled());

    /// <summary>Alphabetisch nach Namen, damit die Tabs nicht springen (SPEC §3.2).</summary>
    public List<IUsageProvider> SortedProviders =>
        InstalledProviders.OrderBy(p => p.DisplayName, StringComparer.Create(Format.Culture, ignoreCase: true)).ToList();

    /// <summary>Wert für Tray-Symbol und Tooltip.</summary>
    public Pick? Displayed => (settings.FixedWindow is { } key ? PickFor(key) : null) ?? Tightest;

    public Pick? Tightest => InstalledProviders
        .Select(p => State(p.Id).Snapshot?.TightestWindow is { } window ? new Pick(p.Id, p.DisplayName, window) : null)
        .OfType<Pick>()
        .MaxBy(pick => pick.Window.Percent);

    public Pick? PickFor(string key)
    {
        var parts = key.Split('/', 2);
        if (parts.Length != 2) return null;
        var provider = Providers.FirstOrDefault(p => p.Id == parts[0]);
        var window = provider is null ? null : State(provider.Id).Snapshot?.Windows.FirstOrDefault(w => w.Id == parts[1]);
        return window is null ? null : new Pick(provider!.Id, provider.DisplayName, window);
    }

    public DateTimeOffset? LastUpdate => States.Values.Select(s => s.Snapshot?.FetchedAt).Max();

    // Abruf

    public void Start()
    {
        Refresh(manual: false);
        // Der Timer prüft nur, ob etwas fällig ist; der eigentliche Takt ist RefreshInterval.
        timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(30) };
        timer.Tick += (_, _) => Refresh(manual: false);
        timer.Start();
    }

    public void Refresh(bool manual)
    {
        var now = DateTimeOffset.UtcNow;
        RollOverResets(now);
        foreach (var provider in InstalledProviders.Where(p => !Loading.Contains(p.Id)))
        {
            var state = State(provider.Id);
            if (state.IsRateLimited) continue;
            var spacing = manual ? ManualFloor : TimeSpan.FromSeconds(settings.RefreshInterval);
            if (state.LastAttempt is { } last && now - last < spacing) continue;
            _ = FetchAsync(provider);
        }
    }

    async Task FetchAsync(IUsageProvider provider)
    {
        var state = State(provider.Id);
        States[provider.Id] = state;
        Loading.Add(provider.Id);
        var previousAttempt = state.LastAttempt;
        state.LastAttempt = DateTimeOffset.UtcNow;
        Changed?.Invoke();
        try
        {
            state.Snapshot = await provider.FetchAsync();
            state.Error = null;
            state.Note = null;
            state.RetryAt = null;
        }
        catch (ProviderException error)
        {
            // Letzte Werte bleiben stehen, nie eine leere Anzeige.
            if (error.Kind == ProviderErrorKind.WaitingForToken)
            {
                state.Note = error.Message;
                state.Error = null;
            }
            else
            {
                state.Error = error.Message;
                state.Note = null;
            }
            // Ohne Anfrage kein Grund zu warten: Beim nächsten Timer-Tick werden die
            // Zugangsdaten neu gelesen, damit ein von der CLI erneuertes Token sofort greift.
            if (error.IsLocal) state.LastAttempt = previousAttempt;
            if (error.Kind == ProviderErrorKind.RateLimited)
                state.RetryAt = DateTimeOffset.UtcNow + (error.RetryAfter ?? TimeSpan.FromSeconds(settings.RefreshInterval));
        }
        catch (Exception error)
        {
            state.Error = error.Message;
        }
        Loading.Remove(provider.Id);
        SaveCache();
        Changed?.Invoke();
    }

    /// <summary>
    /// Ein Fenster, dessen Reset vorbei ist, steht ohne neue Abfrage auf 0 %. Wichtig für
    /// Anbieter, die nur selten abgefragt werden können (Antigravity), aber auch bei Rate-Limit.
    /// </summary>
    void RollOverResets(DateTimeOffset now)
    {
        var changed = false;
        foreach (var state in States.Values)
            foreach (var window in state.Snapshot?.Windows ?? [])
                changed |= window.RollOver(now);
        if (changed) Changed?.Invoke();
    }

    /// <summary>Nur für Screenshots: fester Stand, ohne Abruf und ohne den Cache zu überschreiben.</summary>
    public void ShowDemo(Dictionary<string, ProviderSnapshot> snapshots)
    {
        States = snapshots.ToDictionary(pair => pair.Key, pair => new ProviderState { Snapshot = pair.Value });
        Changed?.Invoke();
    }

    // Cache
    // Nur Prozentwerte und Reset-Zeiten – keine Zugangsdaten. Überlebt Neustarts,
    // damit ein Neustart der App keine zusätzliche Abfrage auslöst.

    static Dictionary<string, ProviderState> LoadCache(string? path)
    {
        if (path is null) return [];
        try { return JsonSerializer.Deserialize<Dictionary<string, ProviderState>>(File.ReadAllText(path)) ?? []; }
        catch (Exception error) when (error is IOException or JsonException or UnauthorizedAccessException) { return []; }
    }

    void SaveCache()
    {
        if (cachePath is null) return;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(cachePath)!);
            var temporary = cachePath + ".tmp";
            File.WriteAllText(temporary, JsonSerializer.Serialize(States));
            File.Move(temporary, cachePath, overwrite: true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }
}
