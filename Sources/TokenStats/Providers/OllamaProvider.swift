import CryptoKit
import Foundation

/// Ollama Cloud: signierte Anfrage mit dem Schlüssel `~/.ollama/id_ed25519`
/// → `ollama.com/api/usage` (Limits) und `ollama.com/api/me` (Plan).
///
/// Ollama kennt kein Token. `ollama signin` verknüpft den lokalen Schlüssel mit dem Konto,
/// und jede Anfrage trägt eine Signatur über Methode, Pfad und Zeitstempel – genau wie
/// in der Ollama-CLI (`auth/auth.go`). Der Schlüssel wird nur gelesen; raus geht die
/// Signatur. Lokale Modelle haben kein Kontingent und tauchen hier nicht auf.
struct OllamaProvider: UsageProvider {
    let id = "ollama"
    let displayName = "Ollama"

    static let host = "https://ollama.com"
    static let hint = "»ollama signin« im Terminal ausführen."

    private var keyFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ollama/id_ed25519")
    }

    func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: keyFile.path)
    }

    func fetch() async throws -> ProviderSnapshot {
        guard let pem = try? String(contentsOf: keyFile, encoding: .utf8),
              let key = Self.parsePrivateKey(pem)
        else { throw ProviderError.notLoggedIn(hint: Self.hint) }

        var snapshot = try Self.parseUsage(try await request("GET", "/api/usage", key: key))
        // Plan ist Beiwerk: Scheitert die zweite Abfrage, bleiben die Limits trotzdem stehen.
        if let me = try? await request("POST", "/api/me", key: key) {
            snapshot.account = Self.parseAccount(me)
        }
        return snapshot
    }

    private func request(_ method: String, _ path: String, key: SigningKey) async throws -> Data {
        let timestamp = String(Int(Date.now.timeIntervalSince1970))
        let url = URL(string: "\(Self.host)\(path)?ts=\(timestamp)")!
        let headers = ["Authorization": "Bearer \(try key.authorization(method: method, path: path, timestamp: timestamp))"]
        return method == "POST"
            ? try await HTTP.postJSON(url, body: [:], headers: headers, expiredHint: Self.hint)
            : try await HTTP.getJSON(url, headers: headers, expiredHint: Self.hint)
    }

    // MARK: Schlüssel

    struct SigningKey {
        /// Öffentlicher Schlüssel im SSH-Wire-Format – der Teil nach „ssh-ed25519 “ in `.pub`.
        var publicBlob: Data
        var privateKey: Curve25519.Signing.PrivateKey

        /// `<Base64(öffentlicher Blob)>:<Base64(Signatur über "METHOD,path?ts=…")>`
        func authorization(method: String, path: String, timestamp: String) throws -> String {
            let signature = try privateKey.signature(for: Data("\(method),\(path)?ts=\(timestamp)".utf8))
            return "\(publicBlob.base64EncodedString()):\(signature.base64EncodedString())"
        }
    }

    /// OpenSSH-Format `openssh-key-v1`, nur unverschlüsselt (so legt Ollama den Schlüssel an).
    static func parsePrivateKey(_ pem: String) -> SigningKey? {
        let body = pem.split(whereSeparator: \.isNewline).filter { !$0.hasPrefix("-----") }.joined()
        let magic = Data("openssh-key-v1\0".utf8)
        guard let raw = Data(base64Encoded: body), raw.starts(with: magic) else { return nil }

        var reader = WireReader(data: Data(raw.dropFirst(magic.count)))
        guard reader.string().map({ String(decoding: $0, as: UTF8.self) }) == "none",  // Cipher
              reader.string() != nil, reader.string() != nil,                          // KDF, KDF-Optionen
              reader.uint32() == 1,
              let publicBlob = reader.string(),
              let privateBlock = reader.string()
        else { return nil }

        var block = WireReader(data: privateBlock)
        guard let check1 = block.uint32(), check1 == block.uint32(),
              block.string().map({ String(decoding: $0, as: UTF8.self) }) == "ssh-ed25519",
              block.string() != nil,                    // öffentlicher Schlüssel, 32 Byte
              let secret = block.string(), secret.count == 64,
              let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: secret.prefix(32))
        else { return nil }
        return SigningKey(publicBlob: publicBlob, privateKey: privateKey)
    }

    private struct WireReader {
        var data: Data
        var offset = 0

        mutating func uint32() -> UInt32? {
            guard offset + 4 <= data.count else { return nil }
            defer { offset += 4 }
            return data[data.startIndex + offset ..< data.startIndex + offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
        }

        mutating func string() -> Data? {
            guard let length = uint32().map(Int.init), offset + length <= data.count else { return nil }
            defer { offset += length }
            return data.subdata(in: data.startIndex + offset ..< data.startIndex + offset + length)
        }
    }

    // MARK: Antwort

    private struct Usage: Decodable {
        struct Limit: Decodable {
            struct Model: Decodable {
                var name: String?
                var request_count: Int?
            }
            var usage: Double?
            var models: [Model]?
        }
        struct Activity: Decodable {
            var cost: String?
        }
        var limits: [String: Limit]?
        var activity: Activity?
    }

    static func parseUsage(_ data: Data, now: Date = .now) throws -> ProviderSnapshot {
        guard let response = try? JSONDecoder().decode(Usage.self, from: data),
              let limits = response.limits, !limits.isEmpty
        else { throw ProviderError.badResponse }

        // Fenster ohne Reset-Zeit: Ollama sagt nur, wie viel verbraucht ist, nicht wann es endet.
        let known: [(key: String, name: String, note: String)] = [
            ("session", "Session", "5 h"), ("weekly", "Woche", "7 d"), ("monthly", "Monat", "Abo-Monat"),
        ]
        let windows = known.compactMap { entry -> LimitWindow? in
            guard let usage = limits[entry.key]?.usage else { return nil }
            return LimitWindow(id: entry.key, name: entry.name, scopeNote: entry.note,
                               percent: usage, resetsAt: nil, windowLength: nil)
        }
        guard !windows.isEmpty else { throw ProviderError.badResponse }

        // Anfragen je Modell aus dem längsten gemeldeten Fenster.
        let models = known.reversed().lazy.compactMap { limits[$0.key]?.models }.first { !$0.isEmpty } ?? []
        var extras = models
            .compactMap { model in model.name.map { ($0, model.request_count ?? 0) } }
            .sorted { $0.1 > $1.1 }
            .map { ExtraValue(id: "requests-\($0.0)", text: "\($0.0) · \($0.1) Anfragen") }
        // Kosten über den Plan hinaus sind echte, abgerechnete Beträge – keine Vergleichswerte.
        if let cost = response.activity?.cost.flatMap(Double.init), cost >= 0.005 {
            extras.append(ExtraValue(id: "billed", text: "Abgerechnet \(Format.money(cost)) / 4 Wochen"))
        }
        return ProviderSnapshot(account: nil, windows: windows, extras: extras, fetchedAt: now)
    }

    static func parseAccount(_ data: Data) -> AccountInfo? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let name = [root["Name"], root["Email"]].compactMap { $0 as? String }.first { !$0.isEmpty }
        let plan = (root["Plan"] as? String).flatMap { $0.isEmpty ? nil : $0.prefix(1).uppercased() + $0.dropFirst() }
        return AccountInfo(name: name, plan: plan)
    }
}
