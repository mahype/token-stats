// swift-tools-version: 6.0
import PackageDescription

// Gemeinsamer Kern von App, Widget-Erweiterung und (später) iOS-Fassung: Datenmodell,
// Formate, Preistabelle, Zustandsfarben und die Widget-Views. Kein Netz, keine Logs –
// die bleiben in der App.
let package = Package(
    name: "TokenStatsCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "TokenStatsCore", targets: ["TokenStatsCore"]),
    ],
    targets: [
        .target(name: "TokenStatsCore"),
    ]
)
