import Foundation

/// Liest die Session-Logs inkrementell ein und hält Tokens pro Tag und Modell
/// in einer kleinen SQLite-Datei (SPEC §7). Beim Öffnen wird nichts neu geparst.
actor UsageLedger {
    struct Row: Equatable, Sendable {
        var day: String         // "2026-09-28", lokale Zeit
        var model: String
        var counts: TokenCounts
    }

    private let db: SQLiteDB
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let calendar = Calendar.current

    /// Schemaversion; eine Änderung verwirft das Aggregat und liest neu ein.
    private static let schemaVersion = 2

    init(url: URL = UsageLedger.defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        db = try SQLiteDB(path: url.path)
        let version = try db.run("PRAGMA user_version").first?.first?.int ?? 0
        if version != Self.schemaVersion {
            try db.exec("""
                DROP TABLE IF EXISTS files; DROP TABLE IF EXISTS seen; DROP TABLE IF EXISTS daily;
                CREATE TABLE files (key TEXT PRIMARY KEY, offset INTEGER NOT NULL, state TEXT);
                CREATE TABLE seen (id TEXT PRIMARY KEY, output INTEGER NOT NULL) WITHOUT ROWID;
                CREATE TABLE daily (
                    provider TEXT NOT NULL, day TEXT NOT NULL, model TEXT NOT NULL,
                    input INTEGER NOT NULL, output INTEGER NOT NULL,
                    cache_write_5m INTEGER NOT NULL, cache_write_1h INTEGER NOT NULL, cache_read INTEGER NOT NULL,
                    PRIMARY KEY (provider, day, model)
                );
                PRAGMA user_version = \(Self.schemaVersion);
                """)
        }
    }

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "TokenStats/usage.sqlite")
    }

    // MARK: Einlesen

    /// Liest alle neuen Zeilen seit dem letzten Lauf. Liefert true, wenn sich etwas geändert hat.
    @discardableResult
    func scan() -> Bool {
        var changed = false
        for (key, url) in claudeFiles() {
            if ingest(key: key, url: url, provider: "claude") { changed = true }
        }
        for (key, url) in codexFiles() {
            if ingest(key: key, url: url, provider: "codex") { changed = true }
        }
        return changed
    }

    private func claudeFiles() -> [(String, URL)] {
        let root = home.appending(path: ".claude/projects")
        return jsonlFiles(under: root).map { ("claude:" + $0.path.dropFirst(root.path.count), $0) }
    }

    /// Schlüssel ist der Dateiname: Codex verschiebt fertige Sessions nach
    /// `archived_sessions`, der Lesestand soll mitwandern.
    private func codexFiles() -> [(String, URL)] {
        ["sessions", "archived_sessions"].flatMap { folder in
            jsonlFiles(under: home.appending(path: ".codex/\(folder)")).map { ("codex:" + $0.lastPathComponent, $0) }
        }
    }

    private func jsonlFiles(under root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
    }

    private func ingest(key: String, url: URL, provider: String) -> Bool {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int else { return false }
        let row = try? db.run("SELECT offset, state FROM files WHERE key = ?", [.text(key)]).first
        var offset = row?[0].int ?? 0
        var codexState = row?[1].text.flatMap { try? JSONDecoder().decode(CodexLogParser.FileState.self, from: Data($0.utf8)) }
            ?? CodexLogParser.FileState()
        if size < offset {
            // Datei neu geschrieben: von vorn. Claude ist über `seen` abgesichert.
            offset = 0
            codexState = CodexLogParser.FileState()
        }
        guard size > offset, let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        var buckets: [String: TokenCounts] = [:]   // "day\tmodel"
        var claudeKeys: [String: UsageEvent] = [:]
        var claudeOrder: [String] = []
        do {
            try handle.seek(toOffset: UInt64(offset))
            var pending = Data()
            while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
                pending.append(chunk)
                var lineStart = pending.startIndex
                while let newline = pending[lineStart...].firstIndex(of: 0x0A) {
                    let line = pending[lineStart..<newline]
                    lineStart = pending.index(after: newline)
                    offset += line.count + 1
                    if provider == "claude" {
                        guard let event = ClaudeLogParser.parse(line) else { continue }
                        if let dedup = event.dedupKey {
                            // Innerhalb der Datei die letzte Zeile je Antwort behalten.
                            if claudeKeys.updateValue(event, forKey: dedup) == nil { claudeOrder.append(dedup) }
                        } else {
                            add(event, to: &buckets)
                        }
                    } else if let event = CodexLogParser.parse(line, state: &codexState) {
                        add(event, to: &buckets)
                    }
                }
                pending = Data(pending[lineStart...])
            }
            // Eine unvollständige letzte Zeile bleibt für den nächsten Lauf liegen.

            try db.transaction {
                // Die Output-Zahl einer Antwort wächst über ihre Log-Zeilen. Stand sie beim
                // letzten Lauf erst teilweise im Log, wird jetzt nur der Zuwachs nachgetragen.
                for dedup in claudeOrder {
                    guard var event = claudeKeys[dedup] else { continue }
                    let known = try db.run("SELECT output FROM seen WHERE id = ?", [.text(dedup)]).first?.first?.int
                    if let known {
                        guard event.counts.output > known else { continue }
                        try db.run("UPDATE seen SET output = ? WHERE id = ?", [.int(event.counts.output), .text(dedup)])
                        event.counts = TokenCounts(output: event.counts.output - known)
                    } else {
                        try db.run("INSERT INTO seen (id, output) VALUES (?, ?)", [.text(dedup), .int(event.counts.output)])
                    }
                    add(event, to: &buckets)
                }
                for (bucket, counts) in buckets {
                    let parts = bucket.split(separator: "\t", maxSplits: 1).map(String.init)
                    try db.run("""
                        INSERT INTO daily (provider, day, model, input, output, cache_write_5m, cache_write_1h, cache_read)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT (provider, day, model) DO UPDATE SET
                            input = input + excluded.input, output = output + excluded.output,
                            cache_write_5m = cache_write_5m + excluded.cache_write_5m,
                            cache_write_1h = cache_write_1h + excluded.cache_write_1h,
                            cache_read = cache_read + excluded.cache_read
                        """, [.text(provider), .text(parts[0]), .text(parts[1]),
                              .int(counts.input), .int(counts.output),
                              .int(counts.cacheWrite5m), .int(counts.cacheWrite1h), .int(counts.cacheRead)])
                }
                let state = provider == "codex" ? (try? JSONEncoder().encode(codexState)).map { String(decoding: $0, as: UTF8.self) } : nil
                try db.run("INSERT OR REPLACE INTO files (key, offset, state) VALUES (?, ?, ?)",
                           [.text(key), .int(offset), state.map { .text($0) } ?? .null])
            }
        } catch {
            NSLog("Token Stats: \(url.lastPathComponent) nicht lesbar: \(error)")
            return false
        }
        return !buckets.isEmpty
    }

    private func add(_ event: UsageEvent, to buckets: inout [String: TokenCounts]) {
        let key = "\(dayKey(event.timestamp))\t\(event.model)"
        buckets[key] = buckets[key, default: TokenCounts()] + event.counts
    }

    private func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: Abfrage

    func rows(provider: String, from: String, through: String) -> [Row] {
        let result = (try? db.run("""
            SELECT day, model, input, output, cache_write_5m, cache_write_1h, cache_read
            FROM daily WHERE provider = ? AND day >= ? AND day <= ?
            """, [.text(provider), .text(from), .text(through)])) ?? []
        return result.map { row in
            Row(day: row[0].text ?? "", model: row[1].text ?? "", counts: TokenCounts(
                input: row[2].int, output: row[3].int,
                cacheWrite5m: row[4].int, cacheWrite1h: row[5].int, cacheRead: row[6].int
            ))
        }
    }
}
