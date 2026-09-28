import SwiftUI

/// Einstellungsfenster, Abschnitte „Anzeige“, „Verbrauch“, „Aktualisierung“ und „Updates“ (SPEC §4).
struct SettingsView: View {
    @Bindable var settings: AppSettings
    let store: UsageStore
    let consumption: ConsumptionStore
    @Bindable var updater: Updater

    @State private var launchAtLogin = false

    private let intervals: [TimeInterval] = [300, 600, 900, 1800, 3600]

    var body: some View {
        Form {
            Section("Anzeige") {
                Picker("Menüleiste", selection: $settings.menuBarMode) {
                    ForEach(MenuBarMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Angezeigter Wert", selection: $settings.fixedWindow) {
                    Text("Knappstes Limit").tag(String?.none)
                    Divider()
                    ForEach(windowChoices, id: \.key) { choice in
                        Text(choice.label).tag(Optional(choice.key))
                    }
                }

                Toggle("Zustandsfarbe im Icon verwenden", isOn: $settings.useStateColor)
                Toggle("API-Vergleichswert in Geld anzeigen", isOn: $settings.showMoney)
                Toggle("Bei Anmeldung starten", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        settings.launchAtLogin = newValue
                        launchAtLogin = settings.launchAtLogin
                    }
            }

            Section {
                Picker("Stichtag des Abos", selection: $settings.billingDay) {
                    ForEach(1...31, id: \.self) { Text("\($0).").tag($0) }
                }
                .onChange(of: settings.billingDay) { consumption.refresh() }
            } header: {
                Text("Verbrauch")
            } footer: {
                Text("Beginn des Zeitraums „Abrechnungsmonat“. In kürzeren Monaten gilt der Monatsletzte.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Abfrageintervall", selection: $settings.refreshInterval) {
                    ForEach(intervals, id: \.self) { Text("\(Int($0 / 60)) Min.").tag($0) }
                }
            } header: {
                Text("Aktualisierung")
            } footer: {
                Text("Die Usage-Endpunkte sind hart rate-limitiert. Kürzer als 5 Minuten führt zu Fehlern.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Automatisch nach Updates suchen", isOn: $updater.automaticallyChecks)
                LabeledContent("Version \(Self.version)") {
                    Button("Jetzt suchen") { updater.checkNow() }
                }
            } header: {
                Text("Updates")
            } footer: {
                Text(updatesFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!updater.isAvailable)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { launchAtLogin = settings.launchAtLogin }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private var updatesFooter: String {
        guard updater.isAvailable else { return "In Debug-Builds abgeschaltet." }
        let last = updater.lastCheck.map { "Zuletzt gesucht \(Format.ago($0))." } ?? "Noch nicht gesucht."
        return "Einmal täglich, ohne Systemdaten. Updates werden beim Beenden installiert. \(last)"
    }

    /// Alle bekannten Limits als „Claude · Woche“.
    private var windowChoices: [(key: String, label: String)] {
        store.providers.flatMap { provider in
            (store.states[provider.id]?.snapshot?.windows ?? []).map {
                (key: "\(provider.id)/\($0.id)", label: "\(provider.displayName) · \($0.name)")
            }
        }
    }
}
