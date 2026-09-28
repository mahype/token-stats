# Token Stats — Spezifikation

macOS-Menüleisten-App, die die Kontingente aller lokal angemeldeten KI-Coding-Abos
anzeigt: Session-Fenster, Wochenlimit, Modell-Limits, Restguthaben — plus eine
Verbrauchsseite mit Tokenzahlen und API-Vergleichswert.

Vorbild sind die Bar-Widgets aus dem Omarchy-Umfeld (claudebar/codexbar, OAgents,
omarchy-ai-usage, ai-usage-bar). Sie sind nicht Teil von Omarchy selbst, folgen aber
alle demselben Muster: ein Icon in der Bar, ein Panel mit einem Abschnitt je Abo.

Visueller Entwurf (Mockups von Menüleiste, Popover, Verbrauchsseite, Einstellungen,
Mitteilung): https://claude.ai/artifact/XYL3hXk3QU1F5wpBQzkd3w

---

## 1. Produktziel

Eine Frage soll ohne Browser, ohne CLI und ohne Nachdenken beantwortet werden:
**„Darf ich noch?“** — und als zweite Frage: **„Was habe ich verbraucht, und was hätte
das ohne Abo gekostet?“**

Nicht-Ziele: kein Kostenmanagement-Dashboard, keine Cloud, kein Konto, keine Telemetrie,
kein Verändern von Zugangsdaten außer beim expliziten Account-Wechsel.

---

## 2. Menüleiste

Standardanzeige ist **nur das Template-Icon** (Roboterkopf), dessen Farbe den Zustand
codiert. Alles Weitere ist Option in den Einstellungen, weil Breite in der Menüleiste
teuer ist.

| Modus | Anzeige | Breite |
|---|---|---|
| `icon` (Standard) | nur Icon, Zustandsfarbe | ~22 pt |
| `icon+pct` | Icon + Prozent des knappsten Limits | ~26–30 pt |
| `icon+bars` | Icon + zwei 3-pt-Mini-Balken (oben Session, unten Woche) | ~30 pt |

- Angezeigter Wert: **knappstes Limit über alle Anbieter** (Standard) oder ein fest
  gewählter Wert (z. B. immer „Claude · Woche“).
- Zustandsfarben: < 50 % grün, 50–79 % neutral/grün, 80–99 % gelb, ≥ 100 % rot.
  (Omarchy-Konvention: gelb ab 80 %, rot ab 100 %.)
- Template-Icon, damit Hell/Dunkel automatisch passt; bei aktivierter Zustandsfarbe
  wird das Icon getönt.
- Optional ein eigenes Symbol pro Client — möglich, aber **nicht** Standard.
- Linksklick öffnet das Popover, Rechtsklick ein `NSMenu`:
  Aktualisieren · Anzeige-Modus · Bei Anmeldung starten · Einstellungen · Beenden.

---

## 3. Popover

Breite 372 pt. Aufbau von oben nach unten:

### 3.1 Kopfzeile
Roboter-Icon · „Token Stats“ · rechts der Seitenumschalter `Limits · Verbrauch` (§3.3).
Das knappste Limit steht hier nicht mehr (Entscheidung 28.09.2026): Es ist schon in der
Menüleiste sichtbar und in den Tab-Punkten; doppelt wirkte der Kopf überladen.

### 3.2 Tab-Leiste — ein Tab je Client
`Claude · Codex · Gemini · Copilot · +2`

- Jeder Tab trägt einen 5-pt-Statuspunkt in der Zustandsfarbe. Damit ist der kritische
  Anbieter ohne Klick sichtbar.
- **Sortierung nach Dringlichkeit:** knappster Client links, beim Öffnen aktiv.
- Passen nicht alle Tabs in die Breite, sammelt `+n` den Rest in einem Menü.
- Tabs statt langer Liste, weil die Popover-Höhe sonst mit jedem Anbieter wächst.

