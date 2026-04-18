---
type: layout
layout_id: three-card
name: Three-Card Spread
description: A versatile three-position spread. Classic interpretation is Past / Present / Future, but positions can be reframed for almost any question.
slot_count: 3
card_orientation: mixed
godot_scene: res://Layouts/ThreeCard.tscn
---

# Three-Card Spread

The three-card spread is the workhorse of tarot reading — versatile, fast, and legible at a glance. Three cards in a row establish a simple narrative arc. The classic framing is **Past / Present / Future**, but the positions absorb many other interpretive frameworks depending on the question.

## Alternative Framings

| Position 1 | Position 2 | Position 3 | Use Case |
|------------|------------|------------|----------|
| Past | Present | Future | General situation |
| Situation | Action | Outcome | Decision-making |
| Mind | Body | Spirit | Wellness |
| You | The other | The relationship | Relationship reading |
| What to embrace | What to release | What is becoming | Inner work |
| Strength | Challenge | Advice | Problem-solving |
| Conscious | Unconscious | Integration | Psychological depth |

## Slots

| slot_id | label | x | y | rotation | meaning |
|---------|-------|---|---|----------|---------|
| 1 | Past    | -220 | 0 | 0 | What has shaped the current situation |
| 2 | Present |    0 | 0 | 0 | The current state of affairs |
| 3 | Future  |  220 | 0 | 0 | Where events are trending if the current path continues |

## Godot Layout Notes

- Cards are placed left-to-right in a horizontal row
- Entire spread fits in a 1920×1080 viewport at 100% zoom with room to spare
- Slot labels render below each card position as a `Label` node
- Consider animating cards dealing in left-to-right sequence with a short delay between each

## Adjacency List

| target_id | target_name | relationship | weight | properties |
|-----------|-------------|--------------|--------|------------|
| celtic-cross | [[Celtic-Cross]] | related_layout | 0.6 | {"notes": "Celtic Cross is the expanded form; three-card is often used as a quick read before a full Celtic Cross"} |
