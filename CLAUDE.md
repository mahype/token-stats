# Token Stats

macOS-Menüleisten-App, die die Kontingente aller lokal angemeldeten KI-Coding-Abos
anzeigt (Claude Code, Codex, später Gemini/Copilot/Cursor/Prepaid-Anbieter) — plus eine
Verbrauchsseite mit Tokenzahlen und API-Vergleichswert. Vorbild sind die Bar-Widgets aus
dem Omarchy-Umfeld.

## Stand

v1 steht (Limits für Claude und Codex gegen die echten Endpunkte). v2 in Arbeit: Seite
„Verbrauch“ mit JSONL-Pipeline, SQLite-Aggregat und Preistabelle ist drin, Mitteilungen
fehlen noch. Das Design liegt vollständig in [SPEC.md](SPEC.md). Bevor du etwas änderst: SPEC.md lesen — dort stehen auch die
Begründungen für Entscheidungen, die sonst wie Geschmacksfragen aussehen.

Visueller Entwurf mit allen Mockups (Menüleiste, Popover „Limits“ und „Verbrauch“,
Einstellungen, Mitteilung): https://claude.ai/artifact/XYL3hXk3QU1F5wpBQzkd3w

## Bauen

`make build` · `make test` · `make run` (XcodeGen erzeugt `TokenStats.xcodeproj` aus
`project.yml`; das Projekt ist nicht eingecheckt, die Entitlements-Dateien in `Config/`
ebenfalls nicht – ihr Inhalt steht in `project.yml`). Das Makefile setzt `DEVELOPER_DIR`,
weil `xcode-select` hier auf die Command Line Tools zeigt.

Debug-Builds signiert das Makefile mit einem „Apple Development“-Zertifikat aus dem
Schlüsselbund, falls vorhanden, sonst ad hoc. Nur mit Team-Signatur bekommen die Widgets
Daten: Die App Group heißt `<Team-ID>.de.mahype.TokenStats` (SPEC §7 „Widgets“). Ob die App
sie schreiben kann, steht im Debug-Build in stderr („Widget-Stand geschrieben“) –
`open --stderr datei "build/…/Token Stats.app"`; der Container selbst ist für das Terminal
nicht lesbar (TCC). Widgets im Gerätetest: Mitteilungszentrale → „Widgets bearbeiten“ →
„Token Stats“. Gemeinsamer Code von App und Erweiterung liegt im Paket
`Packages/TokenStatsCore` (`swift build` dort baut ihn allein).

iOS-App (Issue #11): `make ios` baut für den Simulator, `make ios-run` startet sie dort mit
Demo-Werten zweier Macs (`TOKENSTATS_DEMO=1`; `TOKENSTATS_TAB=usage` für den zweiten Tab,
Screenshot mit `xcrun simctl io booted screenshot`). Der echte Weg über CloudKit braucht
den Container `iCloud.de.mahype.TokenStats` im Developer-Portal; die Mac-App bekommt die
iCloud-Berechtigung nur mit `make build ICLOUD=1` bzw. `make release ICLOUD=1` (verlangt
ein Provisioning-Profil, für Developer ID `PROVISIONING_PROFILE_SPECIFIER` mitgeben).
Ohne sie ist „Stand nach iCloud übertragen“ in den Einstellungen ausgegraut.

Die App cacht den letzten Stand in `~/Library/Application Support/TokenStats/state.json`
und fragt nach einem Neustart erst nach Ablauf des Intervalls wieder ab — häufiges
`make run` verbraucht also kein Rate-Limit. Das Verbrauchs-Aggregat liegt daneben in
`usage.sqlite`; löschen erzwingt ein komplettes Neueinlesen (~40 s).

Windows-Port (.NET 10, WPF) in `windows/`: `dotnet test` und `.\publish.ps1` dort, Details
in [windows/README.md](windows/README.md). Änderungen an Parsern, Formaten oder Texten
gehören in beide Fassungen.

`make test` startet die App als Test-Host und beendet dabei eine laufende Instanz —
danach `make run`. Preistabelle aktualisieren: `Scripts/update-pricing.sh`.
README-Bilder neu rendern: `make screenshots` (nur Debug-Build; Hell und Dunkel). Alle
Werte sind Demo-Werte (`DemoData` in TokenStatsCore, auch für die Widget-Vorschau) – für
Screenshots nie echte Limits, Logs oder Kontonamen verwenden. Braucht keine Bildschirmaufnahme-Freigabe, weil die App
ihre Views selbst zeichnet. Ausnahme Einstellungen: Offscreen zeichnet AppKit die Schalter
grau, darum echt aufnehmen – App mit `TOKENSTATS_OPEN_SETTINGS=1` starten (Demo-Werte,
keine Abfrage, öffnet das Fenster; nur Debug), Fenster-ID per `CGWindowListCopyWindowInfo` holen,
`screencapture -x -o -l <id>`, je einmal im hellen und dunklen Modus. Braucht die
Freigabe „Bildschirmaufnahme“ für das Terminal.

Release: `MARKETING_VERSION` in `project.yml` hochsetzen, Abschnitt `## X.Y.Z` in
`CHANGELOG.md` schreiben, committen, `make release` (Universal-DMG in `build/`, mit
„Developer ID Application: Sven Wagener (2GA7DQ3P3Z)“ signiert, notarisiert und gestapelt),
dann `make publish` (Tag, GitHub-Release, Sparkle-Appcast auf `gh-pages` → GitHub Pages).
Der Sparkle-Schlüssel liegt nur im Schlüsselbund (Konto `token-stats`, Dienst
`https://sparkle-project.org`); ohne ihn können installierte Apps keine Updates mehr
annehmen. Sicherung: `generate_keys --account token-stats -x datei` aus
`build/SourcePackages/artifacts/sparkle/Sparkle/bin/`.
Die Notarisierung nutzt das Schlüsselbund-Profil `notary` (`xcrun notarytool
store-credentials`). Team-ID ist `2GA7DQ3P3Z` (OU im Zertifikat) – nicht die Kennung in
Klammern im Namen des Development-Zertifikats. `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`
ist nötig, sonst lehnt Apple die App wegen `get-task-allow` ab.

## Nächster Schritt

Rest von v2 (SPEC.md §8): Mitteilungen bei 50/80/90 % und bei Reset (§5). Für die
iOS-Fassung (Issue #11) steht der Live-Test aus: Container anlegen, Developer-ID-Profil mit
iCloud, TestFlight.

## Harte Randbedingungen

- **Abfrageintervall mindestens 300 s.** Die Usage-Endpunkte sind undokumentiert und hart
  rate-limitiert; kürzere Intervalle liefern Fehler. Bei HTTP 429 die letzten Werte mit
  Pause-Symbol und Retry-After anzeigen, nie eine leere Anzeige.
- **Zugangsdaten nur lesen.** Nicht kopieren, nicht ins App-Verzeichnis spiegeln,
  ausschließlich Anbieter-Endpunkte kontaktieren.
- **Geldbeträge aus lokaler Rechnung heißen „API-Vergleichswert“, nicht „Kosten“.**
  Abo-Verbrauch wird nicht abgerechnet; der Betrag ist Tokenzahl × Listenpreis.
  Nur Prepaid-Guthaben sind echte, abgerufene Beträge.
- **Cache-Tokens immer getrennt ausweisen** — bei Claude Code sind sie oft ~80 % des
  Volumens zu einem Bruchteil des Input-Preises.

## Sprache

Projektsprache ist Deutsch: UI-Texte, Dokumentation und Commit-Messages auf Deutsch,
Code und Symbolnamen auf Englisch.
