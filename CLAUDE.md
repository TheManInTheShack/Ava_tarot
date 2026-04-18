# CLAUDE.md — Ava Tarot Project Handoff

This file is read automatically by Claude Code at session start. It contains everything needed to continue development without prior conversation context.

---

## What This Is

**Ava Tarot** is an interactive digital tarot deck built in Godot 4, deployed as a PWA (web app installable to phone home screen). It is a **tool, not a game** — a digital card table where the user can shuffle, deal, flip, and arrange tarot cards in standard spread layouts or freeform.

It is intended for use on a phone (portrait orientation, touch drag-and-drop). The primary user is the owner's sister.

---

## What This Is Not

- Not a game engine project with game logic
- Not a native Android/iOS app (no app store, no Xcode, no Google Play)
- Not an AI reading tool (no interpretation logic — just the cards and layouts)

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Knowledge graph / content | Obsidian vault (Markdown files in this repo) |
| Interactive card engine | Godot 4.x — GDScript |
| Deployment | Godot HTML5 export → PWA |
| Hosting | Netlify (preferred) or itch.io for testing |
| Card metadata pipeline | Python script (TBD) — parses vault MD → `cards.json` for Godot |

---

## Active Branch

```
claude/setup-obsidian-godot-cards-1mDbC
```

All work goes on this branch. Do not push to `main` without explicit instruction.

---

## Repository Layout

```
Ava_tarot/
├── CLAUDE.md                        ← you are here
├── README.md                        ← human-facing project overview
│
├── .obsidian/                       ← Obsidian workspace config (open repo as vault)
│   ├── app.json                     ← editor settings
│   ├── workspace.json               ← panel layout: explorer left, graph right
│   └── graph.json                   ← graph color groups by arcana/suit
│
├── _Index.md                        ← vault root / navigation hub
│
├── Meta/
│   ├── Card-Schema.md               ← canonical schema for card notes (READ THIS FIRST)
│   ├── Edge-Types.md                ← taxonomy of graph edge relationship types
│   └── Graph-Index.md               ← 78-node inventory with completion status
│
├── Cards/
│   ├── Major Arcana/
│   │   ├── _Major-Arcana-Index.md   ← Fool's Journey overview + card table
│   │   ├── 00-The-Fool.md           ← COMPLETE
│   │   ├── 01-The-Magician.md       ← COMPLETE
│   │   ├── 02-The-High-Priestess.md ← COMPLETE
│   │   └── (MA-03 through MA-21 are stubs — not yet created as files)
│   └── Minor Arcana/
│       ├── _Minor-Arcana-Index.md
│       ├── Wands/
│       │   ├── _Wands-Index.md
│       │   └── Wands-Ace.md         ← COMPLETE
│       ├── Cups/
│       │   └── _Cups-Index.md       ← index only, cards are stubs
│       ├── Swords/
│       │   └── _Swords-Index.md     ← index only
│       └── Pentacles/
│           └── _Pentacles-Index.md  ← index only
│
├── Layouts/
│   ├── _Layout-Schema.md            ← slot coordinate conventions
│   ├── Three-Card.md                ← COMPLETE (3 slots, portrait row)
│   └── Celtic-Cross.md              ← COMPLETE (10 slots, cross + staff)
│
├── Godot/                           ← Design notes only (Godot project not yet created)
│   ├── _Godot-Project-Notes.md      ← architecture, file structure, PWA deployment
│   └── Card-Node-Design.md          ← CardBase scene/script spec, touch input, camera
│
└── Assets/
    ├── Images/                      ← card art goes here (naming: MA-00-The-Fool.png)
    └── Fonts/
```

**The Godot project files (`.tscn`, `.gd`, `project.godot`) do not exist yet.** The `Godot/` folder contains design specifications only. Building the actual Godot project is the next major phase.

---

## System 1: Obsidian Vault / Knowledge Graph

Open this repo as an Obsidian vault. The vault doubles as:
1. A living knowledge base about tarot cards
2. The source of truth for card metadata that feeds the Godot app

