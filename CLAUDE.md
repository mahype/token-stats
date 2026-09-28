# Token Stats

macOS-Menüleisten-App, die die Kontingente aller lokal angemeldeten KI-Coding-Abos
anzeigt (Claude Code, Codex, später Gemini/Copilot/Cursor/Prepaid-Anbieter) — plus eine
Verbrauchsseite mit Tokenzahlen und API-Vergleichswert. Vorbild sind die Bar-Widgets aus
dem Omarchy-Umfeld.

## Stand

v1 in Arbeit: Grundgerüst, Claude- und Codex-Provider und Seite „Limits“ laufen gegen die
echten Endpunkte. Das Design liegt vollständig in [SPEC.md](SPEC.md). Bevor du etwas änderst: SPEC.md lesen — dort stehen auch die
Begründungen für Entscheidungen, die sonst wie Geschmacksfragen aussehen.

Visueller Entwurf mit allen Mockups (Menüleiste, Popover „Limits“ und „Verbrauch“,
Einstellungen, Mitteilung): https://claude.ai/artifact/XYL3hXk3QU1F5wpBQzkd3w

## Bauen

`make build` · `make test` · `make run` (XcodeGen erzeugt `TokenStats.xcodeproj` aus
`project.yml`; das Projekt ist nicht eingecheckt). Das Makefile setzt `DEVELOPER_DIR`,
weil `xcode-select` hier auf die Command Line Tools zeigt.

Die App cacht den letzten Stand in `~/Library/Application Support/TokenStats/state.json`
und fragt nach einem Neustart erst nach Ablauf des Intervalls wieder ab — häufiges
`make run` verbraucht also kein Rate-Limit.

## Nächster Schritt

Rest von v1 (SPEC.md §8) prüfen und polieren, dann v2: Verbrauchsseite und Mitteilungen.

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
