#!/usr/bin/env bash
# Installs the Token Stats Plasma widget from this checkout into ~/.local/share/plasma/plasmoids.
# Afterwards: system tray settings -> Entries -> "Token Stats" -> Always shown.
# Re-run it to update. Do not use `kpackagetool6 -u` on the installed copy: it deletes the package.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
dest="$HOME/.local/share/plasma/plasmoids/org.tokenstats.claude"
mkdir -p "$dest"
rsync -a --delete "$here/org.tokenstats.claude/" "$dest/"
cp "$here/../../Sources/TokenStats/Resources/pricing.json" "$dest/contents/code/pricing.json"
# add to the tray's item list so it shows up without a trip through the settings
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
panels().forEach(function(p){ p.widgets().forEach(function(w){ if(w.type=="org.kde.plasma.systemtray"){
  w.currentConfigGroup=["General"];
  ["extraItems","knownItems"].forEach(function(k){
    var v=w.readConfig(k); if(v.indexOf("org.tokenstats.claude")<0){ w.writeConfig(k, v+",org.tokenstats.claude") } });
  w.reloadConfig();
}})})' || echo "Could not reach plasmashell; add the widget in the tray settings by hand."