### How a card note is structured

```markdown
---                              ← YAML frontmatter = node properties
type: card
card_id: MA-00                   ← unique ID (see ID scheme below)
name: The Fool
arcana: Major
number: 0
element: Air
planet: Uranus
zodiac: null
keywords_upright: [beginnings, innocence, ...]
keywords_reversed: [recklessness, ...]
image: MA-00-The-Fool.png
godot_scene: res://Cards/Major/TheFool.tscn
status: complete                 ← complete | in-progress | stub
---

# Card Name

[Article: imagery, symbolism, meaning]

## Upright
## Reversed
## Elemental and Astrological
## Numerology  (optional)

## Adjacency List              ← graph edges FROM this card

| target_id | target_name | relationship | weight | properties |
|-----------|-------------|--------------|--------|------------|
| MA-01 | [[01-The-Magician]] | sequential | 1.0 | {"notes": "..."} |
```

### Card ID scheme

| Prefix | Cards |
|--------|-------|
| `MA-00` – `MA-21` | Major Arcana |
| `WA-01` – `WA-14` | Wands (01=Ace, 11=Page, 12=Knight, 13=Queen, 14=King) |
| `CU-01` – `CU-14` | Cups |
| `SW-01` – `SW-14` | Swords |
| `PE-01` – `PE-14` | Pentacles |

### Edge relationship types (summary)

| Type | Meaning |
|------|---------|
| `sequential` | Consecutive on Fool's Journey |
| `sequential_cycle` | World → Fool closure |
| `complementary` | Paired opposites (e.g. Magician / High Priestess) |
| `shadow` | One card is the dark reflection of the other |
| `thematic` | Shared themes or symbols |
| `elemental` | Same elemental affinity |
| `astrological` | Same planet or zodiac ruler |
| `numerical` | Same pip number across suits |
| `archetype` | Minor card embodies a Major Arcana archetype |

Full definitions: `Meta/Edge-Types.md`

### Current graph status

- **Complete nodes**: MA-00, MA-01, MA-02, WA-01 (4 of 78)
- **22 edges** declared across those 4 nodes
- **74 cards** remain as stubs (no file yet for most; suit index files exist)
- `Meta/Graph-Index.md` tracks the full inventory

### Adding a new card

1. Create the file at the correct path (e.g. `Cards/Major Arcana/03-The-Empress.md`)
2. Copy the frontmatter structure from an existing complete card
3. Write the article sections (Upright, Reversed, Elemental, optionally Numerology)
4. Add the `## Adjacency List` table — at minimum one `sequential` edge for Major Arcana
5. Update `status: complete` in frontmatter
6. Update the edge count in `Meta/Graph-Index.md`

---

## System 2: Godot Project (Design Phase — Not Yet Built)

Full specs are in `Godot/_Godot-Project-Notes.md` and `Godot/Card-Node-Design.md`. Summary:

### What to build

```
res://
├── Cards/
│   ├── CardBase.tscn + CardBase.gd     ← drag, tap-vs-drag, flip, orientation
│   ├── Major/ and Minor/               ← one .tscn per card (inherits CardBase)
├── Layouts/
│   ├── LayoutBase.tscn + LayoutBase.gd ← slot snapping logic
│   ├── ThreeCard.tscn
│   └── CelticCross.tscn
├── UI/
│   ├── DeckManager.tscn                ← shuffle + draw UI
│   ├── LayoutSelector.tscn
│   └── CardInfo.tscn                   ← sidebar: card details + graph neighbors
├── Data/
│   ├── cards.json                      ← exported from vault
│   └── layouts.json
├── Autoloads/
│   ├── DeckState.gd                    ← deck order + per-card orientation (reversed bool)
│   └── GraphDB.gd                      ← in-memory graph from cards.json
└── project.godot
```

### Critical project settings (set these first)

