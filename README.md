# Ava Tarot

An interactive digital tarot deck — a tool for laying out, flipping, and reading cards on screen.

Built in **Godot 4**, deployed as a **PWA** (installable web app, no app store required).

---

## What It Does

- Shuffle a full 78-card Rider-Waite deck with configurable upright/reversed probability
- Deal cards into classic spread layouts (Three-Card, Celtic Cross) or place them freeform
- Flip cards face-up or face-down with an animation
- Tap a card to see its meanings, keywords, and knowledge-graph neighbors
- Pan and pinch-zoom the card table on phone or desktop

## Who It's For

Designed for phone use (Android + iOS), portrait orientation, touch drag-and-drop. Runs in any mobile browser; can be added to home screen as a full-screen app.

---

## Repository Structure

This repo contains two things in one:

### 1. Obsidian Vault (content + knowledge graph)

Open this repo as an [Obsidian](https://obsidian.md) vault. Each card is a Markdown note with:
- YAML frontmatter encoding card properties (element, planet, keywords, etc.)
- An article describing the card's symbolism and interpretation
- An **Adjacency List** section defining typed, weighted edges to related cards

The graph view in Obsidian renders the card relationships visually. The vault is the source of truth that feeds the Godot app via a JSON export pipeline.

Start here: [_Index.md](_Index.md)

### 2. Godot Project (interactive app)

The Godot project files live at repo root alongside the vault. Design specifications are in [`Godot/`](Godot/).

**Current status**: design phase — Godot project not yet initialized.

---

## Tech Stack

| Layer | Tech |
|-------|------|
| Card content + knowledge graph | Obsidian (Markdown) |
| Interactive engine | Godot 4.x — GDScript |
| Deployment | Godot HTML5 export → PWA |
| Hosting | Netlify |
| Metadata pipeline | Python (vault MD → `Data/cards.json`) |

---

## Development

### Prerequisites

- [Obsidian](https://obsidian.md) — for vault editing
- [Godot 4.x](https://godotengine.org) — for the app
- Python 3.x — for the vault export script (once written)

### Opening the Vault

Open this folder as an Obsidian vault. The `.obsidian/` config sets up the workspace with a file explorer on the left and a local graph panel on the right.

### Continuing Development

See [`CLAUDE.md`](CLAUDE.md) for a full technical handoff document covering:
- Architecture decisions
- Current state and what remains
- Schema conventions
- Godot project settings
- PWA deployment steps

---

## Card Coverage

| Section | Complete | Total |
|---------|----------|-------|
| Major Arcana | 3 | 22 |
| Wands | 1 | 14 |
| Cups | 0 | 14 |
| Swords | 0 | 14 |
| Pentacles | 0 | 14 |
| **Total** | **4** | **78** |

---

## License

TBD
