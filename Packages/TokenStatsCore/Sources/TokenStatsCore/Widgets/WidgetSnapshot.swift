import Foundation

/// App Group, über die die App den Widgets ihren Stand gibt; der Container liegt unter
/// `~/Library/Group Containers/<Kennung>/`. Die Kennung trägt die Team-ID der Signatur
/// (`APP_GROUP` in project.yml) und steht in der Info.plist von App und Erweiterung: macOS
/// lässt nur Apps desselben Teams an den Container, und `group.`-Kennungen verlangen ein
/// Provisioning-Profil. Ad hoc signierte Builds haben kein Team – dann bleibt die Datei
/// ungeschrieben und die Widgets zeigen „Token Stats öffnen“.
public enum AppGroup {
    public static let identifier: String = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "TokenStatsAppGroup") as? String,
           !value.hasPrefix("."), !value.hasPrefix("$") {
            return value
        }
        return "2GA7DQ3P3Z.de.mahype.TokenStats"
    }()

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

/// Alles, was die Widgets zeigen, fertig gerechnet: Limits je Anbieter und der Verbrauch je
/// Zeitraum. Die App schreibt die Datei nach jeder Änderung, die Erweiterung liest sie nur –
/// sie fragt keine Endpunkte ab, liest keine Zugangsdaten und öffnet kein `usage.sqlite`.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let fileName = "widgets.json"

    public struct Provider: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var snapshot: ProviderSnapshot?
        public var isRateLimited: Bool
        /// Fehler oder Hinweis der App, z. B. „Anmeldung abgelaufen“.
        public var message: String?

        public init(id: String, name: String, snapshot: ProviderSnapshot?, isRateLimited: Bool = false, message: String? = nil) {
            self.id = id
            self.name = name
            self.snapshot = snapshot
            self.isRateLimited = isRateLimited
            self.message = message
        }
    }

    public struct Usage: Codable, Equatable, Sendable {
        public var provider: String
        public var period: UsagePeriod
        public var summary: UsageSummary

        public init(provider: String, period: UsagePeriod, summary: UsageSummary) {
            self.provider = provider
            self.period = period
            self.summary = summary
        }
    }

    public var version: Int
    public var writtenAt: Date
    /// Einstellung „API-Vergleichswert in Geld anzeigen“ – aus heißt: nur Tokens.
    public var showMoney: Bool
    /// Installierte Anbieter, alphabetisch wie die Tabs.
    public var providers: [Provider]
    public var usage: [Usage]

    public init(writtenAt: Date = .now, showMoney: Bool, providers: [Provider], usage: [Usage]) {
        version = Self.currentVersion
        self.writtenAt = writtenAt
        self.showMoney = showMoney
        self.providers = providers
        self.usage = usage
    }

    // MARK: Abfragen

    public func provider(_ id: String) -> Provider? {
        providers.first { $0.id == id }
    }

    /// Das knappste Limit über alle Anbieter.
    public var tightest: (provider: Provider, window: LimitWindow)? {
        providers.compactMap { provider -> (Provider, LimitWindow)? in
            provider.snapshot?.tightestWindow.map { (provider, $0) }
        }.max { $0.1.percent < $1.1.percent }
    }

    /// Verbrauch eines Anbieters oder – bei `nil` – aller Anbieter zusammen.
    public func summary(provider: String?, period: UsagePeriod) -> UsageSummary? {
        let matching = usage.filter { $0.period == period && (provider == nil || $0.provider == provider) }
        guard !matching.isEmpty else { return nil }
        return UsageSummary.merged(matching.map(\.summary))
    }

    // MARK: Datei

    public static var fileURL: URL? {
        AppGroup.containerURL?.appending(path: fileName)
    }

    /// `nil`, wenn die App noch nie geschrieben hat oder das Format nicht passt.
    public static func load(from url: URL? = fileURL) -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.version == currentVersion else { return nil }
        return snapshot
    }

    public func write(to url: URL? = fileURL) throws {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

/// `tokenstats://`-Links, mit denen ein Widget die App öffnet.
public enum WidgetLink {
    public static let scheme = "tokenstats"

    public enum Page: String, Sendable {
        case limits, usage
    }

    public struct Target: Equatable, Sendable {
        public var page: Page
        public var provider: String?
        public var period: UsagePeriod?

        public init(page: Page, provider: String? = nil, period: UsagePeriod? = nil) {
            self.page = page
            self.provider = provider
            self.period = period
        }
    }

    public static func url(_ target: Target) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = target.page.rawValue
        var items: [URLQueryItem] = []
        if let provider = target.provider { items.append(URLQueryItem(name: "provider", value: provider)) }
        if let period = target.period { items.append(URLQueryItem(name: "period", value: period.rawValue)) }
        components.queryItems = items.isEmpty ? nil : items
        return components.url!
    }

    public static func parse(_ url: URL) -> Target? {
        guard url.scheme == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let page = components.host.flatMap(Page.init(rawValue:)) else { return nil }
        let query = components.queryItems ?? []
        return Target(
            page: page,
            provider: query.first { $0.name == "provider" }?.value,
            period: query.first { $0.name == "period" }?.value.flatMap(UsagePeriod.init(rawValue:))
        )
    }
}
