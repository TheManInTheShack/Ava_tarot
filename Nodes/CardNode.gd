class_name CardNode
extends Control

## A single card on the table. No dragging in this first pass — cards live at
## a fixed slot position; the only interaction is tap-to-act (flip, today),
## gated by `interactive`, which the world/panel sets from the live ACL.
## Ported technique (not code) from Paradotz's Nodes/GraphNode.gd: custom
## _draw() per instance, tap handled in _gui_input.

signal tapped(slot_id: String)

const CARD_SIZE := Vector2(140, 240)

var slot_id: String = ""
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
	rotation = PI if orientation == "reversed" else 0.0


func set_interactive(value: bool) -> void:
	interactive = value
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit(slot_id)
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		tapped.emit(slot_id)
		accept_event()
