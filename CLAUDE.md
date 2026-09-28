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
`project.yml`; das Projekt ist nicht eingecheckt). Das Makefile setzt `DEVELOPER_DIR`,
weil `xcode-select` hier auf die Command Line Tools zeigt.

Die App cacht den letzten Stand in `~/Library/Application Support/TokenStats/state.json`
und fragt nach einem Neustart erst nach Ablauf des Intervalls wieder ab — häufiges
`make run` verbraucht also kein Rate-Limit. Das Verbrauchs-Aggregat liegt daneben in
`usage.sqlite`; löschen erzwingt ein komplettes Neueinlesen (~40 s).

`make test` startet die App als Test-Host und beendet dabei eine laufende Instanz —
danach `make run`. Preistabelle aktualisieren: `Scripts/update-pricing.sh`.
README-Bilder neu rendern: `make screenshots` (nur Debug-Build; Hell und Dunkel). Alle
Werte sind Demo-Werte (`Screenshots.swift`) – für Screenshots nie echte Limits, Logs oder
Kontonamen verwenden. Braucht keine Bildschirmaufnahme-Freigabe, weil die App
ihre Views selbst zeichnet. Ausnahme Einstellungen: Offscreen zeichnet AppKit die Schalter
grau, darum echt aufnehmen – App mit `TOKENSTATS_OPEN_SETTINGS=1` starten (Demo-Werte,
keine Abfrage, öffnet das Fenster; nur Debug), Fenster-ID per `CGWindowListCopyWindowInfo` holen,
`screencapture -x -o -l <id>`, je einmal im hellen und dunklen Modus. Braucht die
Freigabe „Bildschirmaufnahme“ für das Terminal.

Release: `MARKETING_VERSION` in `project.yml` hochsetzen, `make release` (Universal-DMG in
`build/`), Tag `vX.Y.Z` pushen, `gh release create vX.Y.Z build/Token-Stats-X.Y.Z.dmg`.
Nur ad-hoc signiert, nicht notarisiert – es gibt hier kein „Developer ID Application“-
Zertifikat. Nutzer müssen den ersten Start unter Datenschutz & Sicherheit freigeben
(steht in der README).

## Nächster Schritt

Rest von v2 (SPEC.md §8): Mitteilungen bei 50/80/90 % und bei Reset (§5).

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
