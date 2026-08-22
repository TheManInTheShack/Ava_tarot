class_name ConceptNode
extends Control

## A small, non-card table object representing a Planet or Element
## correspondence — appears while any in-play card references it (see
## CardWorld._refresh_concept_nodes()), connected by a line to each such
## card, and disappears once none do. Draggable the same way a loose
## card is (press-then-track, handled by CardWorld — see
## CardWorld._on_concept_drag_pressed()), "same feel" as the existing
## MODIFIES mechanic's connecting line, but this is never itself a
## modifier and never resolves onto a slot — it just floats on the table.

signal drag_pressed(key: String)

const SIZE := Vector2(110.0, 50.0)

## "planet:Mercury" / "element:Air" — CardWorld's own concept key,
## identical to what it uses to track this instance internally. Set by
## CardWorld right after .new(), before add_child().
var key: String = ""

var _label: Label
var _style: StyleBoxFlat


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP

	_style = StyleBoxFlat.new()
	_style.set_corner_radius_all(25)
	_style.set_border_width_all(2)

	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


## kind: "planet" or "element" — purely a color accent (cooler tones for
## Planet, earthier tones for Element, warm gold for Orientation/status),
## not load-bearing; easy to retune.
func setup(display_name: String, kind: String) -> void:
	_label.text = display_name
	var accent: Color
	match kind:
		"planet":
			accent = Color(0.45, 0.6, 0.95)
		"orientation":
			accent = Color(0.85, 0.7, 0.35)
		_:
			accent = Color(0.55, 0.75, 0.4)  # element
	_style.bg_color = Color(accent.r, accent.g, accent.b, 0.22)
	_style.border_color = accent
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _style.bg_color, true)
	draw_rect(Rect2(Vector2.ZERO, size), _style.border_color, false, 2.0)


## Pre-rotation local anchor for CardWorld's line drawing — this node
## never rotates, so unlike CardNode.get_layer_transform() there's nothing
## to strip; plain get_global_transform() * attach_point() is correct as-is.
func attach_point() -> Vector2:
	return Vector2(size.x / 2.0, size.y)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		drag_pressed.emit(key)
		accept_event()
