---
type: layout
layout_id: ava-celtic-cross
name: Ava's Celtic Cross
description: Ava's preferred ten-card spread — a personal variation on the classic Celtic Cross with relabeled positions and her own interpretive frame.
slot_count: 10
card_orientation: mixed
godot_scene: res://Layouts/AvaCelticCross.tscn
---

# Ava's Celtic Cross

This is Ava's specific preferred take on the classic Celtic Cross.
## Slot Layout Diagram

```
                            [10] Outcome
                            [ 9] Assistance
	        [ 4] Present
                            [ 8] External Perception
                            [ 7] Internal Perception

[3] Past   [1]+[2]   [5] Short Term

           [ 6] Long Term
```

Slots 1 and 2 share the same (x, y) position; slot 2's card is rotated 90° to cross slot 1.

## Slots

| slot_id | label | x | y | rotation | meaning |
| ---- | ---- | ---- | ---- | ---- | ---- |
| 1 | The Querent | 0 | 0 | 0 | lorem |
| 2 | The Challenge | 0 | 0 | 90 | ipsum |
| 3 | Past | -200 | 0 | 0 | dolor |
| 4 | Present | 0 | -300 | 0 | amat |
| 5 | Short Term | 200 | 0 | 0 | sit |
| 6 | Long Term | 0 | 300 | 0 | foo |
| 7 | Internal Perception | 550 | 300 | 0 | bar |
| 8 | External Perception | 550 | 100 | 0 | baz |
| 9 | Assistance | 550 | -100 | 0 | qux |
| 10 | Outcome | 550 | -300 | 0 | quux |


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
