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

    /// „64 % der Zeit · 18 Pkt. über Plan“
    static func pace(percent: Double, elapsed: Double) -> String {
        let delta = Int(((percent - elapsed) * 100).rounded())
        let time = "\(Int((elapsed * 100).rounded())) % der Zeit"
        switch delta {
        case 3...: return "\(time) · \(delta) Pkt. über Plan"
        case ...(-3): return "\(time) · \(-delta) Pkt. unter Plan"
        default: return "\(time) · im Plan"
        }
    }
}
