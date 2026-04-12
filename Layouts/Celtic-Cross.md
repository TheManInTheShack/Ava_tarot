---
type: layout
layout_id: celtic-cross
name: Celtic Cross
description: The classic ten-card spread providing a comprehensive view of a situation from multiple angles — the challenge, its roots, past, future, inner world, outer world, hopes, and likely outcome.
slot_count: 10
card_orientation: mixed
godot_scene: res://Layouts/CelticCross.tscn
---

# Celtic Cross

The Celtic Cross is the most recognized tarot spread, comprising ten cards arranged in a specific spatial pattern that encodes a complete narrative of the querent's situation. It provides a layered view: the central challenge, surrounding influences, past, future, inner world, outer world, hopes and fears, and likely outcome.

## Slot Layout Diagram

```
                            [10] Outcome
                            [ 9] Hopes / Fears
                            [ 8] External Influences
                            [ 7] Self / Role

[4] Past   [1]+[2]   [6] Near Future

           [ 5] Foundation
           [ 3] Recent Past
```

Slots 1 and 2 share the same (x, y) position; slot 2's card is rotated 90° to cross slot 1.

## Slots

| slot_id | label | x | y | rotation | meaning |
|---------|-------|---|---|----------|---------|
| 1 | The Present | 0 | 0 | 0 | The heart of the matter; the querent's current situation |
| 2 | The Challenge | 0 | 0 | 90 | What crosses or challenges card 1 — friend or foe |
| 3 | Recent Past | 0 | 200 | 0 | Events just passed that still influence the present |
| 4 | Past | -300 | 0 | 0 | Foundational past events; what has led here |
| 5 | Crown | 0 | -200 | 0 | What the querent strives toward; best possible outcome; conscious goal |
| 6 | Near Future | 300 | 0 | 0 | What is approaching in the near term |
| 7 | Self | 550 | 300 | 0 | The querent's attitude, inner state, and self-perception |
| 8 | External Environment | 550 | 100 | 0 | How others see the querent; external influences |
| 9 | Hopes and Fears | 550 | -100 | 0 | The querent's deepest hopes or fears — often both at once |
| 10 | Outcome | 550 | -300 | 0 | The likely outcome if the current trajectory continues |

## Position Interpretation Notes

**Slots 1 & 2** are the center of gravity. Card 2 crosses card 1 — it may challenge, support, or complicate the central energy; it is neutral in meaning until the surrounding cards provide context.

**Slots 3–6** form the cross: a temporal and aspiration map. Read together they establish the full arc of the situation.

**Slots 7–10** are the staff — a vertical column on the right that reads from the inner world (bottom) outward to external environment and upward to outcome.

## Godot Layout Notes

- Slots 1 and 2 share identical `(x, y)`; the Godot scene uses `z_index` to layer them and applies a 90° rotation to slot 2's card upon placement
- The staff column (7–10) is separate from the cross cluster; a minimum viewport width of 1400 px is recommended
- Deal animation: cross cards first (1, 2, 5, 3, 4, 6), then staff bottom to top (7, 8, 9, 10), with a brief pause between the two groups

## Adjacency List

| target_id | target_name | relationship | weight | properties |
|-----------|-------------|--------------|--------|------------|
| three-card | [[Three-Card]] | related_layout | 0.7 | {"notes": "Three-card is often used as a preliminary check before or alongside a full Celtic Cross"} |