### 3.3 Seitenumschalter
`Limits · Verbrauch` als schlanker Kapsel-Umschalter rechts in der Kopfzeile, gilt für
alle Tabs. Kein Segmented Control im Inhalt — das wirkte zu klotzig.
Beim Öffnen steht **immer „Limits“** — die Auswahl wird absichtlich nicht gemerkt.

### 3.4 Seite „Limits“
Kopfzeile des Tabs: Client-Name · Plan (`Max 20×`) · Zustands-Chip mit knappstem Wert.

Je Limit eine Meter-Zeile:

```
Woche  7 d, alle Modelle                      82 %
[███████████████████░░░░░░░]   ← Pace-Marke bei 64 %
Reset Mi 09:00          64 % der Zeit · 18 Pkt. über Plan
```

- Balken 6 pt hoch, Füllfarbe = Zustandsfarbe.
- **Pace-Marke:** dünne senkrechte Marke an der Position „Anteil der verstrichenen
  Fensterzeit“. Füllstand rechts davon = zu schneller Verbrauch. Zusätzlich als Text
  („64 % der Zeit · 18 Pkt. über Plan“).
- Reset-Zeit als Uhrzeit bzw. Wochentag + Uhrzeit, nicht als Countdown.
- Zeilen für Claude: Session 5 h · Woche 7 d · Opus · Sonnet.
- Darunter Pills für Beträge und Kleinwerte: `Extra 12,40 $ / 50 $`, `Guthaben 7,10 $`,
  `heute 4,1 M Tokens`.

### 3.5 Seite „Verbrauch“
- Zeitraum-Umschalter: **Heute · 7 Tage · 30 Tage · Abrechnungsmonat.**
  Der Abrechnungsmonat macht den Vergleich mit dem Abopreis erst ehrlich.
- Zwei Kennzahl-Tiles: `Tokens 38,4 M` (Unterzeile: Cache-Anteil) und
  `API-Vergleichswert 214,80 $` (Unterzeile: `Abo 200 $ / Monat`).
- Tagesdiagramm: eine Säule pro Tag, heutiger Tag hervorgehoben.
- Aufschlüsselung je Modell: `Opus 5 · 2,1 M in · 0,4 M out · 4,2 M Cache → 121,40 $`,
  Summenzeile unten.
- Fußnote, die die Rechnung offenlegt (siehe Abschnitt 6).
- Umgesetzt (v2): Standardzeitraum „7 Tage“; „Heute“ ohne Tagesdiagramm; bei 30 Tagen
  Säulen ohne Beschriftung (Tooltip je Tag). Der Stichtag für „Abrechnungsmonat“ steht in
  den Einstellungen (Standard: 1.; in kürzeren Monaten gilt der Monatsletzte). „Abo x $ /
  Monat“ nur für bekannte Pläne (Claude Pro/Max 5×/Max 20×, Codex Plus/Pro).
  Die Modellzeile zeigt „Cache“ als Summe; die Aufteilung Schreiben/Lesen steht im Tooltip.
- **Cache getrennt ausweisen** ist Pflicht: bei Claude Code sind oft ~80 % des Volumens
  Cache-Reads zu einem Bruchteil des Input-Preises. Eine nackte Gesamt-Tokenzahl führt
  in die Irre.

### 3.6 Fußzeile
- Links: Konto-Button — Avatar (Initiale), Name, „2 Konten“, Chevron. Klick öffnet ein
  Menü mit allen Logins. **Ausgegraut, solange eine Claude-Code-Session läuft.**
- Rechts: Zeitstempel (`vor 1 Min.`), Icon-Button „Aktualisieren“ (Kreispfeil) und
  **beschrifteter Button „⚙ Einstellungen“**.
- Beide Buttons gerahmt mit eigener Fläche (26 pt). Der Einstellungs-Button ist
  beschriftet, weil ein reines 14-pt-Icon in der Fußzeile nicht gefunden wird —
  das war ein konkreter Befund aus dem Entwurf.
