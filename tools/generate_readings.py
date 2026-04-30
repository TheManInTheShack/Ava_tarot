"""
generate_readings.py  —  synthetic reading generator for Ava Tarot

Usage:
    python tools/generate_readings.py [count] [--layout three-card|ava-celtic-cross|mixed]

Defaults: count=50, layout=mixed
Writes to the Godot user:// path on Windows.
"""

import json
import random
import sys
import time
import os
from pathlib import Path

# ── paths ─────────────────────────────────────────────────────────────────────
REPO_ROOT   = Path(__file__).resolve().parent.parent
CARDS_PATH  = REPO_ROOT / "Data" / "cards.json"
LAYOUTS_PATH = REPO_ROOT / "Data" / "layouts.json"
OUTPUT_PATH = Path(os.environ["APPDATA"]) / "Godot" / "app_userdata" / "Ava Tarot" / "readings.json"

# ── load data ─────────────────────────────────────────────────────────────────
with open(CARDS_PATH, encoding="utf-8") as f:
    cards_data = json.load(f)

with open(LAYOUTS_PATH, encoding="utf-8") as f:
    layouts_raw = json.load(f)["layouts"]

cards_by_id = cards_data["nodes"]  # already keyed by card_id
layouts_by_id = {l["layout_id"]: l for l in layouts_raw}

COURT_NUMBERS = {11, 12, 13, 14}

# ── helpers ───────────────────────────────────────────────────────────────────
def is_reversed() -> bool:
    return random.random() < 0.35          # ~35% reversal rate

def card_orientation(slot_rotation: int, reversed_: bool) -> str:
    crossing = abs(slot_rotation % 180) > 22
    if crossing:
        return "crosses_reversed" if reversed_ else "crosses_upright"
    return "placed_reversed" if reversed_ else "placed_upright"

def is_court(card_id: str) -> bool:
    if card_id.startswith("MA-"):
        return False
    parts = card_id.split("-")
    return len(parts) >= 2 and int(parts[1]) in COURT_NUMBERS

def compute_metrics(placements: list) -> dict:
    total = float(len(placements))
    if total == 0:
        return {}
    majors = suits = reversed_count = courts = 0
    suit_counts = {"Wands": 0, "Cups": 0, "Swords": 0, "Pentacles": 0}
    for p in placements:
        data = cards_by_id.get(p["card_id"], {})
        if data.get("arcana") == "Major":
            majors += 1
        suit = data.get("suit")
        if isinstance(suit, str) and suit in suit_counts:
            suit_counts[suit] += 1
        if p["orientation"].endswith("_reversed"):
            reversed_count += 1
        if is_court(p["card_id"]):
            courts += 1
    return {
        "major_ratio":     majors              / total,
        "wands_frac":      suit_counts["Wands"]     / total,
        "cups_frac":       suit_counts["Cups"]      / total,
        "swords_frac":     suit_counts["Swords"]    / total,
        "pents_frac":      suit_counts["Pentacles"] / total,
        "inversion_ratio": reversed_count      / total,
        "court_ratio":     courts              / total,
    }

def generate_reading(layout_id: str, reading_index: int) -> dict:
    layout = layouts_by_id[layout_id]
    all_ids = list(cards_by_id.keys())
    random.shuffle(all_ids)
    drawn = all_ids[:len(layout["slots"])]

    placements = []
    for slot, card_id in zip(layout["slots"], drawn):
        rev = is_reversed()
        placements.append({
            "slot_id":    slot["slot_id"],
            "slot_label": slot["label"],
            "card_id":    card_id,
            "card_name":  cards_by_id[card_id].get("name", card_id),
            "orientation": card_orientation(slot.get("rotation", 0), rev),
        })

    # stable unique id: timestamp ms + index
    ts_ms = int(time.time() * 1000) + reading_index
    from datetime import datetime, timedelta
    # spread timestamps back over the past 60 days for variety
    days_back = random.randint(0, 60)
    dt = datetime.now() - timedelta(days=days_back,
                                    hours=random.randint(0, 23),
                                    minutes=random.randint(0, 59))
    ts_str = dt.strftime("%Y-%m-%dT%H:%M:%S")
    date_str = dt.strftime("%Y%m%d")

    return {
        "reading_id": f"reading-{date_str}-{ts_ms % 1000000}",
        "layout_id":  layout_id,
        "timestamp":  ts_str,
        "querent":    "",
        "notes":      "",
        "placements": placements,
        "metrics":    compute_metrics(placements),
    }

# ── main ──────────────────────────────────────────────────────────────────────
def main():
    args = sys.argv[1:]
    count = 50
    layout_filter = "mixed"

    for arg in args:
        if arg.isdigit():
            count = int(arg)
        elif arg.startswith("--layout="):
            layout_filter = arg.split("=", 1)[1]
        elif arg in ("three-card", "ava-celtic-cross", "mixed"):
            layout_filter = arg

    if layout_filter == "mixed":
        layout_pool = ["three-card", "ava-celtic-cross"]
    else:
        layout_pool = [layout_filter]

    # load existing
    existing = []
    if OUTPUT_PATH.exists():
        with open(OUTPUT_PATH, encoding="utf-8") as f:
            try:
                existing = json.load(f)
            except json.JSONDecodeError:
                existing = []

    new_readings = []
    for i in range(count):
        layout_id = random.choice(layout_pool)
        new_readings.append(generate_reading(layout_id, i))

    all_readings = existing + new_readings
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(all_readings, f, indent="\t", ensure_ascii=False)

    print(f"Generated {count} readings ({layout_filter}). Total in file: {len(all_readings)}")

if __name__ == "__main__":
    main()
