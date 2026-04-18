---
type: index
title: Ava Tarot — Vault Index
created: 2026-04-12
---

# Ava Tarot

An interactive digital tarot deck powered by Godot, with a knowledge graph encoded directly into card notes.

## Navigation

| Section | Description |
|---------|-------------|
| [[Meta/Card-Schema\|Card Schema]] | Frontmatter and adjacency-list format for card notes |
| [[Meta/Edge-Types\|Edge Types]] | Taxonomy of graph edge relationships |
| [[Meta/Graph-Index\|Graph Index]] | Full graph overview and node inventory |
| [[Cards/Major Arcana/_Major-Arcana-Index\|Major Arcana]] | The 22 trump cards (MA-00 → MA-21) |
| [[Cards/Minor Arcana/_Minor-Arcana-Index\|Minor Arcana]] | The 56 pip and court cards |
| [[Layouts/_Layout-Schema\|Layouts]] | Spread / template definitions |
| [[Godot/_Godot-Project-Notes\|Godot Project]] | Engine design notes |

## Project Goals

1. **Interactive digital deck** built in Godot — a tool, not a game
2. **Card behaviors**: freeform drag, template snap, flip animation, upright/reversed orientation
3. **Spread templates**: predefined slot layouts (Celtic Cross, Three-Card, Single, etc.)
4. **Knowledge graph**: each card note is a graph node; adjacency lists encode typed, weighted edges
5. **Supplemental material**: articles in each card note enrich nodes; edge `properties` carry relational metadata

## Knowledge Graph Approach

```
Article (node) + YAML frontmatter (node properties)
    └── ## Adjacency List section (edges with typed, weighted properties)
```

Obsidian's wikilinks drive the visual graph view. The `## Adjacency List` tables make edges machine-readable and exportable to Godot at runtime.

## Asset Folders

- `Assets/Images/` — card face and back art
- `Assets/Fonts/` — custom typography
- `Godot/` — design notes (actual Godot project files live at repo root alongside this vault)