- Das Zahnrad-Icon braucht echte Zähne (Ring + 8 Zähne). Ein Kreis mit Strahlen
  (Feather-Stil) liest sich als Sonne.

Einstellungen sind auf drei Wegen erreichbar: Zahnrad-Button, Rechtsklick aufs
Menüleisten-Symbol, `⌘,` bei offenem Popover.

---

## 4. Einstellungen

Eigenes Fenster, Abschnitt **Anzeige**:

- Menüleiste: `Nur Icon` | `Icon + %` | `Icon + Balken`
- Angezeigter Wert: `Knappstes Limit` | `Fester Wert …`
- Checkboxen: Zustandsfarbe im Icon verwenden · Eigenes Symbol pro Client ·
  API-Vergleichswert in Geld anzeigen · Bei Anmeldung starten

Weitere Abschnitte: **Anbieter** (je Client an/aus, Reihenfolge), **Mitteilungen**
(Schwellen), **Aktualisierung** (Intervall, mindestens 300 s).

Die Geld-Anzeige ist abschaltbar, weil Tokenzahlen belastbar sind, der Geldbetrag
aber eine Modellrechnung ist.

---

## 5. Mitteilungen

- Schwellen **50 %, 80 %, 90 %** pro Fenster, je Schwelle einmal pro Fenster.
- Zusätzlich „Fenster zurückgesetzt, Kontingent wieder da“.
- Jede Schwelle einzeln abschaltbar.
- Inhalt nennt Rest und Reset, plus die nächstbeste Alternative:
  „Opus-Wochenlimit bei 90 % — Rest ≈ 20 Min. Opus · Reset Mi 09:00. Sonnet liegt bei 54 %.“

---

## 6. Anbieter und Datenquellen

Auf dem Zielrechner bereits vorhanden: `~/.claude`, `~/.codex`, `~/.gemini`,
`~/.copilot`, `~/.cursor`, `~/.antigravity`, `~/.config/opencode`.

| Anbieter | Angezeigte Limits | Quelle | Stufe |
|---|---|---|---|
| **Claude Code** | Session 5 h · Woche 7 d · Opus/Sonnet · Extra-Verbrauch, Guthaben | Schlüsselbund `Claude Code-credentials` (macOS!) bzw. `~/.claude/.credentials.json` → `api.anthropic.com/api/oauth/usage` | v1 |
| **Codex** | Session 5 h · Woche · Code-Review · Credits | `~/.codex/auth.json` → ChatGPT-Usage-Endpunkt | v1 |
| **Gemini CLI / Antigravity** | Tages-Quota Pro & Flash, Thinking-Quota, eingebettetes Claude-5-h-Fenster | `~/.gemini/oauth_creds.json`, `~/.antigravity` Cache-JSON | v3 |
| **GitHub Copilot** | Premium-Requests/Monat, Chat-Quota | `gh`-Token / `~/.copilot` → Copilot-Usage-API | v3 |
| **Cursor** | Monatskontingent, Usage-based-Kosten | Cursor-Anmeldung → Dashboard-API | v3 |
| **Prepaid** (OpenRouter, DeepSeek, Moonshot, Fireworks) | Restguthaben, **echter** Betrag | API-Key aus Umgebungsvariable oder Schlüsselbund → Balance-Endpunkt | v3 |
| **Verbrauch & API-Vergleichswert** | Tokens pro Tag und Modell (in/out/Cache) → Listenpreis-Gegenwert | `~/.claude/projects/**/*.jsonl` bzw. Session-Logs der CLI × mitgelieferte Preistabelle | v2 |

### Wichtige Randbedingungen

