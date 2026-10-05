import Foundation

enum HTTP {
    /// Ephemere Session: keine Cookies, kein Disk-Cache, nichts bleibt liegen.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.urlCache = nil
        config.httpCookieStorage = nil
        return URLSession(configuration: config)
    }()

    /// GET mit Bearer-Token. Wirft `ProviderError` für alles außer 200.
    static func getJSON(_ url: URL, headers: [String: String], expiredHint: String) async throws -> Data {
        try await send(URLRequest(url: url), headers: headers, expiredHint: expiredHint)
    }

    /// POST mit JSON-Body – die Google-Endpunkte sind RPCs, auch wenn sie nur lesen.
    static func postJSON(_ url: URL, body: [String: Any], headers: [String: String], expiredHint: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(request, headers: headers, expiredHint: expiredHint)
    }

    private static func send(_ request: URLRequest, headers: [String: String], expiredHint: String) async throws -> Data {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ProviderError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw ProviderError.badResponse }
        switch http.statusCode {
        case 200: return data
        case 401, 403: throw ProviderError.unauthorized(hint: expiredHint)
        case 429:
            throw ProviderError.rateLimited(retryAfter: retryAfter(http.value(forHTTPHeaderField: "Retry-After")))
        default: throw ProviderError.http(status: http.statusCode)
        }
    }

    /// Retry-After als Sekunden oder HTTP-Datum; auf 6 h begrenzt.
    static func retryAfter(_ header: String?, now: Date = .now) -> TimeInterval? {
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else { return nil }
        let seconds: TimeInterval?
        if let value = TimeInterval(header) {
            seconds = value
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            seconds = formatter.date(from: header).map { $0.timeIntervalSince(now) }
        }
        guard let seconds, seconds > 0 else { return nil }
        return min(seconds, 6 * 3600)
    }
}

enum JWT {
    /// Payload eines JWT ohne Signaturprüfung – nur für Ablaufzeit und Plan.
    static func payload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

enum Keychain {
    /// Generisches Passwort über `/usr/bin/security` – so legen die CLIs ihre Einträge an,
    /// und es gibt keine Rückfrage bei jedem neuen (ad-hoc-signierten) Build.
    static func password(service: String, account: String? = nil) -> Data? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service] + (account.map { ["-a", $0] } ?? []) + ["-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}
