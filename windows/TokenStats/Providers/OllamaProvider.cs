using System.Buffers.Binary;
using System.Text;
using System.Text.Json.Nodes;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;
using TokenStats.Model;

namespace TokenStats.Providers;

/// <summary>
/// Ollama Cloud: signierte Anfrage mit dem Schlüssel <c>%USERPROFILE%\.ollama\id_ed25519</c>
/// → <c>ollama.com/api/usage</c> (Limits) und <c>ollama.com/api/me</c> (Plan).
///
/// Ollama kennt kein Token. <c>ollama signin</c> verknüpft den lokalen Schlüssel mit dem Konto,
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

        var snapshot = ParseUsage(await RequestAsync("GET", "/api/usage", key), DateTimeOffset.UtcNow);
        // Plan ist Beiwerk: Scheitert die zweite Abfrage, bleiben die Limits trotzdem stehen.
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

    static readonly (string Key, string Name, string Note)[] KnownWindows =
    [
        ("session", "Session", "5 h"), ("weekly", "Woche", "7 d"), ("monthly", "Monat", "Abo-Monat"),
    ];

    public static ProviderSnapshot ParseUsage(byte[] data, DateTimeOffset now)
    {
        var response = JsonRead.ParseObject(data);
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
