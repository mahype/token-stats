using System.Diagnostics;
using System.Text.Json;
using Microsoft.Data.Sqlite;

namespace TokenStats.Usage;

/// <summary>
/// Liest die Session-Logs inkrementell ein und hält Tokens pro Tag und Modell
/// in einer kleinen SQLite-Datei (SPEC §7). Beim Öffnen wird nichts neu geparst.
/// Nicht threadsicher – der Aufrufer serialisiert die Zugriffe.
/// </summary>
public sealed class UsageLedger : IDisposable
{
    public sealed record Row(string Day, string Model, TokenCounts Counts);   // Day: "2026-09-28", lokale Zeit

    /// <summary>Schemaversion; eine Änderung verwirft das Aggregat und liest neu ein.</summary>
    const int SchemaVersion = 2;

    readonly SqliteConnection db;
    readonly string home;
    SqliteTransaction? transaction;

    public UsageLedger(string path, string? home = null)
    {
        this.home = home ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        db = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path, Pooling = false }.ToString());
        db.Open();
        Exec("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;");
        if (Convert.ToInt32(Scalar("PRAGMA user_version")) != SchemaVersion)
        {
            Exec($"""
                DROP TABLE IF EXISTS files; DROP TABLE IF EXISTS seen; DROP TABLE IF EXISTS daily;
                CREATE TABLE files (key TEXT PRIMARY KEY, offset INTEGER NOT NULL, state TEXT);
                CREATE TABLE seen (id TEXT PRIMARY KEY, output INTEGER NOT NULL) WITHOUT ROWID;
                CREATE TABLE daily (
                    provider TEXT NOT NULL, day TEXT NOT NULL, model TEXT NOT NULL,
                    input INTEGER NOT NULL, output INTEGER NOT NULL,
                    cache_write_5m INTEGER NOT NULL, cache_write_1h INTEGER NOT NULL, cache_read INTEGER NOT NULL,
                    PRIMARY KEY (provider, day, model)
                );
                PRAGMA user_version = {SchemaVersion};
                """);
        }
    }

    public static string DefaultPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TokenStats", "usage.sqlite");

    public void Dispose() => db.Dispose();

    // Einlesen

    /// <summary>Liest alle neuen Zeilen seit dem letzten Lauf. Liefert true, wenn sich etwas geändert hat.</summary>
    public bool Scan()
    {
        var changed = false;
        foreach (var (key, path) in ClaudeFiles())
            changed |= Ingest(key, path, "claude");
        foreach (var (key, path) in CodexFiles())
            changed |= Ingest(key, path, "codex");
        return changed;
    }

    IEnumerable<(string, string)> ClaudeFiles()
    {
        var root = Path.Combine(home, ".claude", "projects");
        return JsonlFiles(root).Select(path => ("claude:" + path[root.Length..].Replace('\\', '/'), path));
    }

    /// <summary>
    /// Schlüssel ist der Dateiname: Codex verschiebt fertige Sessions nach
    /// <c>archived_sessions</c>, der Lesestand soll mitwandern.
    /// </summary>
    IEnumerable<(string, string)> CodexFiles() =>
        new[] { "sessions", "archived_sessions" }.SelectMany(folder =>
            JsonlFiles(Path.Combine(home, ".codex", folder)).Select(path => ("codex:" + Path.GetFileName(path), path)));

    static IEnumerable<string> JsonlFiles(string root)
    {
        if (!Directory.Exists(root)) return [];
        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = true,
            AttributesToSkip = FileAttributes.Hidden | FileAttributes.System,
        };
        // Wie `skipsHiddenFiles` auf macOS: auch Punkt-Dateien und -Ordner auslassen.
        return Directory.EnumerateFiles(root, "*.jsonl", options)
            .Where(path => !path[root.Length..].Split(Path.DirectorySeparatorChar).Any(part => part.StartsWith('.')));
    }

    bool Ingest(string key, string path, string provider)
    {
        long size;
        try { size = new FileInfo(path).Length; }
        catch (IOException) { return false; }

        long offset = 0;
        var codexState = new CodexLogParser.FileState();
        using (var select = Command("SELECT offset, state FROM files WHERE key = $key", ("$key", key)))
        using (var reader = select.ExecuteReader())
        {
            if (reader.Read())
            {
                offset = reader.GetInt64(0);
                if (!reader.IsDBNull(1))
                    codexState = JsonSerializer.Deserialize<CodexLogParser.FileState>(reader.GetString(1)) ?? codexState;
            }
        }
        if (size < offset)
        {
            // Datei neu geschrieben: von vorn. Claude ist über `seen` abgesichert.
            offset = 0;
            codexState = new CodexLogParser.FileState();
        }
        if (size <= offset) return false;

        var buckets = new Dictionary<(string Day, string Model), TokenCounts>();
        var claudeEvents = new Dictionary<string, UsageEvent>();
        var claudeOrder = new List<string>();
        try
        {
            // Claude Code und Codex schreiben weiter in die Dateien: nur lesen, nichts sperren.
            using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete, 1 << 16))
            {
                stream.Seek(offset, SeekOrigin.Begin);
                var buffer = new byte[4 << 20];
                var filled = 0;
                while (true)
                {
                    if (filled == buffer.Length) Array.Resize(ref buffer, buffer.Length * 2);
                    var read = stream.Read(buffer, filled, buffer.Length - filled);
                    if (read == 0) break;
                    filled += read;
                    var start = 0;
                    int newline;
                    while ((newline = Array.IndexOf(buffer, (byte)'\n', start, filled - start)) >= 0)
                    {
                        var line = new ReadOnlyMemory<byte>(buffer, start, newline - start);
                        start = newline + 1;
                        offset += line.Length + 1;
                        if (provider == "claude")
                        {
                            if (ClaudeLogParser.Parse(line) is not { } claudeEvent) continue;
                            if (claudeEvent.DedupKey is { } dedup)
                            {
                                // Innerhalb der Datei die letzte Zeile je Antwort behalten.
                                if (!claudeEvents.ContainsKey(dedup)) claudeOrder.Add(dedup);
                                claudeEvents[dedup] = claudeEvent;
                            }
                            else
                            {
                                Add(claudeEvent, buckets);
                            }
                        }
                        else if (CodexLogParser.Parse(line, codexState) is { } codexEvent)
                        {
                            Add(codexEvent, buckets);
                        }
                    }
                    Buffer.BlockCopy(buffer, start, buffer, 0, filled - start);
                    filled -= start;
                }
                // Eine unvollständige letzte Zeile bleibt für den nächsten Lauf liegen.
            }

            transaction = db.BeginTransaction();
            try
            {
                Commit(provider, key, offset, codexState, buckets, claudeEvents, claudeOrder);
                transaction.Commit();
            }
            finally
            {
                transaction.Dispose();
                transaction = null;
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or SqliteException)
        {
            Debug.WriteLine($"Token Stats: {Path.GetFileName(path)} nicht lesbar: {error.Message}");
            return false;
        }
        return buckets.Count > 0;
    }

    void Commit(string provider, string key, long offset, CodexLogParser.FileState codexState,
                Dictionary<(string Day, string Model), TokenCounts> buckets,
                Dictionary<string, UsageEvent> claudeEvents, List<string> claudeOrder)
    {
        // Die Output-Zahl einer Antwort wächst über ihre Log-Zeilen. Stand sie beim
        // letzten Lauf erst teilweise im Log, wird jetzt nur der Zuwachs nachgetragen.
        using (var seen = Command("SELECT output FROM seen WHERE id = $id", ("$id", "")))
        using (var insert = Command("INSERT INTO seen (id, output) VALUES ($id, $output)", ("$id", ""), ("$output", 0L)))
        using (var update = Command("UPDATE seen SET output = $output WHERE id = $id", ("$id", ""), ("$output", 0L)))
        {
            foreach (var dedup in claudeOrder)
            {
                var claudeEvent = claudeEvents[dedup];
                seen.Parameters["$id"].Value = dedup;
                if (seen.ExecuteScalar() is long known)
                {
                    if (claudeEvent.Counts.Output <= known) continue;
                    update.Parameters["$id"].Value = dedup;
                    update.Parameters["$output"].Value = claudeEvent.Counts.Output;
                    update.ExecuteNonQuery();
                    claudeEvent = claudeEvent with { Counts = new TokenCounts(Output: claudeEvent.Counts.Output - known) };
                }
                else
                {
                    insert.Parameters["$id"].Value = dedup;
                    insert.Parameters["$output"].Value = claudeEvent.Counts.Output;
                    insert.ExecuteNonQuery();
                }
                Add(claudeEvent, buckets);
            }
        }
        foreach (var ((day, model), counts) in buckets)
        {
            using var upsert = Command("""
                INSERT INTO daily (provider, day, model, input, output, cache_write_5m, cache_write_1h, cache_read)
                VALUES ($provider, $day, $model, $input, $output, $w5, $w1, $read)
                ON CONFLICT (provider, day, model) DO UPDATE SET
                    input = input + excluded.input, output = output + excluded.output,
                    cache_write_5m = cache_write_5m + excluded.cache_write_5m,
                    cache_write_1h = cache_write_1h + excluded.cache_write_1h,
                    cache_read = cache_read + excluded.cache_read
                """, ("$provider", provider), ("$day", day), ("$model", model),
                ("$input", counts.Input), ("$output", counts.Output),
                ("$w5", counts.CacheWrite5m), ("$w1", counts.CacheWrite1h), ("$read", counts.CacheRead));
            upsert.ExecuteNonQuery();
        }
        var state = provider == "codex" ? JsonSerializer.Serialize(codexState) : null;
        using (var file = Command("INSERT OR REPLACE INTO files (key, offset, state) VALUES ($key, $offset, $state)",
                   ("$key", key), ("$offset", offset), ("$state", (object?)state ?? DBNull.Value)))
            file.ExecuteNonQuery();
    }

    static void Add(UsageEvent usageEvent, Dictionary<(string, string), TokenCounts> buckets)
    {
        var key = (DayKey(usageEvent.Timestamp), usageEvent.Model);
        buckets[key] = buckets.GetValueOrDefault(key) + usageEvent.Counts;
    }

    /// <summary>Tag in lokaler Zeit.</summary>
    static string DayKey(DateTimeOffset date) => UsageSummary.Key(DateOnly.FromDateTime(date.LocalDateTime));

    // Abfrage

    public List<Row> Rows(string provider, string from, string through)
    {
        using var command = Command("""
            SELECT day, model, input, output, cache_write_5m, cache_write_1h, cache_read
            FROM daily WHERE provider = $provider AND day >= $from AND day <= $through
            """, ("$provider", provider), ("$from", from), ("$through", through));
        using var reader = command.ExecuteReader();
        var rows = new List<Row>();
        while (reader.Read())
            rows.Add(new Row(reader.GetString(0), reader.GetString(1), new TokenCounts(
                reader.GetInt64(2), reader.GetInt64(3), reader.GetInt64(4), reader.GetInt64(5), reader.GetInt64(6))));
        return rows;
    }

    // SQLite

    SqliteCommand Command(string sql, params (string Name, object Value)[] parameters)
    {
        var command = db.CreateCommand();
        command.CommandText = sql;
        command.Transaction = transaction;
        foreach (var (name, value) in parameters) command.Parameters.AddWithValue(name, value);
        return command;
    }

    void Exec(string sql)
    {
        using var command = Command(sql);
        command.ExecuteNonQuery();
    }

    object? Scalar(string sql)
    {
        using var command = Command(sql);
        return command.ExecuteScalar();
    }
}
