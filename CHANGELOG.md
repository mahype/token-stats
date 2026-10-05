# Änderungen

Jede Version hat einen Abschnitt `## X.Y.Z`. `make publish` übernimmt ihn als Text für
das GitHub-Release und für den Update-Dialog in der App.

## Unveröffentlicht

- **Claude-Anmeldung:** Nach „Anmeldung abgelaufen“ erkennt Token Stats ein erneuertes
  Token jetzt innerhalb von 30 s statt erst nach dem nächsten Abfrageintervall. Der
  Hinweis sagt genauer, was zu tun ist: Die Claude-Desktop-App erneuert das Token der
  CLI nicht, dafür muss `claude` einmal im Terminal laufen.
- **Preistabelle:** API-Vergleichswerte jetzt auch für GPT-6 (Sol, 6.1 Sol, Luna, Astra)
  und Claude Sonnet 5.5. Stand 05.10.2026.

## 0.2.0

- **Automatische Updates:** Token Stats sucht einmal täglich nach einer neuen Version und
  installiert sie beim Beenden. Abschaltbar unter Einstellungen → Updates, dort auch
  „Jetzt suchen“. Ab dieser Version ist kein manueller Download mehr nötig.
- **Pace als Fläche:** Der Abstand zwischen Verbrauch und Zeitmarke ist im Balken
  schraffiert und darunter in Zeit umgerechnet – „1 Tag vorgegriffen“, „4 Tage
  ungenutzt“ oder „im Takt“ statt „18 Pkt. über Plan“.

## 0.1.1

- Signiert und von Apple notarisiert – die App startet ohne Gatekeeper-Warnung.
  Funktional identisch mit 0.1.0.

## 0.1.0

- Erste Version: Limits für Claude Code und Codex in der Menüleiste, Verbrauchsseite mit
  Tokens und API-Vergleichswert.
