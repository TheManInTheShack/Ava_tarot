---
type: meta
title: Edge Type Taxonomy
---

# Edge Type Taxonomy

All edges in the Ava Tarot knowledge graph carry a `relationship` field. This document defines each type and its semantic meaning. See [[Card-Schema]] for the full edge table format.

---

## Structural (Major Arcana sequence)

| Type | Description |
|------|-------------|
| `sequential` | One card immediately precedes another on the Fool's Journey |
| `sequential_cycle` | Marks the cyclical closure: The World (21) back to The Fool (0) |

---

## Relational

| Type | Description |
|------|-------------|
| `complementary` | Cards forming a pair of opposing or balancing principles (e.g. Magician / High Priestess) |
| `shadow` | One card is the dark or unconscious expression of the other (e.g. Magician / Devil) |
| `thematic` | Shared themes, symbols, or psychological territory |

---

## Correspondence

| Type | Description |
|------|-------------|
| `elemental` | Shared elemental affinity (Fire, Water, Air, Earth) |
| `astrological` | Shared planetary or zodiac ruler |
| `numerical` | Same pip number across suits (e.g. all Aces, all Fours) |

---

## Cross-Arcana

| Type | Description |
|------|-------------|
| `archetype` | A Minor Arcana card embodies or exemplifies a Major Arcana archetype |
| `court_archetype` | A court card reflects a Major Arcana personality archetype |
| `related_layout` | A layout is thematically or functionally related to another layout |
| `position_affinity` | A card has traditional affinity for a particular spread position |

---

## Edge Properties Reference

All edge `properties` objects recognize these keys:

| Key | Type | Description |
|-----|------|-------------|
| `notes` | string | Human-readable description of the relationship **(required)** |
| `element` | string | Which element grounds this connection |
| `planet` | string | Which planet grounds this connection |
| `number` | integer | Which pip number grounds this connection |
| `journey_stage` | string | For `sequential` edges: the transition being described |
| `bidirectional` | boolean | If `true`, the inverse edge is implied (declare in both notes anyway) |

---

## Weight Guidelines

| Range | Meaning |
|-------|---------|
| 0.9–1.0 | Defining or canonical relationship |
| 0.7–0.8 | Strong, direct correspondence |
| 0.5–0.6 | Meaningful but secondary connection |
| 0.3–0.4 | Loose thematic resonance |
| 0.1–0.2 | Speculative or tradition-specific |
