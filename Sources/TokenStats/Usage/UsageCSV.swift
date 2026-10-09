import Foundation

/// Verbrauch eines Zeitraums als CSV – Semikolon und Dezimalkomma, damit Numbers und
/// Excel mit deutscher Spracheinstellung die Datei ohne Importdialog verstehen.
/// Zwei Blöcke: je Modell (mit Summenzeile) und je Tag, durch eine Leerzeile getrennt.
/// Cache-Tokens stehen getrennt, der Geldbetrag heißt „API-Vergleichswert“ (CLAUDE.md).
enum UsageCSV {
    static let separator = ";"

    static func render(_ summary: UsageSummary, showMoney: Bool, calendar: Calendar = .current) -> String {
        var lines: [String] = []

        var header = ["Modell", "Modell-ID", "Input", "Output", "Cache-Schreiben", "Cache-Lesen", "Tokens"]
        if showMoney { header.append("API-Vergleichswert (USD)") }
        lines.append(row(header))

        for line in summary.models {
            var fields = [ModelName.display(line.model), line.model] + counts(line.counts)
            if showMoney { fields.append(line.value.map(money) ?? "") }
            lines.append(row(fields))
        }

        var total = ["Gesamt", ""] + counts(summary.total)
        if showMoney { total.append(money(summary.value)) }
        lines.append(row(total))

        lines.append("")
        lines.append(row(["Datum", "Tokens"]))
        for day in summary.days {
            lines.append(row([UsageSummary.key(day.day, calendar), String(day.tokens)]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func counts(_ counts: TokenCounts) -> [String] {
        [counts.input, counts.output, counts.cacheWrite, counts.cacheRead, counts.total].map(String.init)
    }

    /// „12,34“ – ohne Währungszeichen, das steht im Spaltenkopf.
    private static func money(_ amount: Double) -> String {
        Format.number(amount, digits: 2)
    }

    private static func row(_ fields: [String]) -> String {
        fields.map(quote).joined(separator: separator)
    }

    private static func quote(_ field: String) -> String {
        guard field.contains(separator) || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
