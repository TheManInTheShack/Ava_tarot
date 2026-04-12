---
type: meta
title: Godot Project Notes
---

# Godot Project Notes

## Project Overview

This Godot project implements an interactive digital tarot deck. It is **not a game** — it is a digital tool for working with cards on screen the way you would on a physical table.

## Core Feature Set

| Feature | Description |
|---------|-------------|
| **Freeform placement** | Cards can be dragged and dropped anywhere on the canvas |
| **Template layouts** | Cards snap into named spread positions (slots) |
| **Flip animation** | Cards animate face-down ↔ face-up |
| **Reversed orientation** | Cards can be upright or reversed (180° rotation) |
| **Shuffle** | Deck shuffles; orientation is randomized per card at configurable probability |
| **Knowledge graph** | Card metadata and edges loaded from JSON exported from this vault |

## Engine

**Godot 4.x** — GDScript

## Project File Structure

```
res://
├── Cards/
│   ├── CardBase.tscn          # Template card scene
│   ├── CardBase.gd            # Drag, flip, orientation logic
│   ├── Major/
│   │   ├── TheFool.tscn
│   │   └── ...                # One .tscn per Major Arcana card
│   └── Minor/
│       ├── Wands/
│       ├── Cups/
│       ├── Swords/
│       └── Pentacles/
├── Layouts/
│   ├── LayoutBase.tscn        # Template layout scene
│   ├── LayoutBase.gd          # Slot management and snapping
│   ├── ThreeCard.tscn
│   └── CelticCross.tscn
├── UI/
│   ├── DeckManager.tscn       # Deck shuffle and draw interface
│   ├── LayoutSelector.tscn    # Spread selection UI
│   └── CardInfo.tscn          # Sidebar panel: card details and graph neighbors
├── Data/
│   ├── cards.json             # Exported graph from Obsidian vault
│   └── layouts.json           # Exported layout definitions
├── Autoloads/
│   ├── DeckState.gd           # Global: current deck order and card orientations
│   └── GraphDB.gd             # In-memory graph: nodes and edges from cards.json
└── project.godot
```

## Data Pipeline: Vault → Godot

The Obsidian vault is the **source of truth** for card metadata. A Python export script (to be developed) will:

1. Parse all `Cards/**/*.md` files
2. Extract YAML frontmatter → card node properties
3. Extract `## Adjacency List` tables → typed, weighted edges
4. Output `Data/cards.json` and `Data/layouts.json` for Godot to load at runtime via `GraphDB.gd`

### `cards.json` shape (draft)

```json
{
  "nodes": {
    "MA-00": {
      "name": "The Fool",
      "arcana": "Major",
      "number": 0,
      "element": "Air",
      "planet": "Uranus",
      "keywords_upright": ["beginnings", "innocence"],
      "keywords_reversed": ["recklessness"],
      "image": "MA-00-The-Fool.png",
      "godot_scene": "res://Cards/Major/TheFool.tscn"
    }
  },
  "edges": [
    {
      "source": "MA-00",
      "target": "MA-01",
      "relationship": "sequential",
      "weight": 1.0,
      "properties": { "notes": "First step on the Fool's Journey" }
    }
  ]
}
```

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Cards are `Node2D`, not `Control` | Free spatial placement; not constrained to UI flow |
| Slots use `Marker2D` as anchors | Lightweight; just a position and name |
| Flip animation uses Y-scale tween | Convincing physical card flip without 3D |
| Reversed = 180° rotation | Visually unambiguous; stored per-card in `DeckState` |
| Snap radius on drop | Cards snap to the nearest slot if within 80px; otherwise stay freeform |
| `GraphDB` as autoload | Graph is available globally; `CardInfo` panel can query neighbors on click |

## See Also

- [[Card-Node-Design]] — Detailed CardBase scene and script specification
- [[../Meta/Card-Schema]] — Vault schema that feeds the data pipeline
- [[../Layouts/_Layout-Schema]] — Slot coordinate conventions
