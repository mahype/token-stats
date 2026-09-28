#!/usr/bin/env bash
# Veröffentlicht das DMG aus `make release`: Tag, GitHub-Release und Eintrag im
# Sparkle-Appcast (Branch gh-pages, ausgeliefert über GitHub Pages).
#
# Der Appcast-Eintrag kommt erst nach dem Release, damit er nie auf einen Download
# zeigt, den es noch nicht gibt. Signiert wird mit dem Ed25519-Schlüssel im
# Schlüsselbund (Konto „token-stats“, siehe CLAUDE.md).
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=mahype/token-stats
FEED=https://mahype.github.io/token-stats/appcast.xml
SIGN_UPDATE=build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update

version="$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)"
tag="v$version"
dmg="build/Token-Stats-$version.dmg"

fail() { echo "Fehler: $*" >&2; exit 1; }

[[ -f "$dmg" ]] || fail "$dmg fehlt – erst make release."
xcrun stapler validate -q "$dmg" || fail "$dmg ist nicht notarisiert."
[[ -x "$SIGN_UPDATE" ]] || fail "$SIGN_UPDATE fehlt – erst make build."
[[ -z "$(git status --porcelain)" ]] || fail "Arbeitsverzeichnis nicht sauber."
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && fail "Tag $tag gibt es schon."

# Abschnitt „## X.Y.Z“ aus CHANGELOG.md, ohne führende Leerzeilen.
notes="$(awk -v v="$version" '/^## /{p = ($2 == v); next} p' CHANGELOG.md | sed '/./,$!d')"
[[ -n "$notes" ]] || fail "Kein Abschnitt „## $version“ in CHANGELOG.md."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
printf '%s\n' "$notes" > "$work/notes.md"

# Signatur zuerst: Fehlt der Schlüssel, soll noch nichts veröffentlicht sein.
signature="$("$SIGN_UPDATE" --account token-stats "$dmg")"
ed_signature="$(sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p' <<<"$signature")"
length="$(sed -nE 's/.*length="([0-9]+)".*/\1/p' <<<"$signature")"
[[ -n "$ed_signature" && -n "$length" ]] || fail "sign_update lieferte: $signature"

sha="$(shasum -a 256 "$dmg" | cut -d' ' -f1)"
cat > "$work/release.md" <<EOF
$notes

## Installation

\`$(basename "$dmg")\` unten herunterladen, öffnen, **Token Stats** auf **Programme** ziehen und starten.
Bestehende Installationen ab 0.2.0 aktualisieren sich selbst.

macOS 14 oder neuer, Universal (Apple Silicon und Intel).

SHA-256: \`$sha\`
EOF

git push origin HEAD
git tag -a "$tag" -m "Token Stats $version"
git push origin "$tag"
gh release create "$tag" "$dmg" --repo "$REPO" --title "Token Stats $version" --notes-file "$work/release.md"

# Appcast auf gh-pages fortschreiben; beim ersten Mal den Branch anlegen.
remote="$(git remote get-url origin)"
if git ls-remote --exit-code --heads origin gh-pages >/dev/null; then
    git clone --quiet --depth 1 --branch gh-pages "$remote" "$work/pages"
else
    git init --quiet --initial-branch gh-pages "$work/pages"
    git -C "$work/pages" remote add origin "$remote"
    touch "$work/pages/.nojekyll"
    cat > "$work/pages/appcast.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Token Stats</title>
    <link>$FEED</link>
    <language>de</language>
  </channel>
</rss>
EOF
fi

python3 Scripts/appcast-add.py "$work/pages/appcast.xml" "$version" \
    "https://github.com/$REPO/releases/download/$tag/$(basename "$dmg")" \
    "$length" "$ed_signature" "$work/notes.md"
git -C "$work/pages" add -A
git -C "$work/pages" commit --quiet -m "Appcast: $version"
git -C "$work/pages" push --quiet origin gh-pages

# GitHub Pages einmalig für gh-pages einschalten. Oft hat GitHub das beim ersten Push auf
# gh-pages schon selbst getan und antwortet dann mit 409.
if ! gh api "repos/$REPO/pages" >/dev/null 2>&1; then
    gh api -X POST "repos/$REPO/pages" -f 'source[branch]=gh-pages' -f 'source[path]=/' >/dev/null 2>&1 ||
        gh api "repos/$REPO/pages" >/dev/null || fail "GitHub Pages ließ sich nicht einschalten."
fi

echo "Veröffentlicht: $tag · Feed $FEED (GitHub Pages braucht ein bis zwei Minuten)"
