import Foundation
import TokenStatsCore

/// Ruft `rtk gain --format json --daily` auf, falls rtk installiert ist. Nur lokal, kein Netz.
enum RtkReader {
    /// GUI-Apps erben keinen Shell-PATH, darum die üblichen Installationsorte der Reihe nach.
    static func executable(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let candidates = [
            URL(filePath: "/opt/homebrew/bin/rtk"),
            URL(filePath: "/usr/local/bin/rtk"),
            home.appending(path: ".cargo/bin/rtk"),
            home.appending(path: ".local/bin/rtk"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static let timeout: TimeInterval = 10

    /// `nil`, wenn rtk fehlt, fehlschlägt, hängt oder etwas Unlesbares ausgibt – dann fehlt der Block.
    static func load() async -> [RtkDay]? {
        guard let url = executable() else { return nil }
        return await Task.detached(priority: .utility) { run(url) }.value
    }

    private static func run(_ url: URL) -> [RtkDay]? {
        let process = Process()
        process.executableURL = url
        process.arguments = RtkSavings.arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch {
            NSLog("Token Stats: rtk nicht startbar: \(error.localizedDescription)")
            return nil
        }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationStatus == 0 else {
            NSLog("Token Stats: rtk gain endete mit \(process.terminationStatus)")
            return nil
        }
        guard let days = RtkSavings.parse(data) else {
            NSLog("Token Stats: Ausgabe von rtk gain nicht lesbar")
            return nil
        }
        return days
    }
}
