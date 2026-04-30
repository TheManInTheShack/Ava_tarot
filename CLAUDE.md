# CLAUDE.md — Ava Tarot

Read this first in any new session. It reflects the current built state.

---

## What This Is

A digital tarot card table built in Godot 4, exported as a PWA for phone use (portrait, touch). Primary user is the owner's sister, who does readings for clients. **It is a tool, not a game** — no interpretation logic, just cards and layouts.

---

## Current State (as of April 2026)

The Godot project is fully functional. The Flask backend is scaffolded but not yet deployed. Next immediate milestone: deploy to DigitalOcean droplet.

### What works
- Full 78-card deck in `Data/cards.json` with 286 graph edges
- Drag, tap-to-select, long-press-to-flip (face-down: 0.55s, face-up: 1.1s)
- Card info panel: works for both face-up and face-down cards; shows name/arcana/keywords/graph neighbors; rotate (< >) and flip buttons; rotation works pre-flip so cards can be set reversed before revealing
- Three layouts: Three-Card, Celtic Cross (classic), Ava's Celtic Cross — selectable via top dropdown
- Slot system: snap-to-slot (80px radius), slot labels above/card labels below, superposition (second card on same slot) tracked separately
- Floating card name label suppressed when card is in a slot (slot labels take over)
- Next Slot button: deals and places cards sequentially into layout slots
- Deck manager: shuffle, deal, next slot, remaining count
- Save Reading: captures all face-up slotted cards to `user://readings.json` with placement + metrics; duplicate guard (same layout + same cards blocks re-save)
- Reading History panel: full-screen overlay, sorted newest-first, color fingerprint swatch per reading, aggregate stats header
- Camera pan and pinch-zoom
- Z-ordering: interacted card always on top; clicking exposed edge of buried card cycles z-order
- Card sprites scale to fit any source image resolution

### What is not yet done
- Backend not deployed (server/ is written and tested locally, not running on droplet)
- No Godot WebSocket client (role-based guest/admin mode not wired up)
- No card art (placeholder back image at Assets/Images/card_back_default.png, 420×720)
- No art-pack switching
- Python vault→cards.json export script not written (cards.json maintained manually)
- PWA not deployed

---

## Repo Layout