- **Die Usage-Endpunkte sind undokumentiert und hart rate-limitiert.** Intervalle unter
  300 s liefern Fehler. Standardintervall daher **300 s**, gemeinsamer Cache über alle
  Konsumenten, bei HTTP 429 die letzten Werte mit Pause-Symbol und Retry-After zeigen
  statt leerer Anzeige.
- **Token nicht selbst erneuern** (Abweichung von claudebar): Ein Refresh rotiert das
  Refresh-Token; ohne Zurückschreiben wäre die CLI danach abgemeldet, und Zurückschreiben
  verbietet „Zugangsdaten nur lesen“. Abgelaufenes Token → Hinweis „Claude Code / Codex
  einmal starten“; die CLI erneuert es selbst.
- Endpunkte (verifiziert 28.09.2026 an claudebar/codexbar und live auf diesem Mac):
  - Claude: `GET https://api.anthropic.com/api/oauth/usage`, Header
    `Authorization: Bearer …`, `anthropic-beta: oauth-2025-04-20`. Antwort:
    `five_hour`/`seven_day`/`seven_day_opus`/`seven_day_sonnet` je `{utilization 0–100,
    resets_at ISO}`, zusätzlich `limits[]` (`kind: weekly_scoped`,
    `scope.model.display_name`, z. B. „Fable“), `extra_usage {is_enabled, monthly_limit,
    used_credits}` in Cent.
  - Codex: `GET https://chatgpt.com/backend-api/wham/usage`, Header
    `Authorization: Bearer <tokens.access_token>`, `chatgpt-account-id: <tokens.account_id>`
    aus `~/.codex/auth.json`. Antwort: `rate_limit.primary_window`/`secondary_window` je
    `{used_percent, reset_at (Unix), limit_window_seconds}` — neuere Konten haben nur ein
    Wochenfenster in `primary_window` —, `code_review_rate_limit`,
    `additional_rate_limits[]`, `credits {has_credits, unlimited, balance}`.
- Claude-Zugangsdaten liegen auf diesem Mac **in beiden Quellen** (Schlüsselbund und
  Datei, beide aktuell). Die App liest beide und nimmt das später ablaufende Token.
  Schlüsselbund über `/usr/bin/security`, weil Claude Code den Eintrag damit anlegt —
  so gibt es keine Rückfrage bei jedem neuen (ad-hoc-signierten) Build.
- **macOS-Unterschied zu Linux:** Claude Code legt die Zugangsdaten in den Schlüsselbund
  (Dienst `Claude Code-credentials`). Eine vorhandene `~/.claude/.credentials.json` kann
  veraltet sein — Schlüsselbund zuerst, Datei als Fallback.

### Verbrauch aus den Logs (verifiziert 28.09.2026)

- **Claude:** Jede Antwort steht mehrfach im Log (eine Zeile je Inhaltsblock), und die
  `output_tokens` wachsen dabei — die **letzte** Zeile ist maßgeblich. Deduplizierung
  global über `message.id:requestId` (fortgesetzte Sessions kopieren den Verlauf). Wie
  ccusage die erste Zeile zu nehmen, zählt hier ~9 % Output zu wenig. Liegt eine Antwort
  zwischen zwei Einlesedurchläufen, wird der Output-Zuwachs nachgetragen.
  Cache-Write getrennt nach `ephemeral_5m` / `ephemeral_1h` (1 h kostet 2 × Input, 5 min 1,25 ×).
- **Codex:** `event_msg`/`token_count` mit kumulierten Summen (`total_token_usage`);
  gezählt wird die Differenz zum vorherigen Stand derselben Datei, Modell aus
  `turn_context`. `input_tokens` enthält die Cache-Reads (`cached_input_tokens`) und wird
  getrennt ausgewiesen. Dateien wandern von `sessions/` nach `archived_sessions/`; der
  Lesestand hängt am Dateinamen.
