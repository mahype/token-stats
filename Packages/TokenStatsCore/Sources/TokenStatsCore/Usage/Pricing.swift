import Foundation

/// Tokenzahlen eines Ereignisses oder einer Summe, Cache getrennt (SPEC §3.5).
public struct TokenCounts: Codable, Equatable, Sendable {
    public var input: Int = 0          // ohne Cache
    public var output: Int = 0
    public var cacheWrite5m: Int = 0
    public var cacheWrite1h: Int = 0
    public var cacheRead: Int = 0

    public init(input: Int = 0, output: Int = 0, cacheWrite5m: Int = 0, cacheWrite1h: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.cacheRead = cacheRead
    }

    public var cacheWrite: Int { cacheWrite5m + cacheWrite1h }
    public var cache: Int { cacheWrite + cacheRead }
    public var total: Int { input + output + cache }
    public var isZero: Bool { total == 0 }

    public static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: lhs.input + rhs.input, output: lhs.output + rhs.output,
            cacheWrite5m: lhs.cacheWrite5m + rhs.cacheWrite5m, cacheWrite1h: lhs.cacheWrite1h + rhs.cacheWrite1h,
            cacheRead: lhs.cacheRead + rhs.cacheRead
        )
    }
}

/// Mitgelieferte Listenpreise mit Datumsstempel (`Scripts/update-pricing.sh`).
/// Der Betrag daraus ist ein API-Vergleichswert, keine Kosten.
public struct PriceTable: Sendable {
    public struct Price: Codable, Sendable {
        public var input: Double
        public var output: Double
        public var cacheRead: Double
        public var cacheWrite5m: Double
        public var cacheWrite1h: Double

        public init(input: Double, output: Double, cacheRead: Double, cacheWrite5m: Double, cacheWrite1h: Double) {
            self.input = input
            self.output = output
            self.cacheRead = cacheRead
            self.cacheWrite5m = cacheWrite5m
            self.cacheWrite1h = cacheWrite1h
        }
    }

    private struct File: Codable {
        var asOf: String
        var models: [String: Price]
    }

    public let asOf: Date?
    public let models: [String: Price]

    /// `pricing.json` aus dem Hauptbundle – in der Widget-Erweiterung leer, die bekommt
    /// fertige Beträge von der App.
    public static let bundled: PriceTable = {
        guard let url = Bundle.main.url(forResource: "pricing", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return PriceTable(asOf: nil, models: [:]) }
        return (try? PriceTable(json: data)) ?? PriceTable(asOf: nil, models: [:])
    }()

    public init(asOf: Date?, models: [String: Price]) {
        self.asOf = asOf
        self.models = models
    }

    public init(json: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: json)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        self.init(asOf: formatter.date(from: file.asOf), models: file.models)
    }

    /// Exakter Name, sonst ohne Datums-Suffix, sonst längster bekannter Präfix.
    public func price(for model: String) -> Price? {
        if let price = models[model] { return price }
        let undated = model.replacing(/-\d{8}$/, with: "")
        if let price = models[undated] { return price }
        let prefix = models.keys.filter { model.hasPrefix($0) }.max { $0.count < $1.count }
        return prefix.flatMap { models[$0] }
    }

    /// Dollar-Betrag, `nil` wenn das Modell nicht in der Tabelle steht.
    public func value(of counts: TokenCounts, model: String) -> Double? {
        guard let price = price(for: model) else { return nil }
        return Double(counts.input) * price.input
            + Double(counts.output) * price.output
            + Double(counts.cacheWrite5m) * price.cacheWrite5m
            + Double(counts.cacheWrite1h) * price.cacheWrite1h
            + Double(counts.cacheRead) * price.cacheRead
    }
}

/// "claude-opus-5-5" → "Opus 5.5", "gpt-5.6-sol" → "GPT-5.6 Sol"
public enum ModelName {
    public static func display(_ model: String) -> String {
        var name = model.replacing(/-\d{8}$/, with: "")
        if name.hasPrefix("claude-") {
            name.removeFirst("claude-".count)
            let parts = name.split(separator: "-")
            guard let family = parts.first else { return model }
            let version = parts.dropFirst().joined(separator: ".")
            return family.prefix(1).uppercased() + family.dropFirst() + (version.isEmpty ? "" : " \(version)")
        }
        if name.hasPrefix("gpt-") {
            let parts = name.split(separator: "-")
            let base = "GPT-" + (parts.count > 1 ? parts[1] : "")
            let suffix = parts.dropFirst(2).map { $0.prefix(1).uppercased() + $0.dropFirst() }
            return ([base] + suffix).joined(separator: " ")
        }
        return model
    }
}
