#!/usr/bin/env bash
# Signiert Sparkles Helfer mit der Developer ID nach und danach die App neu.
# Xcode signiert beim Einbetten nur das Framework selbst; Autoupdate, Updater.app und die
# XPC-Dienste behalten Sparkles Ad-hoc-Signatur ohne Zeitstempel, und die Notarisierung
# lehnt ab. Reihenfolge von innen nach außen, wie in Sparkles Doku („Code Signing“).
#
# Aufruf: sign-sparkle.sh "Token Stats.app" "Developer ID Application"
set -euo pipefail

app="${1:?App-Pfad fehlt}"
identity="${2:?Signatur-Identität fehlt}"
framework="$app/Contents/Frameworks/Sparkle.framework"
sign() { codesign --force --sign "$identity" --options runtime --timestamp "$@"; }

sign "$framework/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$framework/Versions/B/XPCServices/Downloader.xpc"
sign "$framework/Versions/B/Autoupdate"
sign "$framework/Versions/B/Updater.app"
sign "$framework"
sign --preserve-metadata=entitlements "$app"
