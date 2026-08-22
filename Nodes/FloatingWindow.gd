class_name FloatingWindow
extends Panel

## Shared chrome for every floating window in Paratarot: a title bar (drag
## handle + roll-up toggle + close button), three resize handles (right/
## bottom/corner), and roll-up collapse. Two known subclasses today:
## `ContextWindow` (read-only property display — Paradotz's node-hover
## panel, ported) and `Worksheet` (an editable form — "ContextWindow in
## reverse": same shell, write instead of read). Split into a real base
## class rather than a mode flag on one class, since the two are
## conceptually distinct even though nearly all their chrome is identical —
## a subclass only needs to override `_build_body()`, everything else here
## is already complete and shared.
##
## Zero dependencies on tarot-specific data, same as `ContextWindow` always
## was — the intended canonical version to copy into Paradotz/Plotz
## alongside it if/when they want the same shell for something of their own.

signal closed(window: FloatingWindow)

const MIN_SIZE := Vector2(220.0, 120.0)
const ROLLED_HEIGHT := 30.0  # just the header row — same idea as Paradotz's own roll-up (title_h)

var _header_label: Label
var _close_button: Button
var _roll_button: Button
var _body_margin: MarginContainer
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _resize_mode: String = ""  # "", "right", "bottom", "corner"
var _resize_start_mouse: Vector2 = Vector2.ZERO
var _resize_start_size: Vector2 = Vector2.ZERO
var _rolled: bool = false
var _unrolled_height: float = 160.0


func _ready() -> void:
	custom_minimum_size = MIN_SIZE
	z_index = 30

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.12)
	sb.border_color = Color(0.32, 0.32, 0.32)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	var header_row := HBoxContainer.new()
	header_row.custom_minimum_size = Vector2(0.0, 28.0)
	header_row.mouse_filter = Control.MOUSE_FILTER_STOP
	header_row.gui_input.connect(_on_header_input)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 4)
	# header_row's parent is a Container (VBoxContainer), which ignores a
	# child's own anchors entirely and sizes it by size_flags instead — a
	# preset-only margin (no expand flag) shrinks to its minimum size and
	# sits at header_row's left edge, taking the label+buttons cluster with
	# it instead of spanning the row, which is why the buttons would read as
	# stuck on the left rather than pinned to the window's right edge.
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	header_row.add_child(margin)
	var header_hbox := HBoxContainer.new()
	margin.add_child(header_hbox)

	_header_label = Label.new()
	_header_label.add_theme_font_size_override("font_size", 15)
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_hbox.add_child(_header_label)

	_roll_button = Button.new()
	_roll_button.text = "v"
	_roll_button.flat = true
	_roll_button.focus_mode = Control.FOCUS_NONE
	_roll_button.custom_minimum_size = Vector2(24.0, 24.0)
	_roll_button.pressed.connect(_toggle_roll)
	header_hbox.add_child(_roll_button)

	_close_button = Button.new()
	_close_button.text = "x"
	_close_button.custom_minimum_size = Vector2(24.0, 24.0)
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.pressed.connect(func() -> void:
		closed.emit(self)
		queue_free()
	)
	header_hbox.add_child(_close_button)

	vbox.add_child(header_row)
	vbox.add_child(HSeparator.new())

	_body_margin = MarginContainer.new()
	_body_margin.add_theme_constant_override("margin_left", 8)
	_body_margin.add_theme_constant_override("margin_right", 8)
	_body_margin.add_theme_constant_override("margin_top", 6)
	_body_margin.add_theme_constant_override("margin_bottom", 8)
	_body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_body_margin)

	_build_body(_body_margin)

	# Anchored (not manually repositioned) so each strip tracks its own edge
	# for free as the panel resizes. Built in this order — corner last —
	# so the small overlapping region at the very corner resolves to the
	# corner handle: later siblings receive input first in Godot.
	_build_resize_handle("right", Control.CURSOR_HSIZE, 1.0, 0.0, 1.0, 1.0, -6.0, 0.0, 0.0, 0.0)
	_build_resize_handle("bottom", Control.CURSOR_VSIZE, 0.0, 1.0, 1.0, 1.0, 0.0, -6.0, 0.0, 0.0)
	_build_resize_handle("corner", Control.CURSOR_FDIAGSIZE, 1.0, 1.0, 1.0, 1.0, -12.0, -12.0, 0.0, 0.0)


