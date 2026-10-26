# Token Stats

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black.svg?logo=apple)](#voraussetzungen)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138.svg?logo=swift&logoColor=white)](https://www.swift.org)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF.svg)](https://developer.apple.com/xcode/swiftui/)
[![Release](https://img.shields.io/github/v/release/mahype/token-stats?label=release&color=blue)](https://github.com/mahype/token-stats/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/mahype/token-stats/total?label=downloads&color=blue)](https://github.com/mahype/token-stats/releases)
[![Status: v2 in Arbeit](https://img.shields.io/badge/status-v2%20in%20Arbeit-orange.svg)](#roadmap)
[![Anbieter: Antigravity · Claude Code · Codex · Ollama](https://img.shields.io/badge/Anbieter-Antigravity%20%C2%B7%20Claude%20Code%20%C2%B7%20Codex%20%C2%B7%20Ollama-8A63D2.svg)](#anbieter)
[![Zugangsdaten nur lesen](https://img.shields.io/badge/Zugangsdaten-nur%20lesen-brightgreen.svg)](#was-die-app-liest-speichert-und-kontaktiert)
[![Keine Telemetrie](https://img.shields.io/badge/Telemetrie-keine-brightgreen.svg)](#was-die-app-liest-speichert-und-kontaktiert)
[![Keine Abhängigkeiten](https://img.shields.io/badge/Abh%C3%A4ngigkeiten-keine-brightgreen.svg)](#voraussetzungen)
[![Lizenz: MIT](https://img.shields.io/badge/Lizenz-MIT-blue.svg)](LICENSE)

Menüleisten-App für macOS, die die Kontingente deiner KI-Coding-Abos anzeigt:
Session-Fenster, Wochenlimit, Modell-Limits und Extra-Verbrauch von Claude Code,
Codex, Antigravity (Google) und Ollama Cloud. Dazu eine Verbrauchsseite mit Tokenzahlen je Tag und Modell und dem
**API-Vergleichswert** – was derselbe Verbrauch über die API gekostet hätte.

Die App beantwortet ohne Browser und ohne CLI die Frage **„Darf ich noch?“**. Sie nutzt
die Anmeldungen, die Claude Code, Codex, die Antigravity-CLI und Ollama ohnehin auf
deinem Mac haben. Kein Konto,
keine Cloud, keine Telemetrie.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="screenshots/limits-dark.png">
    <img src="screenshots/limits-light.png" width="372" alt="Popover „Limits“: Session, Woche und Opus-Limit von Claude mit Pace-Marke">
  </picture>
</p>

## Funktionen

- **Menüleisten-Symbol** in der Zustandsfarbe des knappsten Limits – grün, ab 80 % gelb,
  ab 100 % rot. Wahlweise nur das Symbol, mit Prozentwert oder mit zwei Mini-Balken
  für Session und Woche.
- **Ein Tab je Anbieter**, nach Dringlichkeit sortiert: Der knappste Anbieter steht
  links und ist beim Öffnen aktiv. Der Statuspunkt am Tab zeigt den Zustand ohne Klick.
- **Meter je Limit** mit Reset-Zeit und **Pace-Marke**: Die senkrechte Marke steht dort,
  wo du bei gleichmäßigem Verbrauch wärst. Der Abstand dazu ist schraffiert und darunter
  in Zeit umgerechnet, z. B. `1 Tag vorgegriffen` oder `4 Tage ungenutzt`.
- **Verbrauch** für Heute, 7 Tage, 30 Tage oder den Abrechnungsmonat: Tokens mit
  getrennt ausgewiesenem Cache-Anteil, Tagesdiagramm und Aufschlüsselung je Modell.
- **API-Vergleichswert** aus Tokenzahl × Listenpreis, mit mitgelieferter Preistabelle.
  Abschaltbar, wenn du nur Tokens sehen willst.
- **Schont die Rate-Limits:** höchstens alle 5 Minuten eine Abfrage, der letzte Stand
  überlebt Neustarts. Bei HTTP 429 bleiben die letzten Werte mit Pause-Symbol stehen –
  nie eine leere Anzeige.
- Rechtsklick aufs Symbol: Aktualisieren, Anzeige-Modus, Bei Anmeldung starten,
  Einstellungen (auch mit `⌘,` bei offenem Popover).
- **Widgets** für Schreibtisch und Mitteilungszentrale: „Verbrauch“ mit Tokens,
  API-Vergleichswert, Tagesdiagramm und Modellen für Heute, 7 Tage, 30 Tage oder den
  Abrechnungsmonat – und „Limits“ mit den Metern eines Anbieters samt Pace-Marke. Klick
  aufs Widget öffnet das Popover auf der passenden Seite.
- **iPhone und iPad** (optional): Die Mac-App überträgt ihren Stand auf Wunsch in deine
  private iCloud-Datenbank, die iOS-App zeigt Limits und Verbrauch aller Macs – dazu
  Widgets für Homescreen und Sperrbildschirm. Standardmäßig aus, siehe
  [iPhone](#iphone-und-ipad).

<table>
  <tr>
    <th width="50%">Verbrauch mit API-Vergleichswert</th>
    <th width="50%">Codex</th>
  </tr>
  <tr>
    <td valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="screenshots/usage-dark.png">
        <img src="screenshots/usage-light.png" alt="Seite „Verbrauch“: Tokens, API-Vergleichswert, Tagesdiagramm und Aufschlüsselung je Modell">
      </picture>
    </td>
    <td valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="screenshots/limits-codex-dark.png">
        <img src="screenshots/limits-codex-light.png" alt="Codex-Tab mit Wochenlimit und Code-Review-Limit">
      </picture>
    </td>
  </tr>
</table>

<table>
  <tr>
    <th width="50%">Antigravity</th>
    <th width="50%">Ollama Cloud</th>
  </tr>
  <tr>
    <td valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="screenshots/limits-antigravity-dark.png">
        <img src="screenshots/limits-antigravity-light.png" alt="Antigravity-Tab mit Wochenlimit für Gemini und für Claude & GPT">
      </picture>
    </td>
    <td valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="screenshots/limits-ollama-dark.png">
        <img src="screenshots/limits-ollama-light.png" alt="Ollama-Tab mit Session- und Wochenlimit und Anfragen je Modell">
      </picture>
    </td>
  </tr>
</table>

Die drei Anzeige-Modi der Menüleiste:

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="screenshots/menubar-dark.png">
    <img src="screenshots/menubar-light.png" width="270" alt="Menüleisten-Symbol: nur Icon, Icon mit Prozent, Icon mit Balken">
  </picture>
</p>

Die Widgets „Verbrauch“ und „Limits“ in Klein, Mittel und Groß (Zeitraum und Anbieter
sind je Widget einstellbar):

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="screenshots/widgets-dark.png">
    <img src="screenshots/widgets-light.png" width="560" alt="Widgets: Verbrauch heute und 7 Tage, Limits von Claude, Verbrauch 30 Tage mit Modellen">
  </picture>
</p>

Die iOS-App mit dem Stand eines Macs (Simulator, Demo-Werte):

<table>
  <tr>
    <th width="50%">Limits</th>
    <th width="50%">Verbrauch</th>
  </tr>
  <tr>
    <td valign="top" align="center"><img src="screenshots/ios-limits.png" width="300" alt="iOS-App, Tab „Limits“: ein Abschnitt je Mac mit den Metern aller Anbieter"></td>
    <td valign="top" align="center"><img src="screenshots/ios-usage.png" width="300" alt="iOS-App, Tab „Verbrauch“: Zeitraum, Anbieter, Kennzahlen, Tagesdiagramm und Modelle"></td>
  </tr>
</table>

Die Einstellungen – Anzeige, Stichtag des Abos und Abfrageintervall:

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="screenshots/settings-dark.png">
    <img src="screenshots/settings-light.png" width="460" alt="Einstellungsfenster mit den Abschnitten Anzeige, Verbrauch und Aktualisierung">
  </picture>
</p>

<sub>Alle Werte in den Screenshots sind Demo-Werte.</sub>

## Anbieter

| Anbieter | Limits | Verbrauch | Stand |
|---|---|---|---|
| **Claude Code** | Session 5 h · Woche · Modell-Limits (Opus, Sonnet …) · Extra-Verbrauch | ✅ | v1 / v2 |
| **Codex** | Session 5 h · Woche · Code-Review · Credits | ✅ | v1 / v2 |
| **Antigravity** (Google) | Wochenlimit Gemini · Wochenlimit Claude & GPT · Plan (z. B. Google AI Plus) | – | v3 |
| **Ollama Cloud** | Session 5 h · Woche · Monat (je nach Plan) · Anfragen je Modell · Kosten über den Plan | – | v3 |
| GitHub Copilot, Cursor | – | – | geplant (v3) |
| Prepaid (OpenRouter, DeepSeek, Moonshot, Fireworks) | echtes Restguthaben | – | geplant (v3) |

Jeder Anbieter ist eine Datei, die das Protokoll `UsageProvider` erfüllt – die
Oberfläche bleibt beim Hinzufügen unberührt.

## Voraussetzungen

- macOS 14 (Sonoma) oder neuer, Apple Silicon oder Intel
- Claude Code, Codex, die Antigravity-CLI (`agy`) und/oder Ollama (`ollama signin`),
  mindestens einmal angemeldet

Keine Pakete, kein Framework, keine Laufzeit – ein einzelnes `.app`.

## Installation

**[⬇ Token Stats herunterladen](https://github.com/mahype/token-stats/releases/latest)** –
unter *Assets* die Datei `Token-Stats-<Version>.dmg`.

1. Das DMG öffnen und **Token Stats** auf **Programme** ziehen.
2. Token Stats aus dem Programme-Ordner starten. Das Robotersymbol erscheint in der
   Menüleiste; ein Dock-Symbol gibt es nicht.
3. Optional: Rechtsklick aufs Symbol → **Bei Anmeldung starten**.

Updates kommen ab Version 0.2.0 von selbst: Token Stats sucht einmal täglich und
installiert eine neue Version beim Beenden. Wer 0.1.x hat, lädt 0.2.0 einmal von Hand.

Die App ist mit Developer ID signiert und von Apple notarisiert. Beim ersten Start liest
sie alle Session-Logs einmal ein (bei einigen Gigabyte Logs etwa 40 Sekunden), danach
nur noch, was neu dazukommt.

### Aus dem Quelltext bauen

Mit Xcode 16 oder neuer (Swift 6) und [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
git clone https://github.com/mahype/token-stats.git
cd token-stats
make run
```

`make run` baut die App und startet sie. Das Makefile nutzt `/Applications/Xcode.app`,
auch wenn `xcode-select` auf die Command Line Tools zeigt.

### Windows

Eine Portierung als Tray-App für Windows 10/11 (nativ ARM64, auch x64) liegt in
[`windows/`](windows/README.md) – gleiche Datenquellen und Rechnung, gebaut mit .NET 10.

## iPhone und iPad

Das iPhone kann die Anbieter nicht selbst abfragen und keine Logs lesen – es zeigt den
Stand deiner Macs. Dafür schreibt die Mac-App, wenn du es einschaltest, nach jeder
Abfrage einen Datensatz je Mac in deine **private iCloud-Datenbank** (CloudKit): Prozente,
Reset-Zeiten, Tagessummen und Beträge, dieselben Kilobyte wie für die Widgets. Keine
Zugangsdaten, keine Logs. Die iOS-App holt die Datensätze, zeigt sie als Abschnitt je Mac
(plus „Alle Macs“ zusammengerechnet) und lädt per stillem Push nach, sobald ein Mac
einen neuen Stand schreibt; daneben steht immer, wie alt der Stand ist, weil ein Mac
zwischendurch schlafen kann.

- Einschalten: Mac → Einstellungen → **iPhone → „Stand nach iCloud übertragen“**. Standard
  ist aus; ohne iPhone bleibt es bei „keine Cloud“.
- Die Mac-App braucht dafür einen Build mit iCloud-Berechtigung (`make build ICLOUD=1`,
  verlangt ein Provisioning-Profil – siehe [Entwicklung](#entwicklung)). Ohne sie ist der
  Schalter ausgegraut.
- Die iOS-App kommt nur über TestFlight oder den App Store aufs Gerät; ein Build aus
  Xcode mit eigenem Team geht für das eigene iPhone.
- Widgets auf iOS: Homescreen klein, mittel, groß wie auf dem Mac; Sperrbildschirm rund
  (Gauge des knappsten Limits), rechteckig (Session und Woche mit Reset) und inline
  („Claude 62 % · Reset 14:30“). Anbieter und Zeitraum je Widget einstellbar.

## Entfernen

**Bei Anmeldung starten** ausschalten, die App beenden, dann:

```bash
rm -rf "/Applications/Token Stats.app"
rm -rf ~/Library/Application\ Support/TokenStats   # letzter Stand und Verbrauchs-Aggregat
defaults delete de.mahype.TokenStats              # Einstellungen
```

Deine Anmeldungen bei Claude Code, Codex, Antigravity und Ollama bleiben unberührt.

## Wie aktuell sind die Zahlen?

**Limits** kommen vom Anbieter und gelten für das ganze Konto – Nutzung auf anderen
Geräten, im Browser oder in Desktop-Apps ist enthalten. Abgefragt wird im eingestellten
Intervall (mindestens 5 Minuten). Dafür braucht die App ein gültiges Token, und das
erneuert nur die jeweilige CLI auf diesem Mac:

| Anbieter | Limits aktuell, solange … | Sonst |
|---|---|---|
| **Antigravity** | `agy` in der letzten Stunde auf diesem Mac lief | letzter Stand mit grauem Hinweis; Nutzung anderswo fehlt bis zum nächsten `agy`-Start. Die Antigravity-Desktop-App erneuert das Token nicht. |
| **Claude Code** | `claude` in den letzten 8 Stunden im Terminal lief | „Anmeldung abgelaufen“ mit letztem Stand. Die Claude-Desktop-App erneuert das Token nicht. |
| **Codex** | Codex in den letzten 10 Tagen auf diesem Mac lief | „Anmeldung abgelaufen“ mit letztem Stand |
| **Ollama Cloud** | immer – Ollama muss nicht laufen, der Schlüssel läuft nicht ab | – |

Ist der Reset-Zeitpunkt eines Limits erreicht, steht es auch ohne neue Abfrage auf 0 %.

**Verbrauch** liest die Session-Logs **dieses Macs**. Was du auf einem anderen Rechner,
im Browser oder in einer Desktop-App verbrauchst, fehlt dort.

## Was die App liest, speichert und kontaktiert

| Was | Wo |
|---|---|
| Claude-Zugangsdaten (nur lesen) | Schlüsselbund `Claude Code-credentials`, Fallback `~/.claude/.credentials.json` |
| Codex-Zugangsdaten (nur lesen) | `~/.codex/auth.json` |
| Ollama-Schlüssel (nur lesen, zum Signieren) | `~/.ollama/id_ed25519` – verlässt den Mac nicht, gesendet wird nur die Signatur |
| Antigravity-Zugangsdaten (nur lesen) | Schlüsselbund `gemini` / `antigravity` (von `agy`), Projekt aus `~/.gemini/antigravity-cli/cache/` |
| Tokenzahlen (nur lesen) | `~/.claude/projects/**/*.jsonl`, Session-Logs unter `~/.codex/` |
| Letzter Stand der Limits | `~/Library/Application Support/TokenStats/state.json` (nur Prozente und Reset-Zeiten) |
| Verbrauchs-Aggregat je Tag und Modell | `~/Library/Application Support/TokenStats/usage.sqlite` |
| Stand für die Widgets | `~/Library/Group Containers/<Team-ID>.de.mahype.TokenStats/widgets.json` – Prozente, Reset-Zeiten, Tagessummen und Beträge, fertig gerechnet; keine Zugangsdaten |
| Stand fürs iPhone (nur wenn eingeschaltet) | private CloudKit-Datenbank `iCloud.de.mahype.TokenStats`, ein Datensatz je Mac mit demselben Inhalt wie `widgets.json` |
| Einstellungen | UserDefaults `de.mahype.TokenStats` |
| Claude-Kontingent | `api.anthropic.com/api/oauth/usage` |
| Codex-Kontingent | `chatgpt.com/backend-api/wham/usage` |
| Ollama-Kontingent und Plan | `ollama.com/api/usage` und `ollama.com/api/me` |
| Antigravity-Kontingent und Plan | `daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary` und `:loadCodeAssist` |
| Update-Prüfung (täglich, abschaltbar) | `mahype.github.io/token-stats/appcast.xml`, Download von `github.com` |

- **Zugangsdaten werden nur gelesen** – nicht kopiert, nicht ins App-Verzeichnis
  gespiegelt, nicht erneuert. Ist ein Token abgelaufen, zeigt die App einen Hinweis;
  einmal Claude Code bzw. Codex starten genügt, die CLI erneuert es selbst. Wie lange
  die Zahlen ohne CLI aktuell bleiben, steht unter
  [Wie aktuell sind die Zahlen?](#wie-aktuell-sind-die-zahlen)
- **Nur die Anbieter-Endpunkte** werden kontaktiert, dazu einmal täglich der Update-Feed –
  ohne Systemdaten, abschaltbar unter Einstellungen → Updates. Preise stammen aus der
  mitgelieferten Tabelle, nicht aus dem Netz. iCloud nur, wenn du „Stand nach iCloud
  übertragen“ einschaltest.
- **Abfrageintervall mindestens 300 s.** Die Usage-Endpunkte sind undokumentiert und
  hart rate-limitiert.

## API-Vergleichswert ≠ Kosten

Abo-Verbrauch wird nicht pro Nachricht abgerechnet, und die Usage-Endpunkte liefern
nur Prozentwerte. Der Betrag auf der Verbrauchsseite ist deshalb eine Modellrechnung:
Input, Output, Cache-Schreiben und Cache-Lesen aus den lokalen Logs, jeweils mal
Listenpreis zum Zeitpunkt der Anfrage. Er zeigt, was derselbe Verbrauch über die API
gekostet hätte – nicht, was du zahlst.

Cache-Tokens stehen immer getrennt: Bei Claude Code machen sie oft rund 80 % des
Volumens aus, kosten aber nur einen Bruchteil des Input-Preises. Eine nackte
Gesamt-Tokenzahl würde in die Irre führen.

## Entwicklung

| Befehl | Zweck |
|---|---|
| `make build` | Projekt aus `project.yml` erzeugen und bauen |
| `make run` | bauen, laufende Instanz beenden, neu starten |
| `make test` | Unit-Tests (beendet eine laufende Instanz, danach `make run`) |
| `make release` | Universal-Build als DMG nach `build/`: signiert, notarisiert, gestapelt |
| `make publish` | Tag, GitHub-Release und Eintrag im Update-Feed für dieses DMG |
| `make screenshots` | die Bilder dieser README nach `screenshots/` rendern (außer Einstellungen, siehe [CLAUDE.md](CLAUDE.md)) |
| `make ios` · `make ios-run` | iOS-App für den Simulator bauen bzw. dort mit Demo-Werten starten (`SIMULATOR="iPhone 16"` wählt das Gerät) |
| `make build ICLOUD=1` · `make release ICLOUD=1` | Mac-App mit iCloud-Berechtigung (verlangt ein Provisioning-Profil mit iCloud; für Developer ID `PROVISIONING_PROFILE_SPECIFIER` mitgeben) |
| `swift build` in `Packages/TokenStatsCore` | nur den gemeinsamen Kern bauen |
| `Scripts/update-pricing.sh` | Preistabelle aus LiteLLM aktualisieren |

`TokenStats.xcodeproj` ist nicht eingecheckt, XcodeGen erzeugt es bei jedem Build.
`usage.sqlite` löschen erzwingt ein komplettes Neueinlesen der Logs.

Debug-Builds signiert `make build` mit einem „Apple Development“-Zertifikat aus dem
Schlüsselbund, falls eines da ist, sonst ad hoc. Die Widgets brauchen die Team-Signatur:
Die App Group heißt `<Team-ID>.de.mahype.TokenStats`, und macOS lässt nur Apps desselben
Teams an den Container. Ad hoc signiert läuft die App, die Widgets zeigen dann aber nur
„Token Stats öffnen“.

| Pfad | Inhalt |
|---|---|
| `Sources/TokenStats/Providers/` | ein Anbieter je Datei: Zugangsdaten lesen, Endpunkt abfragen, Antwort übersetzen |
| `Sources/TokenStats/Model/` | Stand je Anbieter, Abruftakt, Rate-Limit-Behandlung, Einstellungen |
| `Sources/TokenStats/Usage/` | Log-Parser, SQLite-Aggregat, Preistabelle |
| `Sources/TokenStats/UI/` | Popover, Verbrauchsseite, Einstellungen, Menüleisten-Symbol |
| `Sources/TokenStatsWidgets/` | WidgetKit-Erweiterung für Mac und iOS: Konfiguration und Timelines der Widgets „Verbrauch“ und „Limits“, Sperrbildschirm-Familien |
| `Sources/TokenStatsiOS/` | iOS-App: iCloud-Stand laden, Tabs „Limits“ und „Verbrauch“ |
| `Packages/TokenStatsCore/` | gemeinsamer Kern von App und Widgets: Datenmodell, Formate, Preistabelle, Zustandsfarben, Widget-Views, Demo-Werte |
| `Tests/TokenStatsTests/` | Parser- und Verbrauchstests |

Das vollständige Design mit den Begründungen hinter den Entscheidungen steht in
[SPEC.md](SPEC.md).

## Roadmap

- [x] **v1** – Limits für Claude und Codex, drei Anzeige-Modi, Rate-Limit-Behandlung
- [ ] **v2** – Verbrauchsseite mit API-Vergleichswert ✅ · Mitteilungen bei 50/80/90 %
  und bei Reset
- [ ] **v3** – Antigravity ✅ · Ollama Cloud ✅ · Widgets ✅ · iOS-App ✅ · Copilot, Cursor,
  Prepaid-Guthaben, Claude-Account-Wechsel

## Lizenz

MIT – siehe [LICENSE](LICENSE).

## Hinweis

Unabhängiges Community-Projekt, nicht verbunden mit Anthropic, OpenAI, Google oder Ollama.
Claude ist eine Marke von Anthropic, Codex und ChatGPT sind Marken von OpenAI,
Gemini und Antigravity sind Marken von Google, Ollama ist eine Marke von Ollama Inc.
Die abgefragten Usage-Endpunkte sind nicht dokumentiert und können sich jederzeit
ändern.
