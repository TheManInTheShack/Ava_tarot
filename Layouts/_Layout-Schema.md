---
type: meta
title: Layout / Spread Schema
---

# Layout / Spread Schema

A **layout** (also called a *spread*) defines a set of named positions — *slots* — where cards are placed during a reading. Each slot has interpretive meaning and spatial coordinates used by the Godot renderer.

---

## Frontmatter (Layout Node Properties)

```yaml
---
type: layout
layout_id: three-card             # machine-readable unique ID (kebab-case)
name: Three-Card Spread           # display name
description: Short description.
slot_count: 3                     # number of card positions
card_orientation: mixed           # upright | mixed (mixed = reversed cards allowed)
godot_scene: res://Layouts/ThreeCard.tscn
---
```

### Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Always `"layout"` |
| `layout_id` | string | Unique identifier, kebab-case |
| `name` | string | Human-readable name |
| `description` | string | Brief description of the spread's purpose |
| `slot_count` | integer | Number of card positions |
| `card_orientation` | string | `"upright"` = no reversed cards; `"mixed"` = reversed cards allowed |
| `godot_scene` | string | Godot scene resource path |

---

## Slot Definition

Each slot is defined in the `## Slots` section as a table:

```markdown
## Slots

| slot_id | label | x | y | rotation | meaning |
|---------|-------|---|---|----------|---------|
| 1 | Past   | -220 | 0 | 0  | What has shaped the situation |
| 2 | Present|    0 | 0 | 0  | The current state of affairs  |
| 3 | Future |  220 | 0 | 0  | Where events are trending     |
```

### Slot Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `slot_id` | integer | Unique position number within this layout |
| `label` | string | Human-readable name for this position |
| `x` | integer | X coordinate in Godot viewport pixels (center = 0) |
| `y` | integer | Y coordinate (positive = downward) |
| `rotation` | integer | Base rotation in degrees (0 = upright, 90 = landscape / crossing card) |
| `meaning` | string | Interpretive meaning of this position |

---

## Godot Coordinate System

- **Origin (0, 0)**: viewport center
- **X axis**: left is negative, right is positive
- **Y axis**: up is negative, down is positive (standard Godot 2D)
- Card nominal size: **140 × 240 px** (standard tarot aspect ratio ≈ 1:1.714)
- Gap between adjacent cards: **~80 px**

---

## Optional: Layout Adjacency List

Layouts can participate in the knowledge graph with edges to related layouts or to cards with traditional affinity for specific positions:

```markdown
## Adjacency List

| target_id | target_name | relationship | weight | properties |
|-----------|-------------|--------------|--------|------------|
| three-card | [[Three-Card]] | related_layout | 0.8 | {"notes": "Three-card is the compact form of this spread"} |
| MA-00 | [[../Cards/Major Arcana/00-The-Fool]] | position_affinity | 0.6 | {"slot_id": 1, "notes": "The Fool often appears in position 1 (new beginnings)"} |
```
