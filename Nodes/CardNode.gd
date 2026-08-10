class_name CardNode
extends Control

## A single card layer on the table. No dragging in this first pass — cards
## live at a fixed slot position; the only interactions are tap-to-act (flip,
## today) and right-click for the context menu, both gated by `interactive`,
## which the world/panel sets from the live ACL.
## Ported technique (not code) from Paradotz's Nodes/GraphNode.gd: custom
## _draw() per instance, tap/right-click handled in _gui_input.

signal tapped(slot_id: String, layer: String)
signal context_requested(slot_id: String, layer: String)

const CARD_SIZE := Vector2(140, 240)

var slot_id: String = ""
var layer: String = "vertical"       # "vertical" (primary) or "horizontal" (crossing/modifier)
var deck_card_id: String = ""
var card_name: String = ""
var face_up: bool = false
var orientation: String = "upright"  # "upright" or "reversed"
var interactive: bool = false        # whether a tap currently does anything

static var back_texture: Texture2D = null
var front_texture: Texture2D = null


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	pivot_offset = CARD_SIZE / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, CARD_SIZE)
	draw_rect(rect, Color(0.08, 0.08, 0.08), true)
	draw_rect(rect, Color(0.3, 0.3, 0.3), false, 2.0)

	if face_up:
		if front_texture != null:
			draw_texture_rect(front_texture, rect, false)
		else:
			draw_string(ThemeDB.fallback_font, Vector2(8, CARD_SIZE.y / 2.0), card_name,
				HORIZONTAL_ALIGNMENT_LEFT, CARD_SIZE.x - 16, 16)
	else:
		if back_texture != null:
			draw_texture_rect(back_texture, rect, false)
		else:
			draw_rect(rect, Color(0.15, 0.1, 0.25), true)

	if interactive:
		draw_rect(rect, Color(0.63, 0.78, 0.2), false, 3.0)


func set_face_up(value: bool) -> void:
	face_up = value
	queue_redraw()


func set_orientation(value: String) -> void:
	orientation = value
	_update_rotation()


func set_layer(value: String) -> void:
	layer = value
	_update_rotation()


## Total rotation combines two independent facts: which layer this is
## (vertical=0°, horizontal=90°, structural) and whether it's reversed
## (+180°, instance-level) — see Meta/Reading-Model.md's structural-vs-
## instance property split.
func _update_rotation() -> void:
	var layer_angle := (PI / 2.0) if layer == "horizontal" else 0.0
	var reversed_angle := PI if orientation == "reversed" else 0.0
	rotation = layer_angle + reversed_angle


func set_interactive(value: bool) -> void:
	interactive = value
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			tapped.emit(slot_id, layer)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			context_requested.emit(slot_id, layer)
			accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		tapped.emit(slot_id, layer)
		accept_event()