```
ava_tarot/
├── CLAUDE.md                  ← you are here
├── project.godot              ← Godot 4, GL Compatibility, 1080×1920 viewport, 540×960 dev window
├── Main.tscn / Main.gd        ← orchestrator: layout, deck, card spawning, camera, UI wiring
├── CameraController.gd        ← pan (one-finger on empty table) + pinch-zoom
├── Cards/
│   ├── CardBase.tscn/.gd      ← core card: drag/flip/select, Sprite2D auto-scaled to 140×240
│   ├── Major Arcana/          ← 22 vault .md files (MA-00 through MA-21)
│   └── Minor Arcana/
│       ├── Wands/             ← 14 vault .md files
│       ├── Cups/              ← 14 vault .md files
│       ├── Swords/            ← 14 vault .md files
│       └── Pentacles/         ← 14 vault .md files
├── Layouts/
│   ├── LayoutBase.gd          ← slot snapping, CardLabel1/2 below each slot, superposition tracking
│   ├── LayoutBase.tscn        ← base scene instanced by all layout scenes
│   ├── ThreeCard.tscn
│   ├── CelticCross.tscn       ← classic 10-slot layout
│   └── AvaCelticCross.tscn    ← Ava's preferred variant (relabeled positions, adjusted spacing)
├── UI/
│   ├── CardInfo.tscn/.gd      ← card detail panel: works face-up and face-down; rotate/flip buttons
│   ├── DeckManager.tscn/.gd   ← shuffle, deal, next slot, save, history buttons
│   ├── LayoutSelector.tscn/.gd ← top-bar dropdown, populates from layouts.json
│   └── ReadingHistory.tscn/.gd ← full-screen reading log; color fingerprint; aggregate stats
├── Autoloads/
│   ├── DeckState.gd           ← deck order, draw, is_reversed; shuffle excludes in-play cards
│   └── GraphDB.gd             ← loads cards.json at runtime; get_node_data / get_neighbors
├── Data/
│   ├── cards.json             ← 78 nodes, 286 edges — source of truth for card data
│   └── layouts.json           ← layout definitions with slot positions and metadata
├── Meta/
│   ├── Card-Schema.md         ← vault card frontmatter schema
│   ├── Graph-Index.md         ← all 78 nodes with Obsidian links and edge counts
│   └── Reading-Model.md       ← data model design: readings, scenarios, phase space
├── Assets/Images/             ← card_back_default.png (420×720 placeholder)
├── tools/
│   ├── fetch_rider_waite.py   ← image fetch utility
│   └── generate_readings.py   ← synthetic reading generator (usage: python tools/generate_readings.py [count] [layout])
└── server/                    ← Flask backend (scaffolded, not yet deployed)
    ├── wsgi.py                ← gunicorn entry point
    ├── app.py                 ← Flask + flask-sock init
    ├── auth.py                ← bcrypt login, @login_required decorator
    ├── sessions.py            ← in-memory sessions, 5h TTL, background cleanup
    ├── routes.py              ← REST API: login, session, card/edge CRUD, reading CRUD
    ├── readings.py            ← file-backed reading CRUD on Data/readings.json
    ├── sockets.py             ← WebSocket: /ws/admin/<id> and /ws/guest/<id>?token=
    ├── requirements.txt
    ├── hash_password.py       ← run to generate bcrypt hashes for .env
    └── .env.example           ← ADMIN_PASSWORD_HASH, DEV_PASSWORD_HASH, FLASK_SECRET, WHEREBY_ROOM_URL
```

---

## Key Architecture Decisions

| Decision | Detail |
|----------|--------|
| Godot 4 HTML5 export | PWA, no app store |
| 1080×1920 viewport, canvas_items stretch | Fills any phone screen correctly |
| Node2D cards (not Control) | Free spatial placement, not UI flow |
| Area2D collision input | Cards handle their own drag/tap/flip |
| Z-index counter in Main.gd | Monotonically increasing; interacted card always on top |
| `_higher_card_at_mouse()` | Checks if higher card's bounds actually contain the mouse (not just rect overlap) |
| `_draw()` + `draw_set_transform` | World-space horizontal card label; Control/Camera2D mismatch is why Label nodes don't work here |
| `in_slot` flag on CardBase | Suppresses `_draw()` label when card is in a layout slot |
| LayoutBase creates slot labels at runtime | `_ready()` adds CardLabel1/CardLabel2 Label nodes below each Marker2D; `label_y_offset` metadata overrides position (used by crossing slot) |
| Superposition tracking | `assigned_card` = primary, `superposition_card` = second card on same slot; drag-away promotes super to primary |
| cards.json at runtime | GraphDB autoload; vault markdown is the human-editable source |
| Reading capture | `user://readings.json` (Godot app data); metrics vector: major_ratio, suit fracs, inversion_ratio, court_ratio |
| Reading fingerprint color | HSV: H=dominant suit element, S=major arcana density, V dims with inversion |
| Flask + flask-sock + gevent | Lightweight WebSocket backend, same pattern as cholt project |
| Two admin users | `admin` (sister), `dev` (owner) — separate bcrypt hashes in env vars |
| Whereby for voice/video | Persistent room URL in env var, returned alongside guest_url on session start |

---

## LayoutBase Slot System

Each Marker2D slot in a layout scene has these metadata keys:

| Key | Type | Purpose |
|-----|------|---------|
| `slot_id` | int | ordering (1-based) |
| `label` | String | display name (shown in static SlotLabel above slot) |
| `meaning` | String | interpretive meaning (informational only) |
| `slot_rotation` | float | card rotation when placed (0 or 90) |
| `force_reversed` | bool | forces is_reversed=true on place |
| `assigned_card` | CardBase | primary card in slot (set at runtime) |
| `superposition_card` | CardBase | second card stacked on slot (set at runtime) |
| `label_y_offset` | float | offsets CardLabel1/2 downward (used by crossing slot to avoid overlap) |

