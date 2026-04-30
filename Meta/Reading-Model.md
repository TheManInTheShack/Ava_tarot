---
type: meta
title: Reading & Scenario Data Model
---

# Reading & Scenario Data Model

This document defines the conceptual architecture for readings, scenarios, and metrics in the Ava Tarot knowledge graph. It is a design reference — nothing described here is yet implemented beyond the base card graph.

---

## Graph Layers

The full graph is composed of four distinct layers. Each is optionally loadable on top of the one below. The base card graph is always present; the others are applied as context demands.

| Layer | Contents | Always Loaded |
|-------|----------|---------------|
| 0 — Card Graph | 78 card nodes, ~286 edges (sequential, relational, correspondence) | Yes |
| 1 — Layout Graph | Layout and slot nodes; describes physical reading positions | When a spread is selected |
| 2 — Reading | A specific spread instance; card-in-slot edges with orientation | When reviewing a past reading |
| 3 — Scenarios | Named subgraph patterns extracted from or overlaid onto a reading | On demand / admin-defined |

Layers 2 and 3 are subgraphs that reference nodes from layers 0 and 1. They do not modify the base graph.

---

## Node Types

| Type | Status | Description |
|------|--------|-------------|
| `card` | Existing | One node per card (78 total) |
| `layout` | Existing | One node per spread type |
| `slot` | Partially defined | Currently metadata on layout nodes; promote to first-class for readings |
| `reading` | Planned | A timestamped record of one spread instance |
| `scenario` | Planned | A named, admin-defined subgraph pattern |
| `metric` | Planned | A computed aggregate property of a reading |

---

## Readings

A **reading** is a Layer 2 subgraph recording which cards appeared in which slots and how. It is bounded: it cannot exist without a layout, and it references only nodes from layers 0 and 1.

### Reading Node Properties

```json
{
  "reading_id": "reading-2026-04-21-001",
  "layout_id": "ava-celtic-cross",
  "timestamp": "2026-04-21T14:30:00",
  "querent": "optional free-text",
  "notes": "optional reading notes"
}
```

### Reading Edge Types (new, to add to Edge-Types.md)

| Type | Description |
|------|-------------|
| `placed_upright` | Card occupies a slot in its normal (vertical) orientation |
| `placed_reversed` | Card occupies a slot in reversed orientation |
| `crosses_upright` | Card occupies a slot in horizontal (crossing) orientation, upright |
| `crosses_reversed` | Card occupies a slot in horizontal (crossing) orientation, reversed |

Every card placement in a reading is one of these four edge types from a `card` node to a `slot` node, carrying the `reading_id` as a property so the edge is scoped to that reading.

---

## Scenarios

Scenarios are the most structurally rich concept. There are two distinct flavors.

---

### Flavor A — Positional Scenarios (slot-bound)

A positional scenario is tied to a specific slot and describes the cards physically present there. The superposition is the canonical case.

**Superposition structure:**
- A primary card (node) with its inversion status
- A secondary card (node) with its inversion status
- A slot (node) within a specific layout

**Combinatoric space** for Ava's Celtic Cross (10 slots):
```
78 (primary) × 2 (primary inversion) × 77 (secondary) × 2 (secondary inversion) × 10 (slot)
= 240,240 possible superposition instances
```
The space is not pre-fillable — instances are recorded as they occur in actual readings.

**Positional scenario node:**
```json
{
  "scenario_id": "scenario-superposition-...",
  "type": "superposition",
  "slot_id": "slot-2",
  "layout_id": "ava-celtic-cross",
  "primary_card": "MA-18",
  "primary_reversed": false,
  "secondary_card": "MA-12",
  "secondary_reversed": true,
  "admin_notes": "Moon crosses the Hanged Man — suspension of fear",
  "reading_ids": ["reading-2026-04-21-001"]
}
```

Scenarios are linked to the readings in which they were observed, building a corpus over time.

---

### Flavor B — Aggregate Scenarios (pattern-wide)

Aggregate scenarios are not tied to a slot. They describe a property of the entire spread — a pattern that emerges when you look at all the cards together.

**The three core aggregate dimensions:**

