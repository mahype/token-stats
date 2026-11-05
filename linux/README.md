# Token Stats for Linux

Two variants with the same data sources, calculation and price table
([`Sources/TokenStats/Resources/pricing.json`](../Sources/TokenStats/Resources/pricing.json)).
Claude Code only for now.

| Desktop | Use | Status |
|---|---|---|
| KDE Plasma 6 | [`plasma/`](plasma/README.md): native widget | tested |
| Anything else with StatusNotifier tray support | [`gtk/`](gtk/README.md): Python/GTK3 | tested on Plasma 6 only |

Expectations for the GTK variant on other desktops (not tested):

- **GNOME:** needs the "AppIndicator and KStatusNotifierItem Support" extension for a tray icon.
  GNOME has no layer-shell, so the window is a normal window, not anchored to the icon.
- **Sway, Hyprland, waybar:** layer-shell works, so the window should anchor to the panel. The
  display scale is read with `kscreen-doctor` and falls back to 1, so fractional scaling will
  misplace it.
- **XFCE, Cinnamon, MATE (X11):** the icon should appear through StatusNotifier, the window has
  no fixed position.

Reports and fixes for other desktops are welcome.
