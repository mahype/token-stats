#!/usr/bin/env bash
# Packt eine gebaute App in ein DMG mit Verknüpfung auf /Programme zum Hineinziehen.
# Aufruf: Scripts/make-dmg.sh <App> <Ziel.dmg>
set -euo pipefail
APP=$1
DMG=$2

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$(basename "$APP")"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -quiet -volname "Token Stats" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
echo "$DMG"