| Setting | Value |
|---------|-------|
| Project Settings > Input > Pointing > **Emulate Mouse from Touch** | **ON** |
| Display > Window > Viewport Width | 1080 |
| Display > Window > Viewport Height | 1920 |
| Display > Window > Content Scale Mode | `canvas_items` |
| Display > Window > Content Scale Aspect | `keep` |

### Touch input pattern (IMPORTANT)

Cards use a `DRAG_THRESHOLD` (12px) to distinguish tap from drag:
- Press + release without moving → `card_clicked` signal → flip or show info
- Press + move > 12px → enter drag mode → `card_dropped` signal on release

Camera2D handles pan (one/two finger on empty table) and pinch-zoom. Cards consume their own input events so the camera doesn't interfere.

See `Godot/Card-Node-Design.md` for full GDScript snippets.

### PWA deployment

- Export: Godot HTML5 export with **Progressive Web App** checkbox ON
- Host on **Netlify** (required for COOP/COEP headers — GitHub Pages won't work without workarounds)
- Add `netlify.toml` to repo root:
  ```toml
  [[headers]]
    for = "/*"
    [headers.values]
      Cross-Origin-Opener-Policy = "same-origin"
      Cross-Origin-Embedder-Policy = "require-corp"
  ```
- End user: open URL → "Add to Home Screen" → full-screen app icon, works offline

See `Godot/_Godot-Project-Notes.md` for complete deployment section.

### Data pipeline: Vault → Godot

A Python export script (not yet written) will:
1. Parse all `Cards/**/*.md` frontmatter → node properties
2. Parse `## Adjacency List` tables → edge list
3. Write `Data/cards.json` + `Data/layouts.json`

`GraphDB.gd` loads this JSON at runtime. `CardInfo` panel queries it when a card is tapped.

---

## Key Decisions Already Made

These were discussed and chosen — don't re-open unless the user brings it up:

| Decision | Reason |
|----------|--------|
| Godot 4 (not Flutter, React Native, etc.) | User's choice; supports all needed features |
| Web/PWA only, no native apps | User explicitly does not want app store overhead |
| Obsidian vault in same repo as code | Knowledge graph and app share one source of truth |
| Node2D cards (not Control) | Free spatial placement, not constrained to UI layout flow |
| Cards.json loaded at runtime (not hardcoded) | Vault stays authoritative; no duplication |
| Portrait base viewport 1080×1920 | Primary use is phone, portrait orientation |
| Netlify for hosting (not GitHub Pages) | Pages can't set COOP/COEP headers natively |

---

## What Comes Next

Roughly in order:

1. **Fill out remaining 74 card notes** in the vault — content work, can be done incrementally
2. **Write the Python export script** (`tools/export_vault.py`) to produce `Data/cards.json`
3. **Create the Godot project** — initialize `project.godot`, set the project settings above
4. **Build `CardBase.tscn` + `CardBase.gd`** — the tap/drag/flip foundation everything else depends on
5. **Build `LayoutBase`** + `ThreeCard.tscn` and `CelticCross.tscn` with slot snapping
6. **Build `DeckState.gd` + `GraphDB.gd`** autoloads
7. **Build the UI** — `DeckManager`, `LayoutSelector`, `CardInfo` panel
8. **Add card art** to `Assets/Images/` (naming: `MA-00-The-Fool.png`, etc.)
9. **PWA export + Netlify deploy**

---

## Conventions

- Card file names: `00-The-Fool.md`, `01-The-Magician.md` (zero-padded number, hyphenated name)
- Minor Arcana: `Wands-Ace.md`, `Wands-Two.md`, … `Wands-King.md`
- Image files: `MA-00-The-Fool.png`, `WA-01-Ace-of-Wands.png`
- Godot scene names: `TheFool.tscn`, `TheMagician.tscn`, `WandsAce.tscn` (PascalCase, no hyphens)
- All new Markdown content files go in `Cards/`, `Layouts/`, or `Meta/` — not at repo root
- `CLAUDE.md`, `README.md`, and `netlify.toml` live at repo root