| Dimension | Description | Representation |
|-----------|-------------|----------------|
| **Major Arcana density** | Ratio of major arcana cards to total | `n_major / n_total` → scalar (0.0–1.0) |
| **Suit distribution** | Relative presence of each suit | `[Wands, Cups, Swords, Pentacles]` → 4-vector |
| **Value distribution** | Relative presence of each pip value | `[Ace, 2–10, Page, Knight, Queen, King]` → 14-vector (or 4-group: low/mid/high/court) |

Additional optional dimensions:
- **Inversion ratio**: reversed cards / total → `scalar`
- **Court density**: face cards / total → `scalar`
- **Suit entropy**: spread vs concentration of suits → `scalar`

Each of these is a computable metric, not something the admin needs to define. They are derived automatically when a reading is saved.

---

## Phase Space & Reading Fingerprints

This is the key insight: a reading can be mapped to a point in a multi-dimensional feature space. Readings that share a "feel" will cluster near each other. Over time this enables pattern recognition — e.g., "readings with high major arcana density and suit concentration in Cups tend to be emotionally charged."

**Compact feature vector (one reading):**
```
[major_ratio, wands_frac, cups_frac, swords_frac, pents_frac, inversion_ratio, court_ratio, value_entropy]
```

**The color metaphor** maps this to a 3-component visual fingerprint:
- **Hue (H)**: elemental balance — angle through the four suits projected onto a circle (Fire=0°, Water=90°, Air=180°, Earth=270°). A Wands-heavy reading is warm/red; Cups-heavy is blue-green.
- **Saturation (S)**: major arcana density — the more majors, the more vivid the reading.
- **Value (V)**: overall intensity — driven by inversion ratio and value entropy (lots of high-pip cards = darker; lots of Aces and courts = brighter).

This gives each reading a single HSV color that serves as a fast, human-readable fingerprint. Two readings with similar colors had similar structural character, regardless of the specific cards.

This is not a metaphor — it is a legitimate dimensionality reduction from an 8+ dimensional space to 3 perceptual dimensions. The mapping needs calibration with actual data before it becomes meaningful.

---

## Scenario Instantiation Workflow

Scenarios should not be created by default. The workflow is:

1. A reading is completed and saved (with card-in-slot edges and computed metrics).
2. The admin reviews the reading and optionally flags subgraph patterns as named scenarios.
3. A scenario instance is created, linked to the reading, and tagged with admin notes.
4. Over multiple readings, the same scenario recurs; its instance list grows.
5. The admin can query: "every time The Moon crossed The Hanged Man, what was the outcome?"

This means scenarios are **discovered, not prescribed** — the system doesn't know in advance which patterns are meaningful. The admin decides what to name and track.

---

## Implementation Phases

### Phase 1 — Readings (next)
- Promote slots to first-class nodes (or define them in a `slots.json`)
- Define `reading` schema and backend endpoints (`POST /api/readings`, `GET /api/readings/:id`)
- Record card placements as typed edges on the reading node
- Compute and store the feature vector at save time

### Phase 2 — Positional Scenarios
- Define scenario schema
- Admin UI: select a slot in a reading → "mark this as a scenario"
- Store scenario instances; link to readings
- Query interface: "show all readings where X crosses Y in slot Z"

### Phase 3 — Aggregate Scenarios & Phase Space
- Implement HSV fingerprint computation
- Display color chip alongside each saved reading
- Similarity search: "find readings with similar character to this one"
- Over time: clustering, pattern annotations

---

## Relationship to Existing Edge Types

New edge types needed (to be added to [[Edge-Types]]):

| Type | Layer | Description |
|------|-------|-------------|
| `placed_upright` | Reading | Card in slot, vertical orientation |
| `placed_reversed` | Reading | Card in slot, reversed |
| `crosses_upright` | Reading | Card in slot, horizontal/crossing, upright |
| `crosses_reversed` | Reading | Card in slot, horizontal/crossing, reversed |
| `observed_in` | Scenario | Scenario instance linked to a reading |
| `scenario_primary` | Scenario | Primary card in a positional scenario |
| `scenario_secondary` | Scenario | Secondary (crossing) card in a positional scenario |
| `scenario_slot` | Scenario | Slot that a positional scenario occupies |
