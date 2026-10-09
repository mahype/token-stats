# Änderungen

Jede Version hat einen Abschnitt `## X.Y.Z`. `make publish` übernimmt ihn als Text für
das GitHub-Release und für den Update-Dialog in der App.

## 0.3.2

- **Preistabelle:** Claude Haiku 5.5 ist neu. Bei Claude Sonnet 5.5 kosten Cache-Treffer
  jetzt 0,10 $ statt 0,20 $ pro Million Tokens. Alle übrigen Preise sind mit den
  offiziellen Preisseiten abgeglichen, Stand 09.10.2026. Haiku 5.5 wird bei Anfragen
  über 100.000 Tokens teurer; der API-Vergleichswert rechnet mit dem Preis darunter.

## 0.3.1

- **Claude abgemeldet statt „abgelaufen“:** Hat sich die Claude-Code-CLI abgemeldet –
  etwa nach `/logout` oder einer gescheiterten Token-Erneuerung –, sagt Token Stats das
  jetzt so und nennt `claude auth login`. Bisher fiel die App auf eine veraltete
  Zugangsdatei zurück und meldete nur „Anmeldung abgelaufen“. Die Claude-Desktop-App
  hat eine eigene Anmeldung und bleibt davon unberührt.

## 0.3.0

- **Antigravity (Google):** Neuer Anbieter mit den Wochenlimits für Gemini und für
  Claude & GPT sowie dem Plan (z. B. „Google AI Plus“). Voraussetzung ist die
  Antigravity-CLI `agy`, einmal angemeldet. Weil Google-Tokens nur eine Stunde leben
  und nur `agy` sie erneuert, zeigt Token Stats danach den letzten Stand mit Hinweis.
- **Ollama Cloud:** Neuer Anbieter mit Session-, Wochen- und (je nach Plan)
  Monatslimit, den Anfragen je Modell und abgerechneten Kosten über den Plan.
  Voraussetzung ist `ollama signin`. Lokale Modelle haben kein Kontingent und tauchen
  nicht auf.
- **Wie aktuell sind die Zahlen?** Neuer README-Abschnitt: Was jeder Anbieter braucht,
  damit die Limits aktuell bleiben. Die Verbrauchsseite sagt jetzt ausdrücklich, dass
  sie nur Nutzung auf diesem Mac enthält.
- **Zusatzwerte umbrechen:** Passen die Chips unter den Balken nicht in eine Zeile,
  fließen sie in die nächste.
- **Tabs alphabetisch:** Die Anbieter stehen in fester Reihenfolge nach Namen statt
  nach Dringlichkeit. Beim Öffnen ist weiterhin der knappste Anbieter ausgewählt.
- **Reset ohne Abfrage:** Ist der Reset-Zeitpunkt eines Limits erreicht, steht es sofort
  auf 0 %, auch wenn gerade keine Abfrage möglich ist.
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
