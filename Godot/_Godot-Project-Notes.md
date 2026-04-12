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

## Engine and Deployment Target

**Godot 4.x** — GDScript  
**Primary export**: Web (HTML5 / WebAssembly), deployed as a **PWA**

No native app installs. One URL, works on any phone browser, installable to home screen. See [[#Deployment Web / PWA]] below.

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
| Emulate Mouse from Touch: ON | Single input code path handles both desktop mouse and phone touch |
| Pan/zoom via Camera2D | Spreads wider than the phone screen stay usable; no fixed viewport constraint |
| Web export + PWA | No app store; one URL; installable to home screen on Android and iOS |

---

## Deployment: Web / PWA

### What gets built

Godot's HTML5 export produces a self-contained bundle:
```
index.html
index.js
index.wasm
index.pck          ← all game assets packed here
index.audio.worklet.js
```

With **Progressive Web App** enabled in the export settings, Godot also generates:
```
manifest.json      ← app name, icons, display mode
service_worker.js  ← enables offline use and home-screen install
```

### How to host

Any static file host works. Recommended options:

| Host | Notes |
|------|-------|
| **GitHub Pages** | Free, automatic from a branch; familiar if you've done webapps |
| **Netlify** | Free tier, drag-and-drop deploy or Git-connected; good for quick shares |
| **itch.io** | Free, designed for Godot web exports specifically; good for testing |

> **HTTPS is required** for PWA install prompts and for SharedArrayBuffer (which Godot's web export needs for threading). GitHub Pages and Netlify provide HTTPS automatically.

### Enabling PWA in Godot

In the Godot export dialog (Project > Export > Web):
1. Check **"Progressive Web App"**
2. Set app name, short name, and upload icons (192×192 and 512×512 PNG)
3. Set **Display mode**: `standalone` (fills screen, no browser chrome)
4. Set **Orientation**: `portrait` or `any` — `any` lets the user decide

### What your sister does

1. Open the URL in Safari (iOS) or Chrome (Android)
2. Tap the share/menu button → **"Add to Home Screen"**
3. It installs as an icon on her home screen
4. Tapping it opens full-screen, no browser address bar, behaves exactly like a native app
5. Works offline after first load (service worker caches assets)

### Responsive Viewport

Set base resolution in **Project Settings > Display > Window**:

| Setting | Value |
|---------|-------|
| Viewport Width | 1080 |
| Viewport Height | 1920 |
| Content Scale Mode | `canvas_items` |
| Content Scale Aspect | `keep` |

This gives a portrait-oriented "world" that scales cleanly to any phone. The `Camera2D` with pinch-zoom (see [[Card-Node-Design#Canvas Pan and Zoom]]) handles spreads that are wider than the screen.

### COOP / COEP Headers (required for Godot 4 web)

Godot 4's web export requires two HTTP headers for `SharedArrayBuffer` support:
```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

On **Netlify**: add a `netlify.toml` at repo root:
```toml
[[headers]]
  for = "/*"
  [headers.values]
    Cross-Origin-Opener-Policy = "same-origin"
    Cross-Origin-Embedder-Policy = "require-corp"
```

On **GitHub Pages**: these headers cannot be set directly. Use a workaround repo like `godot-web-export-fix` or host on Netlify instead.

---

## See Also

- [[Card-Node-Design]] — Detailed CardBase scene and script specification
- [[../Meta/Card-Schema]] — Vault schema that feeds the data pipeline
- [[../Layouts/_Layout-Schema]] — Slot coordinate conventions
