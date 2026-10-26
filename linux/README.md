# Token Stats for Linux

Tray widget for Linux, same idea as the macOS and Windows apps: Claude Code limits with a
pace mark, plus token usage per day and model with the API comparison value. Written in
Python/GTK3, a single file.

**Scope:** Claude Code only (no Codex, Antigravity or Ollama yet). Tested on KDE Plasma 6 on
Wayland. Same data sources as the other versions:

- Limits: `GET https://api.anthropic.com/api/oauth/usage` with the login from
  `~/.claude/.credentials.json` (read only, the token is never refreshed or written).
- Usage: `~/.claude/projects/**/*.jsonl`, last message per id, cache writes split by 5 m / 1 h.
- Prices: [`Sources/TokenStats/Resources/pricing.json`](../Sources/TokenStats/Resources/pricing.json),
  so `Scripts/update-pricing.sh` updates all versions.

## Install and run

Debian/Ubuntu:

```sh
sudo apt install python3-gi python3-gi-cairo gir1.2-gtk-3.0 gir1.2-gtklayershell-0.1 libgtk-layer-shell0
python3 linux/tokenstats.py
```

Run it from a checkout, because it reads the price table from `Sources/`. For autostart put a
`.desktop` file in `~/.config/autostart/` with `Exec=python3 /path/to/linux/tokenstats.py`.

## How it behaves

- Registers its own StatusNotifierItem (no menu): a left click opens the window, centred above
  the icon. The icon is a ring in the state colour (green, yellow from 80 %, red from 100 %)
  with the percentage inside.
- The window is a [layer-shell](https://github.com/wmww/gtk-layer-shell) surface, so it sits
  directly above (or below) the panel and cannot be dragged. Esc, a click outside or another
  click on the icon closes it. Without `gir1.2-gtklayershell-0.1` it falls back to a normal
  window.
- Plasma reports the icon position in physical pixels and sends every click twice. The script
  converts with the scale from `kscreen-doctor -j` and ignores calls within 400 ms.
- Refreshes every 5 minutes. On HTTP 429 the last values stay and a note appears.

## Limits of this version

- No settings window; the refresh interval is a constant at the top of the file.
- Plasma highlights the icon of its own applets while their popup is open. A plain
  StatusNotifierItem does not get that.
- Only the first screen is considered when positioning.