`LayoutBase._ready()` adds `CardLabel1` and `CardLabel2` Label nodes (white, 18pt, z=200) as children of each Marker2D. These update reactively via `card_flipped`, `card_drag_started`, and `card_orientation_changed` signals.

---

## Reading Data Format

Saved to `user://readings.json` (Windows: `%APPDATA%\Godot\app_userdata\Ava Tarot\readings.json`):

```json
{
  "reading_id": "reading-20260426-123456",
  "layout_id": "ava-celtic-cross",
  "timestamp": "2026-04-26T19:00:00",
  "querent": "",
  "notes": "",
  "placements": [
    { "slot_id": 1, "slot_label": "The Querent", "card_id": "MA-13",
      "card_name": "Death", "orientation": "placed_upright" }
  ],
  "metrics": {
    "major_ratio": 0.3, "wands_frac": 0.1, "cups_frac": 0.2,
    "swords_frac": 0.2, "pents_frac": 0.2,
    "inversion_ratio": 0.3, "court_ratio": 0.2
  }
}
```

Orientation values: `placed_upright`, `placed_reversed`, `crosses_upright`, `crosses_reversed`.
Only face-up, slotted cards are captured. Duplicate guard checks last saved reading.

---

## Session / Backend Design

- Admin logs in → POST /api/session/start → gets `guest_url` (tarot link) + `call_url` (Whereby)
- Guest URL format: `?role=guest&session=<id>&token=<token>`
- Guest connects to `/ws/guest/<id>?token=<token>` — read-only, receives state broadcasts
- Admin connects to `/ws/admin/<id>` — sends `{"type":"state","payload":{...}}` to mirror to guest
- Session expires: admin disconnect, explicit /api/session/end, or 5-hour TTL
- One active session per admin user at a time
- Card data editable via REST: GET/PUT/POST /api/cards, GET/POST/DELETE /api/edges
- Readings: GET/POST `/api/readings`, GET/PUT/DELETE `/api/readings/<reading_id>`

---

## Godot Project Settings

| Setting | Value |
|---------|-------|
| Renderer | GL Compatibility |
| Viewport | 1080 × 1920 |
| Dev window override | 540 × 960 |
| Stretch mode | canvas_items |
| Emulate mouse from touch | ON |
| Autoloads | DeckState, GraphDB |

---

## Known GDScript / Godot Gotchas (already fixed, will recur)

- **JSON null fields**: `.get("key", "")` returns `null` (not `""`) when key exists with null value. Pattern: `var v = data.get("key"); var s: String = v if v is String else ""`
- **`arcana` field value**: is `"Major"` in cards.json, not `"Major Arcana"` — check `== "Major"`
- **`slot_id` type**: Godot stores metadata as-typed; old .tscn files may produce float. Always cast: `int(slot.get_meta("slot_id", 0))`
- **`remove_meta` not `erase_meta`**: Godot 4 uses `Node.remove_meta()` — `erase_meta` doesn't exist
- **`Array[String]`** assignment from untyped Array: use `.assign()` not `= arr.duplicate()`
- **`to_local()` return type**: needs explicit `: Vector2` annotation for type inference
- **Label (Control) as child of Marker2D (Node2D)**: works — `position` is in parent's local 2D space; z_index must be set explicitly (labels default to 0, cards may be higher)
- **`_draw()` world-space text**: use `draw_set_transform(anchor_screen, -rotation, Vector2.ONE)` to keep text horizontal regardless of card rotation

---

## Deployment Target

DigitalOcean droplet, nginx + gunicorn, same pattern as the `cholt` project in `dev/projects/cholt/`. Godot PWA export goes to a static host. Note: Netlify requires COOP/COEP headers for SharedArrayBuffer — check export settings.
