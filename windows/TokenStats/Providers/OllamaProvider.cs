using System.Buffers.Binary;
using System.Text;
using System.Text.Json.Nodes;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;
using TokenStats.Model;

namespace TokenStats.Providers;

/// <summary>
/// Ollama Cloud: signierte Anfrage mit dem Schlüssel <c>%USERPROFILE%\.ollama\id_ed25519</c>
/// → <c>ollama.com/api/balance</c> (Limits/Guthaben), <c>/api/usage</c> (Statistik) und <c>/api/me</c> (Plan).
///
/// Die App benötigt keinen API-Key. <c>ollama signin</c> verknüpft den lokalen Schlüssel mit dem Konto,
/// und jede Anfrage trägt eine Signatur über Methode, Pfad und Zeitstempel – genau wie in der
/// Ollama-CLI (<c>auth/auth.go</c>). Der Schlüssel wird nur gelesen; raus geht die Signatur.
/// Lokale Modelle haben kein Kontingent und tauchen hier nicht auf.
/// </summary>
public sealed class OllamaProvider : IUsageProvider
{
    public string Id => "ollama";
    public string DisplayName => "Ollama";

    const string Host = "https://ollama.com";
    const string Hint = "»ollama signin« im Terminal ausführen.";

    static string KeyFile =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".ollama", "id_ed25519");

    public bool IsInstalled() => File.Exists(KeyFile);

    public async Task<ProviderSnapshot> FetchAsync()
    {
        SigningKey? key;
        try { key = ParsePrivateKey(File.ReadAllText(KeyFile)); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { key = null; }
        if (key is null) throw ProviderException.NotLoggedIn(Hint);

        var snapshot = ParseBalance(await RequestAsync("GET", "/api/balance", key), DateTimeOffset.UtcNow);
        // Statistik und Plan sind Beiwerk: Fehler dort dürfen die Limits nicht ausblenden.
        try { snapshot.Extras.AddRange(ParseUsage(await RequestAsync("GET", "/api/usage", key), DateTimeOffset.UtcNow).Extras); }
        catch (ProviderException) { }
        try { snapshot.Account = ParseAccount(await RequestAsync("POST", "/api/me", key)); }
        catch (ProviderException) { }
        return snapshot;
    }

    static Task<byte[]> RequestAsync(string method, string path, SigningKey key)
    {
        var timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString();
        var url = new Uri($"{Host}{path}?ts={timestamp}");
        var headers = new Dictionary<string, string> { ["Authorization"] = $"Bearer {key.Authorization(method, path, timestamp)}" };
        return method == "POST"
            ? Http.PostJsonAsync(url, new JsonObject(), headers, Hint)
            : Http.GetJsonAsync(url, headers, Hint);
    }

    // Schlüssel

    public sealed class SigningKey(byte[] publicBlob, Ed25519PrivateKeyParameters privateKey)
    {
        /// <summary>Öffentlicher Schlüssel im SSH-Wire-Format – der Teil nach „ssh-ed25519 “ in <c>.pub</c>.</summary>
        public byte[] PublicBlob { get; } = publicBlob;

        /// <summary><c>&lt;Base64(öffentlicher Blob)&gt;:&lt;Base64(Signatur über "METHOD,path?ts=…")&gt;</c></summary>
        public string Authorization(string method, string path, string timestamp)
        {
            var message = Encoding.UTF8.GetBytes($"{method},{path}?ts={timestamp}");
            var signer = new Ed25519Signer();
            signer.Init(true, privateKey);
            signer.BlockUpdate(message, 0, message.Length);
            return $"{Convert.ToBase64String(PublicBlob)}:{Convert.ToBase64String(signer.GenerateSignature())}";
        }
    }

    /// <summary>OpenSSH-Format <c>openssh-key-v1</c>, nur unverschlüsselt (so legt Ollama den Schlüssel an).</summary>
    public static SigningKey? ParsePrivateKey(string pem)
    {
        var body = string.Concat(pem.Split('\n', '\r').Where(line => !line.StartsWith("-----")).Select(line => line.Trim()));
        byte[] raw;
        try { raw = Convert.FromBase64String(body); }
        catch (FormatException) { return null; }
        var magic = Encoding.ASCII.GetBytes("openssh-key-v1\0");
        if (!raw.AsSpan().StartsWith(magic)) return null;

        var reader = new WireReader(raw[magic.Length..]);
        if (reader.String() is not { } cipher || Encoding.ASCII.GetString(cipher) != "none") return null;
        if (reader.String() is null || reader.String() is null) return null;   // KDF, KDF-Optionen
        if (reader.UInt32() != 1) return null;
        if (reader.String() is not { } publicBlob || reader.String() is not { } privateBlock) return null;

        var block = new WireReader(privateBlock);
        if (block.UInt32() is not { } check || block.UInt32() != check) return null;
        if (block.String() is not { } type || Encoding.ASCII.GetString(type) != "ssh-ed25519") return null;
        if (block.String() is null) return null;                                 // öffentlicher Schlüssel, 32 Byte
        if (block.String() is not { Length: 64 } secret) return null;
        return new SigningKey(publicBlob, new Ed25519PrivateKeyParameters(secret, 0));
    }

    sealed class WireReader(byte[] data)
    {
        int offset;

        public uint? UInt32()
        {
            if (offset + 4 > data.Length) return null;
            var value = BinaryPrimitives.ReadUInt32BigEndian(data.AsSpan(offset, 4));
            offset += 4;
            return value;
        }

        public byte[]? String()
        {
            if (UInt32() is not { } length || offset + length > data.Length) return null;
            var value = data.AsSpan(offset, (int)length).ToArray();
            offset += (int)length;
            return value;
        }
    }

    // Antwort

    /// <summary>Seit Oktober 2026 liefert /api/balance die Limits, /api/usage nur noch Statistik.</summary>
    public static ProviderSnapshot ParseBalance(byte[] data, DateTimeOffset now)
    {
        var response = JsonRead.ParseObject(data);
        var included = response.Obj("included");
        if (included is null) throw ProviderException.BadResponse();

        var windows = new List<LimitWindow>();
        foreach (var (id, name, note, length) in new[]
        {
            ("session", "Session", "5 h", TimeSpan.FromHours(5)),
            ("weekly", "Woche", "7 d", TimeSpan.FromDays(7)),
        })
        {
            var limit = included.Obj(id);
            if (limit.Num("remaining_percent") is not { } remaining || !double.IsFinite(remaining) || remaining is < 0 or > 100)
                continue;
            windows.Add(new LimitWindow
            {
                Id = id, Name = name, ScopeNote = note, Percent = (100 - remaining) / 100,
                ResetsAt = JsonRead.Date(limit.Str("resets_at")), WindowLength = length.TotalSeconds,
            });
        }

        var extras = new List<ExtraValue>();
        if (included.Num("balance_usd") is { } balance && double.IsFinite(balance))
        {
            extras.Add(new ExtraValue("included-balance", $"Abo-Guthaben {Format.Money(balance)}"));
            if (included.Num("allowance_usd") is { } allowance && double.IsFinite(allowance) && allowance > 0)
                windows.Add(new LimitWindow
                {
                    Id = "monthly", Name = "Monat", ScopeNote = "Abo-Monat", Percent = Math.Max(0, 1 - balance / allowance),
                    ResetsAt = JsonRead.Date(included.Obj("period").Str("until")),
                });
        }
        // Ein Nullbetrag ist ein gültiger Stand, auch bei einem Plan ohne Kontingent.
        if (windows.Count == 0 && extras.Count == 0) throw ProviderException.BadResponse();
        if (response.Obj("purchased").Num("balance_usd") is { } purchased && double.IsFinite(purchased) && purchased >= 0)
            extras.Add(new ExtraValue("purchased-balance", $"Zusatzguthaben {Format.Money(purchased)}"));

        return new ProviderSnapshot { Windows = windows, Extras = extras, FetchedAt = now };
    }

    static readonly (string Key, string Name, string Note)[] KnownWindows =
    [
        ("session", "Session", "5 h"), ("weekly", "Woche", "7 d"), ("monthly", "Monat", "Abo-Monat"),
    ];

    public static ProviderSnapshot ParseUsage(byte[] data, DateTimeOffset now)
    {
        var response = JsonRead.ParseObject(data);
        if (response.Obj("totals") is { } totals)
        {
            var period = response.Str("range") switch
            {
                "24h" => "24 h + aktuelle Stunde", "7d" => "7 Tage + heute", "30d" => "30 Tage + heute", _ => null,
            };
            if (period is null || totals.Num("request_count") is not { } requests || !double.IsFinite(requests) || requests < 0 || requests != Math.Truncate(requests))
                throw ProviderException.BadResponse();
            var usageExtras = new List<ExtraValue> { new("requests", $"{requests:0} Anfragen / {period}") };
            if (totals.Num("usage_usd") is { } usageCost && double.IsFinite(usageCost) && usageCost >= 0)
                usageExtras.Add(new ExtraValue("usage-cost", $"Verbrauch {Format.Money(usageCost)} / {period}"));
            foreach (var (id, name, field) in new[]
            {
                ("input", "Eingabe", "input_tokens"), ("cache", "Cache-Lesen", "cached_input_tokens"), ("output", "Ausgabe", "output_tokens"),
            })
                if (totals.Num(field) is { } count && double.IsFinite(count) && count >= 0 && count <= long.MaxValue && count == Math.Truncate(count))
                    usageExtras.Add(new ExtraValue($"tokens-{id}", $"{name} {Format.Tokens((long)count)} Tokens / {period}"));
            return new ProviderSnapshot { Extras = usageExtras, FetchedAt = now };
        }

        // Alte Antworten bleiben lesbar; fehlende Statistik ist niemals ein 0-%-Limit.
        var limits = response.Obj("limits");
        if (limits is null || limits.Count == 0) throw ProviderException.BadResponse();

        // Fenster ohne Reset-Zeit: Ollama sagt nur, wie viel verbraucht ist, nicht wann es endet.
        var windows = KnownWindows
            .Select(entry => limits.Obj(entry.Key).Num("usage") is { } usage
                ? new LimitWindow { Id = entry.Key, Name = entry.Name, ScopeNote = entry.Note, Percent = usage }
                : null)
            .OfType<LimitWindow>()
            .ToList();
        if (windows.Count == 0) throw ProviderException.BadResponse();

        // Anfragen je Modell aus dem längsten gemeldeten Fenster.
        var models = Enumerable.Reverse(KnownWindows)
            .Select(entry => limits.Obj(entry.Key).Arr("models"))
            .FirstOrDefault(list => list is { Count: > 0 }) ?? [];
        var extras = models
            .Select(model => (Name: model.Str("name"), Count: (int)(model.Num("request_count") ?? 0)))
            .Where(model => model.Name is not null)
            .OrderByDescending(model => model.Count)
            .Select(model => new ExtraValue($"requests-{model.Name}", $"{model.Name} · {model.Count} Anfragen"))
            .ToList();
        // Kosten über den Plan hinaus sind echte, abgerechnete Beträge – keine Vergleichswerte.
        if (double.TryParse(response.Obj("activity").Str("cost"), System.Globalization.NumberStyles.Float,
                            System.Globalization.CultureInfo.InvariantCulture, out var cost) && cost >= 0.005)
            extras.Add(new ExtraValue("billed", $"Abgerechnet {Format.Money(cost)} / 4 Wochen"));

        return new ProviderSnapshot { Windows = windows, Extras = extras, FetchedAt = now };
    }

    public static AccountInfo? ParseAccount(byte[] data)
    {
        var root = JsonRead.ParseObject(data);
        if (root is null) return null;
        var name = new[] { root.Str("Name"), root.Str("Email") }.FirstOrDefault(value => !string.IsNullOrEmpty(value));
        var plan = root.Str("Plan") is { Length: > 0 } raw ? char.ToUpperInvariant(raw[0]) + raw[1..] : null;
        return new AccountInfo(name, plan);
    }
}
