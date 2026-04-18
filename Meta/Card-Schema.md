---
type: meta
title: Card Note Schema
---

# Card Note Schema

Every card in the vault is a Markdown note with two structural components:
1. **Frontmatter** — static node properties (YAML)
2. **Adjacency List section** — graph edges with typed, weighted, property-bearing connections

---

## Frontmatter (Node Properties)

```yaml
---
type: card                    # always "card"
card_id: MA-00                # unique ID — see ID Format below
name: The Fool                # display name
arcana: Major                 # "Major" or "Minor"
number: 0                     # 0–21 for Major; 1–14 for Minor
number_label: null            # override for Ace/Page/Knight/Queen/King; null otherwise
suit: null                    # Wands | Cups | Swords | Pentacles | null (for Major)
element: Air                  # Fire | Water | Air | Earth | null
planet: Uranus                # ruling planet, or null
zodiac: null                  # ruling zodiac sign, or null
keywords_upright:             # array of upright meaning keywords
  - beginnings
  - innocence
keywords_reversed:            # array of reversed meaning keywords
  - recklessness
image: MA-00-The-Fool.png     # filename under Assets/Images/
godot_scene: res://Cards/Major/TheFool.tscn   # Godot resource path
status: complete              # complete | stub | in-progress
---
```

### ID Format

| Prefix | Arcana / Suit |
|--------|--------------|
| `MA-NN` | Major Arcana (00–21) |
| `WA-NN` | Minor — Wands (01–14) |
| `CU-NN` | Minor — Cups (01–14) |
| `SW-NN` | Minor — Swords (01–14) |
| `PE-NN` | Minor — Pentacles (01–14) |

For Minor Arcana: `01` = Ace, `11` = Page, `12` = Knight, `13` = Queen, `14` = King.

### Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Always `"card"` |
| `card_id` | string | Globally unique node identifier |
| `name` | string | Full display name |
| `arcana` | string | `"Major"` or `"Minor"` |
| `number` | integer | Numeric position in arcana or suit |
| `number_label` | string\|null | Human label for Ace and court cards |
| `suit` | string\|null | Suit name, or `null` for Major Arcana |
| `element` | string\|null | `"Fire"` / `"Water"` / `"Air"` / `"Earth"` |
| `planet` | string\|null | Ruling planet |
| `zodiac` | string\|null | Ruling zodiac sign |
| `keywords_upright` | string[] | Upright meaning keywords |
| `keywords_reversed` | string[] | Reversed meaning keywords |
| `image` | string | Filename of card art under `Assets/Images/` |
| `godot_scene` | string | Godot scene resource path |
| `status` | string | `"complete"` \| `"stub"` \| `"in-progress"` |

---

## Adjacency List (Edge Properties)

Every card note ends with an `## Adjacency List` section containing a Markdown table of outgoing edges.

```markdown
## Adjacency List

| target_id | target_name | relationship | weight | properties |
|-----------|-------------|--------------|--------|------------|
| MA-01 | [[01-The-Magician]] | sequential | 1.0 | {"notes": "First step on the Fool's Journey"} |
```

### Edge Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `target_id` | string | `card_id` of the destination node |
| `target_name` | string | Wikilink to the destination note |
| `relationship` | string | Edge type — see [[Meta/Edge-Types]] |
| `weight` | float | Relatedness strength, 0.0–1.0 |
| `properties` | JSON string | Arbitrary metadata on this edge |

### Graph Semantics

- Edges are **directed** (source → target); bidirectional relationships should be declared in **both** card notes
- `weight` encodes relatedness strength; values can feed Godot graph layout algorithms
- The `properties` object must always include a `"notes"` key with a human-readable description

---

## Note Structure

```
---
[frontmatter]
---

# Card Name

[Article: description, symbolism, imagery]

## Upright

[Upright interpretation]

## Reversed

[Reversed interpretation]

## Elemental and Astrological

[Element, planet, zodiac associations]

## Numerology  (optional)

[Numerological significance]

## Adjacency List

[Edge table]
```

Optional additional sections:
- `## In Spreads` — how this card typically behaves in specific layout positions
- `## Historical Notes` — esoteric or historical background
- `## Artistic Variations` — notes on different deck traditions
