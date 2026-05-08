#!/usr/bin/env python3
"""
Update docs/appcast.xml with a new release item.

Usage:
    update_appcast.py VERSION TAG ED_SIGNATURE LENGTH PUBDATE

Reads CHANGELOG.md to extract release notes for the version (## [x.y.z] section).
Writes release notes to docs/release-notes/<VERSION>.md.
Inserts/replaces a Sparkle <item> in docs/appcast.xml for that version.
"""

from __future__ import annotations

import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = os.environ.get("GITHUB_REPOSITORY", "onurdilmen/pomodoro-menubar")
PAGES_BASE = "https://onurdilmen.github.io/pomodoro-menubar"


def extract_changelog(version: str) -> str:
    """Pull the body of `## [VERSION]` from CHANGELOG.md, or a short fallback."""
    path = Path("CHANGELOG.md")
    if not path.exists():
        return f"Release v{version}"

    text = path.read_text()
    pattern = re.compile(
        rf"^##\s*\[{re.escape(version)}\][^\n]*\n(.*?)(?=^##\s*\[|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(text)
    if not match:
        return f"Release v{version}"
    return match.group(1).strip()


def render_item(
    version: str,
    tag: str,
    ed_signature: str,
    length: str,
    pubdate: str,
    notes_url: str,
) -> str:
    dmg_url = (
        f"https://github.com/{REPO}/releases/download/{tag}/Pomodoro-{version}.dmg"
    )
    return (
        "        <item>\n"
        f"            <title>Pomodoro {version}</title>\n"
        f"            <pubDate>{pubdate}</pubDate>\n"
        f"            <sparkle:version>{version}</sparkle:version>\n"
        f"            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>\n"
        f"            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>\n"
        f"            <sparkle:releaseNotesLink>{notes_url}</sparkle:releaseNotesLink>\n"
        f'            <enclosure url="{dmg_url}" sparkle:edSignature="{ed_signature}" length="{length}" type="application/octet-stream" />\n'
        "        </item>"
    )


def upsert_item(appcast_path: Path, version: str, item_xml: str) -> None:
    text = appcast_path.read_text()

    existing_pattern = re.compile(
        rf"\s*<item>(?:(?!<item>)[\s\S])*?<sparkle:version>{re.escape(version)}</sparkle:version>[\s\S]*?</item>",
        re.MULTILINE,
    )
    if existing_pattern.search(text):
        new_text = existing_pattern.sub("\n" + item_xml, text, count=1)
    else:
        # Insert after </language> for ordered placement; if missing, before </channel>
        if "</language>" in text:
            new_text = text.replace("</language>", "</language>\n" + item_xml, 1)
        else:
            new_text = text.replace("</channel>", item_xml + "\n    </channel>", 1)
    appcast_path.write_text(new_text)


def main() -> int:
    if len(sys.argv) < 5:
        print(
            "Usage: update_appcast.py VERSION TAG ED_SIGNATURE LENGTH [PUBDATE]",
            file=sys.stderr,
        )
        return 2

    version = sys.argv[1]
    tag = sys.argv[2]
    ed_signature = sys.argv[3]
    length = sys.argv[4]
    pubdate = (
        sys.argv[5]
        if len(sys.argv) > 5
        else datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
    )

    notes = extract_changelog(version)
    notes_dir = Path("docs/release-notes")
    notes_dir.mkdir(parents=True, exist_ok=True)
    notes_path = notes_dir / f"{version}.md"
    notes_path.write_text(notes + "\n")

    notes_url = f"{PAGES_BASE}/release-notes/{version}.md"
    item = render_item(version, tag, ed_signature, length, pubdate, notes_url)

    appcast_path = Path("docs/appcast.xml")
    upsert_item(appcast_path, version, item)

    print(
        f"Updated docs/appcast.xml and docs/release-notes/{version}.md for v{version}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