- Erstes Einlesen auf diesem Mac: 1.823 Dateien / ~3,3 GB in ~36 s, danach inkrementell
  (Offset je Datei, Takt 60 s und beim Öffnen des Popovers). Aggregat in
  `~/Library/Application Support/TokenStats/usage.sqlite`; der Betrag wird erst bei der
  Abfrage aus Tokens × Preistabelle berechnet, eine neue Preistabelle wirkt also sofort.

### Preise: abrufen geht nicht, rechnen schon

- Der Usage-Endpunkt liefert Prozentwerte und Reset-Zeiten — **keine Tokenzahlen und
  keine Beträge.** Für Abo-Verbrauch existiert keine Abrechnung pro Nachricht.
- Tokenzahlen liegen vollständig lokal in `~/.claude/projects/**/*.jsonl`: pro Nachricht
  Input, Output, Cache-Write, Cache-Read, teils mit von Claude Code selbst berechneten
  Kosten. Gleiche Quelle wie `ccusage`.
- Preise kommen aus einer **mitgelieferten Preistabelle mit Datumsstempel**, die bei
  App-Updates aktualisiert wird (`ccusage` nutzt eine gepinnte LiteLLM-Preisliste).
  Kosten = Input × Preis + Output × Preis + Cache-Write + Cache-Read, pro Ereignis mit
  dem Preis von dessen Zeitstempel.
- Deshalb heißt die Zahl **„API-Vergleichswert“**, nicht „Kosten“. Beträge von
  Prepaid-Anbietern sind dagegen echt und werden als `abgerechnet` gekennzeichnet,
  berechnete als `berechnet`.

---

## 7. Architektur

- **Swift + SwiftUI**, Agent-App ohne Dock-Icon (`LSUIElement`), ab macOS 14.
  Symbol über `NSStatusItem` + `NSPopover` statt `MenuBarExtra`, weil `MenuBarExtra`
  keinen Rechtsklick kennt (§2); Inhalte von Popover und Einstellungen sind SwiftUI.
  Kein Framework, keine Laufzeit — ein signiertes `.app`.
- Autostart über `SMAppService` (kein LaunchAgent-Plist von Hand).
- Icon als Template-Symbol; Füllstand ggf. über `variableValue`.
- **Ein Protokoll pro Anbieter** — neue Clients sind eine Datei, die UI bleibt unberührt.
  Genau deshalb decken die Omarchy-Widgets so schnell >20 Agents ab.

```swift
protocol UsageProvider {
    var id: String { get }              // "claude", "codex", …
    var displayName: String { get }
    func isInstalled() -> Bool          // Credential-Quelle vorhanden?
    func fetch() async throws -> ProviderSnapshot
}

struct ProviderSnapshot {
    let account: AccountInfo?           // Name, Plan, weitere Logins
    let windows: [LimitWindow]
    let extras: [ExtraValue]            // Beträge, Guthaben, Kleinwerte
    let fetchedAt: Date
    let staleness: Staleness            // frisch | Cache | rate-limited(retryAfter)
}

struct LimitWindow {
    let name: String                    // "Session", "Woche", "Opus"
    let scopeNote: String?              // "5 h", "7 d, alle Modelle"
    let percent: Double                 // 0…1
    let resetsAt: Date?
    let elapsedFraction: Double?        // für die Pace-Marke
}
```

- **Verbrauchs-Pipeline getrennt vom Limit-Abruf:** JSONL-Dateien werden im Hintergrund
  inkrementell eingelesen (Offset je Datei merken) und pro Tag/Modell aggregiert in einer
  kleinen SQLite-Datei gehalten — nicht bei jedem Öffnen neu geparst.
- Zugangsdaten werden **nur gelesen**, nie kopiert, nie ins App-Verzeichnis gespiegelt.
  Es werden ausschließlich die Anbieter-Endpunkte kontaktiert.
- Account-Wechsel: inaktive Logins im Schlüsselbund verwahren, Backups der letzten 10
  behalten, Wechsel blockieren solange eine Session läuft (PID-Prüfung analog
  `~/.claude/sessions/<pid>.json`).

