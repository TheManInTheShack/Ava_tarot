---
type: meta
title: Card Node Design
---

# Card Node Design

Specification for the `CardBase` scene and script — the foundation for every card in the deck.

**Deployment target**: Web / PWA. Input handling covers both mouse (desktop browser) and touch (phone/tablet). See [[_Godot-Project-Notes#Deployment Web / PWA]] for hosting strategy.

---

## Scene Tree

```
CardBase (Node2D)
├── CardBack (Sprite2D)            # Back face texture — visible when face-down
├── CardFront (Sprite2D)           # Front face texture — visible when face-up
├── SelectionHighlight (Polygon2D) # Glow/outline when hovered or selected
├── DropShadow (Sprite2D)          # Soft shadow; z_offset offset downward
├── CollisionArea (Area2D)         # Receives mouse + touch input events
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

## Touch and Mouse Input Strategy

**Project Settings > Input > Pointing > Emulate Mouse from Touch: ON**

Enabling this in Godot's project settings means every finger tap/drag is automatically translated into equivalent mouse events. The card code only handles mouse events and works on both desktop and touch screens for free. No separate touch code paths needed.

The one thing emulation doesn't resolve automatically is **tap vs drag disambiguation**: a finger-down followed immediately by finger-up should flip the card; a finger-down followed by movement should drag it. We use a movement threshold to tell them apart.

---

## Drag and Drop

```gdscript
const DRAG_Z_INDEX  := 100
const DRAG_THRESHOLD := 12.0   # pixels of movement before drag mode activates

var _input_down:      bool    = false
var _dragging:        bool    = false   # true once DRAG_THRESHOLD is exceeded
var _drag_offset:     Vector2 = Vector2.ZERO
var _press_start_pos: Vector2 = Vector2.ZERO

func _on_collision_area_input_event(_viewport, event, _shape_idx):
    if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
        return

    if event.pressed:
        _input_down      = true
        _dragging        = false
        _press_start_pos = get_global_mouse_position()
        _drag_offset     = global_position - _press_start_pos
    else:
        if _dragging:
            # Finger/mouse lifted after a drag — notify layout for slot snapping
            z_index = 0
            drop_shadow.modulate.a = 0.25
            emit_signal("card_dropped", self, global_position)
        else:
            # Finger/mouse lifted without significant movement — it was a tap
            emit_signal("card_clicked", self)
        _input_down = false
        _dragging   = false

func _process(_delta):
    if not _input_down:
        return

    var current_pos := get_global_mouse_position()

    if not _dragging:
        # Promote to drag once movement threshold is crossed
        if current_pos.distance_to(_press_start_pos) > DRAG_THRESHOLD:
            _dragging = true
            z_index   = DRAG_Z_INDEX
            drop_shadow.modulate.a = 0.6

    if _dragging:
        global_position = current_pos + _drag_offset
```

The threshold of 12 px is small enough that intentional drags feel immediate but large enough to absorb the natural finger wobble on a phone screen during what the user intends as a tap.

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

## Canvas Pan and Zoom (Mobile)

A Celtic Cross spread at full card size is wider than a phone screen. The solution is a `Camera2D` the user can pan and pinch-zoom. Cards live in "world" space; the camera moves over them.

```gdscript
# CameraController.gd — attached to Camera2D
const ZOOM_MIN  := Vector2(0.3, 0.3)
const ZOOM_MAX  := Vector2(2.0, 2.0)
const ZOOM_STEP := 0.1   # for mouse wheel on desktop

var _pan_active:      bool    = false
var _pan_start_mouse: Vector2
var _pan_start_cam:   Vector2

# --- Mouse wheel zoom (desktop) ---
func _unhandled_input(event):
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            zoom = (zoom + Vector2(ZOOM_STEP, ZOOM_STEP)).clamp(ZOOM_MIN, ZOOM_MAX)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            zoom = (zoom - Vector2(ZOOM_STEP, ZOOM_STEP)).clamp(ZOOM_MIN, ZOOM_MAX)
        # Right-click or middle-click to pan on desktop
        elif event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
            _pan_active      = event.pressed
            _pan_start_mouse = get_global_mouse_position()
            _pan_start_cam   = global_position

    elif event is InputEventMouseMotion and _pan_active:
        global_position = _pan_start_cam - (get_global_mouse_position() - _pan_start_mouse)

# --- Two-finger pinch zoom + one-finger pan (touch / mobile) ---
# Godot 4: InputEventMagnifyGesture and InputEventPanGesture fire on
# web touch screens when "Emulate Mouse from Touch" is ON.

func _input(event):
    if event is InputEventMagnifyGesture:
        zoom = (zoom * event.factor).clamp(ZOOM_MIN, ZOOM_MAX)
    elif event is InputEventPanGesture:
        global_position -= event.delta / zoom.x
```

**One-finger pan vs card drag**: the camera only pans when the finger lands on empty table space. When it lands on a card, the card's `CollisionArea` consumes the event first, so the camera never receives it.

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
