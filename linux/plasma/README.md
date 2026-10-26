# Token Stats for KDE Plasma 6

Native Plasma widget (QML + a small Python backend). Same idea as the macOS and Windows apps:
Claude Code limits with a pace mark, plus token usage per day and model with the API comparison
value. Being a real applet, Plasma positions the popup above the tray icon and highlights the
icon while it is open, like the clipboard or Bluetooth popups. Colours follow the Plasma theme.

**Scope:** Claude Code only (no Codex, Antigravity or Ollama yet). Needs Plasma 6, `python3`
and `rsync`. Same data sources as the other versions:

- Limits: `GET https://api.anthropic.com/api/oauth/usage` with the login from
  `~/.claude/.credentials.json` (read only, the token is never refreshed or written). The last
  good values are cached in `~/.cache/tokenstats/`, so HTTP 429 or being offline keeps them.
- Usage: `~/.claude/projects/**/*.jsonl`, last message per id, cache writes split by 5 m / 1 h.
- Prices: [`Sources/TokenStats/Resources/pricing.json`](../../Sources/TokenStats/Resources/pricing.json),
  copied next to the backend on install, so `Scripts/update-pricing.sh` plus a re-install updates it.

## Install

```sh
linux/plasma/install.sh
```

Then open the system tray settings, **Entries**, and set "Token Stats" to **Always shown**. The
script already adds it to the tray's item list; re-run it to update. It starts with the session.

Test without the panel: `plasmawindowed org.tokenstats.claude`.

## Layout

- `contents/code/backend.py` prints one JSON document (limits, plan, 31 days of usage); the
  widget runs it every 5 minutes through the `executable` data engine.
- `contents/code/util.js` formatting and aggregation; `contents/ui/*.qml` the views.

## Limits of this version

- No settings page; the refresh interval is a constant in `main.qml`.
- Do not update with `kpackagetool6 -u` on the installed copy, it deletes the package.
