import Foundation

/// Ein Verbrauchsereignis aus einem Session-Log.
struct UsageEvent: Equatable, Sendable {
    var timestamp: Date
    var model: String
    var counts: TokenCounts
    /// Schlüssel für die globale Deduplizierung, `nil` = nicht deduplizieren.
    var dedupKey: String?
}

/// Claude Code: `~/.claude/projects/**/*.jsonl`, eine Zeile je Inhaltsblock.
/// Dieselbe Antwort steht mehrfach im Log (und in fortgesetzten Sessions erneut),
/// daher Deduplizierung über `message.id` + `requestId` wie bei ccusage.
enum ClaudeLogParser {
    /// Schneller Vorfilter, bevor eine Zeile dekodiert wird.
    static let markers = [Data(#""type":"assistant""#.utf8), Data(#""usage""#.utf8)]

    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                struct CacheCreation: Decodable {
                    var ephemeral_5m_input_tokens: Int?
                    var ephemeral_1h_input_tokens: Int?
                }
                var input_tokens: Int?
                var output_tokens: Int?
                var cache_creation_input_tokens: Int?
                var cache_read_input_tokens: Int?
                var cache_creation: CacheCreation?
            }
            var id: String?
            var model: String?
            var usage: Usage?
        }
        var type: String?
        var timestamp: String?
        var requestId: String?
        var message: Message?
    }

    static func parse(_ line: Data) -> UsageEvent? {
        guard markers.allSatisfy({ line.range(of: $0) != nil }),
              let decoded = try? JSONDecoder().decode(Line.self, from: line),
              decoded.type == "assistant",
              let message = decoded.message, let usage = message.usage,
              let model = message.model, model != "<synthetic>",
              let timestamp = decoded.timestamp.flatMap(Timestamp.parse)
        else { return nil }

        // Cache-Write nach Lebensdauer getrennt, weil 1 h teurer ist als 5 min.
        let write = usage.cache_creation_input_tokens ?? 0
        let write1h = usage.cache_creation?.ephemeral_1h_input_tokens ?? 0
        let write5m = usage.cache_creation?.ephemeral_5m_input_tokens ?? max(write - write1h, 0)
        let counts = TokenCounts(
            input: usage.input_tokens ?? 0,
            output: usage.output_tokens ?? 0,
            cacheWrite5m: write5m,
            cacheWrite1h: write1h,
            cacheRead: usage.cache_read_input_tokens ?? 0
        )
        guard !counts.isZero else { return nil }

        let key: String? = if let id = message.id, let request = decoded.requestId { "\(id):\(request)" } else { nil }
        return UsageEvent(timestamp: timestamp, model: model, counts: counts, dedupKey: key)
    }
}

/// Codex: `~/.codex/sessions/**/rollout-*.jsonl` (später `archived_sessions/`).
/// `token_count`-Ereignisse tragen kumulierte Summen; gezählt wird die Differenz
/// zum vorherigen Stand derselben Datei – robust gegen wiederholte Ereignisse.
enum CodexLogParser {
    static let markers = [Data(#""token_count""#.utf8), Data(#""turn_context""#.utf8)]

    /// Zustand je Datei, wird mit dem Lese-Offset gespeichert.
    struct FileState: Codable, Equatable {
        var model: String?
        var lastTotal: Totals?
    }

    struct Totals: Codable, Equatable {
        var input_tokens: Int?
        var cached_input_tokens: Int?
        var cache_write_input_tokens: Int?
        var output_tokens: Int?

        var input: Int { input_tokens ?? 0 }
        var cached: Int { cached_input_tokens ?? 0 }
        var cacheWrite: Int { cache_write_input_tokens ?? 0 }
        var output: Int { output_tokens ?? 0 }

        func isAtLeast(_ other: Totals) -> Bool {
            input >= other.input && cached >= other.cached && cacheWrite >= other.cacheWrite && output >= other.output
        }
    }

    private struct Line: Decodable {
        struct Payload: Decodable {
            struct Info: Decodable {
                var total_token_usage: Totals?
                var last_token_usage: Totals?
            }
            var type: String?
            var model: String?
            var info: Info?
        }
        var type: String?
        var timestamp: String?
        var payload: Payload?
    }

    static func parse(_ line: Data, state: inout FileState) -> UsageEvent? {
        guard markers.contains(where: { line.range(of: $0) != nil }),
              let decoded = try? JSONDecoder().decode(Line.self, from: line),
              let payload = decoded.payload
        else { return nil }

        if decoded.type == "turn_context" {
            if let model = payload.model, !model.isEmpty { state.model = model }
            return nil
        }
        guard decoded.type == "event_msg", payload.type == "token_count",
              let total = payload.info?.total_token_usage,
              let timestamp = decoded.timestamp.flatMap(Timestamp.parse)
        else { return nil }

        let delta: Totals
        if let last = state.lastTotal, total.isAtLeast(last) {
            delta = Totals(
                input_tokens: total.input - last.input,
                cached_input_tokens: total.cached - last.cached,
                cache_write_input_tokens: total.cacheWrite - last.cacheWrite,
                output_tokens: total.output - last.output
            )
        } else if state.lastTotal != nil {
            // Zähler zurückgesetzt (z. B. Kontext komprimiert): nur den letzten Turn zählen.
            delta = payload.info?.last_token_usage ?? total
        } else {
            delta = total
        }
        state.lastTotal = total

        // OpenAI zählt Cache-Reads als Teil des Inputs; hier getrennt ausweisen.
        let counts = TokenCounts(
            input: max(delta.input - delta.cached - delta.cacheWrite, 0),
            output: delta.output,
            cacheWrite5m: delta.cacheWrite,
            cacheWrite1h: 0,
            cacheRead: delta.cached
        )
        guard !counts.isZero else { return nil }
        return UsageEvent(timestamp: timestamp, model: state.model ?? "codex", counts: counts, dedupKey: nil)
    }
}

enum Timestamp {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()
    private static let lock = NSLock()

    static func parse(_ string: String) -> Date? {
        lock.withLock { fractional.date(from: string) ?? plain.date(from: string) }
    }
}
