"""
Download all 78 Rider-Waite-Smith card images from Wikimedia Commons.
Images are public domain (1909, artist Pamela Colman Smith).

Resizes each card to 420x720 (3x the Godot card slot of 140x240) and saves
with the project's naming convention (e.g. MA-00-The-Fool.png).

Usage:
    python tools/fetch_rider_waite.py
"""

import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path

try:
    from PIL import Image
    import io
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    print("Pillow not installed — images will be saved at full resolution.")
    print("Run: pip install pillow")

CARD_W, CARD_H = 420, 720
OUT_DIR = Path(__file__).parent.parent / "Assets" / "Images"
CARDS_JSON = Path(__file__).parent.parent / "Data" / "cards.json"

WIKIMEDIA_URL = "https://commons.wikimedia.org/wiki/Special:FilePath/{filename}"

HEADERS = {
    "User-Agent": "ava-tarot-art-fetcher/1.0 (personal project; contact thmanintheshack@gmail.com)"
}


def card_filename(card_id: str, card_name: str) -> str:
    """Convert card name to our project's image filename convention."""
    safe = card_name.replace(" ", "-")
    return f"{card_id}-{safe}.png"


def wikimedia_filename(card_name: str) -> str:
    return f"{card_name} (Rider-Waite Smith tarot deck).png"


def download_and_save(card_id: str, card_name: str) -> bool:
    wm_file = wikimedia_filename(card_name)
    url = WIKIMEDIA_URL.format(filename=urllib.parse.quote(wm_file))
    out_path = OUT_DIR / card_filename(card_id, card_name)

    if out_path.exists():
        print(f"  skip (exists): {out_path.name}")
        return True

    try:
        req = urllib.request.Request(url, headers=HEADERS)
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = resp.read()

        if HAS_PIL:
            img = Image.open(io.BytesIO(data))
            img = img.resize((CARD_W, CARD_H), Image.LANCZOS)
            img.save(out_path, optimize=True)
        else:
            out_path.write_bytes(data)

        print(f"  ok: {out_path.name}")
        return True

    except Exception as e:
        print(f"  FAILED {card_name}: {e}")
        return False


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    with open(CARDS_JSON, encoding="utf-8") as f:
        data = json.load(f)

    cards = sorted(data["nodes"].items(), key=lambda kv: (kv[1]["arcana"] != "Major", kv[0]))
    total = len(cards)
    failed = []

    print(f"Fetching {total} cards → {OUT_DIR}\n")

    for i, (card_id, node) in enumerate(cards, 1):
        name = node["name"]
        print(f"[{i:02d}/{total}] {card_id}: {name}")
        ok = download_and_save(card_id, name)
        if not ok:
            failed.append((card_id, name))
        time.sleep(0.5)  # be polite to Wikimedia

    print(f"\nDone. {total - len(failed)}/{total} succeeded.")
    if failed:
        print("Failed:")
        for card_id, name in failed:
            print(f"  {card_id}: {name}")


if __name__ == "__main__":
    main()
