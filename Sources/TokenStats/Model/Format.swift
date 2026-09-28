import Foundation

/// Deutsche Anzeigeformate: „82 %“, „12,40 $“, „Mi 09:00“.
enum Format {
    static let locale = Locale(identifier: "de_DE")

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded())) %"
    }

    static func dollars(cents: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "\(formatter.string(from: NSNumber(value: cents / 100)) ?? "?") $"
    }

    static func money(_ amount: Double) -> String {
        dollars(cents: amount * 100)
    }

    /// „38,4 M“, „812 k“, „950“
    static func tokens(_ count: Int) -> String {
        let value = Double(count)
        switch value {
        case 1_000_000_000...: return "\(number(value / 1_000_000_000, digits: 1)) Mrd."
        case 1_000_000...: return "\(number(value / 1_000_000, digits: 1)) M"
        case 1_000...: return "\(number(value / 1_000, digits: 0)) k"
        default: return "\(count)"
        }
    }

    static func number(_ value: Double, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func number(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Uhrzeit, bei späteren Tagen Wochentag + Uhrzeit – kein Countdown (SPEC §3.4).
    static func reset(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
        if calendar.isDate(date, inSameDayAs: now) { return time }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        if days == 1 { return "morgen \(time)" }
        if days < 7 { return "\(date.formatted(.dateTime.weekday(.abbreviated).locale(locale))) \(time)" }
        return "\(date.formatted(.dateTime.day().month(.abbreviated).locale(locale))) \(time)"
    }

    /// „vor 1 Min.“
    static func ago(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "gerade eben" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "vor \(minutes) Min." }
        let hours = minutes / 60
        if hours < 24 { return "vor \(hours) Std." }
        return "vor \(hours / 24) T."
    }

    /// Abstand zwischen Verbrauch und Pace-Marke als Zeit: „1 Tag vorgegriffen“, „4 Tage ungenutzt“,
    /// „im Takt“ (SPEC §3.4). Zeit statt Prozentpunkten, weil sich darunter niemand etwas vorstellen kann.
    static func pace(percent: Double, elapsed: Double, windowLength: TimeInterval) -> String {
        let delta = percent - elapsed
        guard abs(delta) >= paceTolerance else { return "im Takt" }
        let span = duration(abs(delta) * windowLength)
        return delta > 0 ? "\(span) vorgegriffen" : "\(span) ungenutzt"
    }

    /// Abweichung von der Pace-Marke, ab der sie als Fläche und Text erscheint.
    static let paceTolerance = 0.03

    /// „40 Min.“, „5 Std.“, „1 Tag“, „4 Tage“ – bewusst grob, es geht um die Größenordnung.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = seconds / 60
        if minutes < 90 { return "\(max(1, Int(minutes.rounded()))) Min." }
        let hours = minutes / 60
        if hours < 24 { return "\(Int(hours.rounded())) Std." }
        let days = Int((hours / 24).rounded())
        return days == 1 ? "1 Tag" : "\(days) Tage"
    }
}
