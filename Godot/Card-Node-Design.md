---
type: meta
title: Card Node Design
---

# Card Node Design

Specification for the `CardBase` scene and script — the foundation for every card in the deck.

---

## Scene Tree

```
CardBase (Node2D)
├── CardBack (Sprite2D)            # Back face texture — visible when face-down
├── CardFront (Sprite2D)           # Front face texture — visible when face-up
├── SelectionHighlight (Polygon2D) # Glow/outline when hovered or selected
├── DropShadow (Sprite2D)          # Soft shadow; z_offset offset downward
├── CollisionArea (Area2D)         # Receives mouse input events
│   └── CollisionShape2D           # Matches card rect (RectangleShape2D)
└── AnimationPlayer                # Flip animation clips
```

---

## Exported Properties (GDScript)

```gdscript
@export var card_id:       String    = ""     # e.g. "MA-00"
@export var card_name:     String    = ""
@export var face_texture:  Texture2D          # Front face art
@export var back_texture:  Texture2D          # Shared deck back
@export var is_face_up:    bool      = true
@export var is_reversed:   bool      = false  # true = 180° upside-down orientation
```

---

## Signals

```gdscript
signal card_clicked(card: CardBase)
signal card_dropped(card: CardBase, drop_position: Vector2)
signal card_flipped(card: CardBase, is_face_up: bool)
```

---

## Flip Animation

The flip is a Y-axis scale tween simulating a physical card turn. Halfway through, when the card is scaled to zero on Y, the textures swap.

```gdscript
const FLIP_HALF_DURATION := 0.18  # seconds

func flip() -> void:
    var tween := create_tween()
    tween.set_ease(Tween.EASE_IN_OUT)
    tween.set_trans(Tween.TRANS_CUBIC)
    tween.tween_property(self, "scale:y", 0.0, FLIP_HALF_DURATION)
    tween.tween_callback(_swap_face)
    tween.tween_property(self, "scale:y", 1.0, FLIP_HALF_DURATION)
    emit_signal("card_flipped", self, !is_face_up)

func _swap_face() -> void:
    is_face_up = !is_face_up
    card_front.visible = is_face_up
    card_back.visible  = !is_face_up
    # Preserve reversal rotation on face-up cards
    rotation_degrees = 180.0 if (is_face_up and is_reversed) else 0.0
```

---

## Drag and Drop

```gdscript
var _dragging:     bool    = false
var _drag_offset:  Vector2 = Vector2.ZERO
const DRAG_Z_INDEX := 100

func _on_collision_area_input_event(_viewport, event, _shape_idx):
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            _dragging    = true
            _drag_offset = global_position - get_global_mouse_position()
            z_index      = DRAG_Z_INDEX
            drop_shadow.modulate.a = 0.6  # stronger shadow while dragging
        else:
            _dragging = false
            z_index   = 0
            drop_shadow.modulate.a = 0.25
            emit_signal("card_dropped", self, global_position)

func _process(_delta):
    if _dragging:
        global_position = get_global_mouse_position() + _drag_offset
```

---

## Slot Snapping

Handled by the Layout scene, not by the card itself. When `card_dropped` fires, the active layout checks proximity to each of its slots:

```gdscript
# In LayoutBase.gd
const SNAP_RADIUS := 80.0

func _on_card_dropped(card: CardBase, drop_pos: Vector2) -> void:
    for slot in get_children():  # slots are Marker2D children
        if slot.global_position.distance_to(drop_pos) < SNAP_RADIUS:
            card.global_position = slot.global_position
            card.is_reversed     = slot.get_meta("force_reversed", false)
            if card.is_reversed:
                card.rotation_degrees = 180.0
            slot.set_meta("assigned_card", card)
            return
    # No slot nearby — card stays in freeform position
```

---

## Upright / Reversed Orientation

- **Stored** in `DeckState.card_orientations: Dictionary` (`card_id → bool`)
- **During shuffle**: each card has a configurable chance of being reversed (default 33%)
- **Visual**: reversed cards rotate 180° — the graphic appears upside down
- **After flip**: `_swap_face()` re-applies the rotation so a face-up reversed card stays visually reversed

```gdscript
# DeckState.gd (autoload)
var card_orientations: Dictionary = {}  # card_id: String → is_reversed: bool
var reversal_probability: float = 0.33

func shuffle_deck(card_ids: Array) -> Array:
    card_ids.shuffle()
    for id in card_ids:
        card_orientations[id] = randf() < reversal_probability
    return card_ids
```

---

## Card Dimensions

| Property | Value |
|----------|-------|
| Width | 140 px |
| Height | 240 px |
| Aspect ratio | 1 : 1.714 (standard tarot) |
| Back texture | Shared across all cards (`res://Assets/card_back.png`) |
| Front texture | Unique per card (`res://Assets/Images/MA-00-The-Fool.png`, etc.) |

---

## CardInfo Sidebar Panel

When a card is clicked (not dragged), the `CardInfo.tscn` panel populates with:
- Card name, arcana, suit, element, planet
- Upright and reversed keywords
- A list of graph neighbors pulled from `GraphDB.gd` — relationship type, target name, weight
- A "flip" button and an "orient" toggle (upright / reversed)

```gdscript
# GraphDB.gd (autoload)
var nodes: Dictionary = {}  # card_id → node property dict
var edges: Array = []       # [{source, target, relationship, weight, properties}]

func get_neighbors(card_id: String) -> Array:
    return edges.filter(func(e): return e["source"] == card_id)
```