## Override in every subclass to populate the body area — ContextWindow
## adds a read-only RichTextLabel, Worksheet adds an editable TextEdit +
## Save button. Base does nothing on its own.
func _build_body(_body_margin_container: MarginContainer) -> void:
	pass


func _build_resize_handle(mode: String, cursor: int, anchor_left: float, anchor_top: float, anchor_right: float, anchor_bottom: float, off_left: float, off_top: float, off_right: float, off_bottom: float) -> void:
	var handle := Control.new()
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = cursor
	handle.anchor_left = anchor_left
	handle.anchor_top = anchor_top
	handle.anchor_right = anchor_right
	handle.anchor_bottom = anchor_bottom
	handle.offset_left = off_left
	handle.offset_top = off_top
	handle.offset_right = off_right
	handle.offset_bottom = off_bottom
	handle.gui_input.connect(func(event: InputEvent) -> void: _on_resize_input(mode, event))
	add_child(handle)


func configure(pos: Vector2, initial_size: Vector2 = Vector2(320.0, 160.0)) -> void:
	position = pos
	size = initial_size
	_unrolled_height = initial_size.y


## For persisting a window's geometry (Paratarot saves the hover window's
## spot per-Layout). Always reports the unrolled height, not whatever
## ROLLED_HEIGHT currently is, so a save made while rolled still restores
## to a sensible size when unrolled later — "rolled" is reported separately
## and re-applied via set_rolled().
func get_geometry() -> Dictionary:
	return {"x": position.x, "y": position.y, "width": size.x, "height": _unrolled_height, "rolled": _rolled}


func set_rolled(value: bool) -> void:
	if value != _rolled:
		_toggle_roll()


## Same idea as Paradotz's own context panel: collapse to just the header
## row, remembering the height to restore on the next toggle. Temporarily
## drops custom_minimum_size's height floor too — otherwise Godot would
## clamp .size.y right back up past ROLLED_HEIGHT.
func _toggle_roll() -> void:
	_rolled = not _rolled
	if _rolled:
		_unrolled_height = size.y
		custom_minimum_size.y = ROLLED_HEIGHT
		size.y = ROLLED_HEIGHT
	else:
		custom_minimum_size.y = MIN_SIZE.y
		size.y = _unrolled_height
	_body_margin.visible = not _rolled
	_roll_button.text = ">" if _rolled else "v"


## Same press-then-track-via-_input() technique CardWorld's own slot
## markers use — gui_input alone stops firing the instant the cursor
## leaves the header row's/handle's own rect mid-drag.
func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = get_global_mouse_position() - position
			get_viewport().set_input_as_handled()
		else:
			_dragging = false


func _on_resize_input(mode: String, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_resize_mode = mode
			_resize_start_mouse = get_global_mouse_position()
			_resize_start_size = size
			get_viewport().set_input_as_handled()
		else:
			_resize_mode = ""


func _input(event: InputEvent) -> void:
	if _dragging:
		if event is InputEventMouseMotion:
			position = get_global_mouse_position() - _drag_offset
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_dragging = false
	elif _resize_mode != "":
		if event is InputEventMouseMotion:
			var delta: Vector2 = get_global_mouse_position() - _resize_start_mouse
			var new_size: Vector2 = _resize_start_size
			if _resize_mode == "right" or _resize_mode == "corner":
				new_size.x = max(MIN_SIZE.x, _resize_start_size.x + delta.x)
			# Rolled: height stays pinned to the header row regardless of a
			# vertical drag — unrolling is the only thing that changes it.
			if not _rolled and (_resize_mode == "bottom" or _resize_mode == "corner"):
				new_size.y = max(MIN_SIZE.y, _resize_start_size.y + delta.y)
				_unrolled_height = new_size.y
			size = new_size
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_resize_mode = ""
