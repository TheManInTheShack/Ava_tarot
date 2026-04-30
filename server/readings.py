import json
from pathlib import Path

READINGS_FILE = Path(__file__).parent.parent / "Data" / "readings.json"


def _load() -> list:
    if not READINGS_FILE.exists():
        return []
    with open(READINGS_FILE, encoding="utf-8") as f:
        return json.load(f)


def _save(readings: list) -> None:
    with open(READINGS_FILE, "w", encoding="utf-8") as f:
        json.dump(readings, f, indent=2, ensure_ascii=False)


def list_readings() -> list:
    return _load()


def get_reading(reading_id: str) -> dict | None:
    for r in _load():
        if r.get("reading_id") == reading_id:
            return r
    return None


def upsert_reading(reading: dict) -> dict:
    readings = _load()
    for i, r in enumerate(readings):
        if r.get("reading_id") == reading.get("reading_id"):
            readings[i] = reading
            _save(readings)
            return reading
    readings.append(reading)
    _save(readings)
    return reading


def delete_reading(reading_id: str) -> bool:
    readings = _load()
    filtered = [r for r in readings if r.get("reading_id") != reading_id]
    if len(filtered) == len(readings):
        return False
    _save(filtered)
    return True
