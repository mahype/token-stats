#!/usr/bin/env python3
"""Stellt einen <item>-Eintrag an den Anfang eines Sparkle-Appcasts.

Aufruf: appcast-add.py APPCAST VERSION DMG_URL LENGTH ED_SIGNATURE NOTES_FILE

Die Notizen (Markdown aus CHANGELOG.md) landen als HTML in <description>, damit Sparkle
sie direkt im Update-Dialog zeigt. Ein releaseNotesLink auf GitHub würde die komplette
Webseite samt Navigation in das kleine Fenster laden.
"""
import html
import re
import sys
from email.utils import formatdate
from xml.etree import ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)
MIN_SYSTEM_VERSION = "14.0"


def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    return re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)", r'<a href="\2">\1</a>', text)


def markdown_to_html(markdown):
    """Nur die Teilmenge aus CHANGELOG.md: Absätze und Listen mit eingerückten Folgezeilen."""
    blocks, current = [], None
    for line in markdown.splitlines() + [""]:
        bullet = re.match(r"[-*]\s+(.*)", line)
        if bullet:
            if current:
                blocks.append(current)
            current = ["li", bullet.group(1)]
        elif line.strip() and current:
            current[1] += " " + line.strip()
        elif line.strip():
            current = ["p", line.strip()]
        elif current:
            blocks.append(current)
            current = None
    out, open_list = [], False
    for tag, text in blocks:
        if tag == "li" and not open_list:
            out.append("<ul>")
            open_list = True
        if tag != "li" and open_list:
            out.append("</ul>")
            open_list = False
        out.append(f"<{tag}>{inline(text)}</{tag}>")
    if open_list:
        out.append("</ul>")
    return "\n".join(out)


def main():
    path, version, url, length, signature, notes_file = sys.argv[1:7]
    tree = ET.parse(path)
    channel = tree.getroot().find("channel")
    if any(item.findtext(f"{{{SPARKLE}}}version") == version for item in channel.findall("item")):
        sys.exit(f"Appcast enthält {version} schon.")

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {version}"
    ET.SubElement(item, "pubDate").text = formatdate(usegmt=True)
    ET.SubElement(item, f"{{{SPARKLE}}}version").text = version
    ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = version
    ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = MIN_SYSTEM_VERSION
    with open(notes_file, encoding="utf-8") as notes:
        ET.SubElement(item, "description").text = markdown_to_html(notes.read())
    ET.SubElement(item, "enclosure", {
        "url": url,
        "length": length,
        "type": "application/octet-stream",
        f"{{{SPARKLE}}}edSignature": signature,
    })

    first_item = next((i for i, e in enumerate(channel) if e.tag == "item"), len(channel))
    channel.insert(first_item, item)
    ET.indent(tree, space="  ")
    tree.write(path, encoding="UTF-8", xml_declaration=True)


if __name__ == "__main__":
    main()