### Abkürzung, falls schnell ein Ergebnis gebraucht wird
Dasselbe Datenmodell als Skript unter **SwiftBar** — Stunden statt Wochenende, opfert
aber Mitteilungen, Pace-Marke, Verbrauchsseite und Account-Wechsel.

---

## 8. Roadmap

**v1 — Limits für Claude und Codex**
Menüleisten-Icon mit den drei Anzeige-Modi, Popover mit Tabs, Session/Woche/Modell-Limits,
Reset-Zeiten, 300-s-Cache mit Rate-Limit-Behandlung, Einstellungen für die Anzeige.

**v2 — Verbrauchsseite und Mitteilungen**
Umschalter `Limits · Verbrauch`, JSONL-Pipeline + SQLite-Aggregat, Tokens pro Tag und
Modell, API-Vergleichswert mit Preistabelle, Pace-Marke, Schwellen 50/80/90 %.

**v3 — Breite und Konten**
Gemini/Antigravity/Copilot/Cursor, Prepaid-Guthaben als echte Beträge,
Claude-Account-Wechsel, optional Verbrauchs-Sync über iCloud Drive zwischen mehreren Macs.

---

## 9. Offene Punkte

- ~~Codex-Endpunkt~~ und ~~Quelle der Claude-Zugangsdaten~~: geklärt, siehe §6.
- Claude-Guthaben (`/api/oauth/organizations/<org>/prepaid/credits`) ist in v1 noch nicht
  angebunden — zweiter rate-limitierter Aufruf, erst bei Bedarf.
- Ob Gemini-/Antigravity-Quotas ohne Umweg über die CLI-Caches abrufbar sind.
- Aktualisierungsweg der Preistabelle: vorerst mit dem App-Update
  (`Scripts/update-pricing.sh` erzeugt `Resources/pricing.json` aus LiteLLM, Stand im
  Dateikopf). Nachladen zur Laufzeit wäre eine zusätzliche Netzverbindung.
- Signierung/Notarisierung und Verteilweg (direktes `.app`, Homebrew Cask?).
- Prüfen, ob eine bestehende App genügt, bevor gebaut wird: Claude Tracker,
  ClaudeUsageBar, claude-codex-limits, ClaudeMeter, Usagebar, SessionWatcher.
  Eigenbau lohnt vor allem wegen der Multi-Provider-Breite und der Verbrauchsseite.

---

## 10. Quellen

- claudebar — https://github.com/mryll/claudebar (Endpunkt, Token-Refresh, 60-s-Cache, Farbschwellen)
- codexbar — https://github.com/mryll/codexbar (Session, Woche, Code-Review, Credits)
- OAgents — https://github.com/TiniTinyTerminator/OAgents (24 Agents, Panel mit Tabs, Token-Historie, Multi-Machine-Sync)
- omarchy-ai-agents — https://github.com/cbrompton/omarchy-ai-agents (Pace-Formulierung, Opus/Sonnet-Zeilen, Account-Wechsel)
- omarchy-ai-usage-bar — https://github.com/gladimdim/omarchy-ai-usage-bar (Balken-Layout, Limit-Auswahl)
- omarchy-ai-usage — https://github.com/rodrigo-sntg/omarchy-ai-usage
- ai-usagebar — https://github.com/akitaonrails/ai-usagebar
- Omarchy-Handbuch: AI — https://omarchy.org/manual/ai/
- ccusage, Cost Modes — https://ccusage.com/guide/cost-modes
- ccost — https://github.com/cc-friend/ccost
- Claude Code Docs, Manage costs — https://code.claude.com/docs/en/costs
- Vergleichbare macOS-Apps: https://claudetracker.com/ · https://www.claudeusagebar.com/ · https://github.com/ArrivaRUS/claude-codex-limits · https://eddmann.com/ClaudeMeter/
