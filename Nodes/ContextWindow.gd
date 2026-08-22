class_name ContextWindow
extends Panel

## A reusable "context window": a header + BBCode property body, shown
## either docked (one fixed instance, content updates live, e.g. on hover)
## or floating (any number of independent, draggable, closable snapshots).
## Deliberately zero dependencies on tarot-specific data — set_content()
## takes plain strings, nothing else. This is the canonical version to copy
## into Paradotz/Plotz if/when they want the same thing (their own
## node-hover context panel and property inspector, respectively) — these
## three Godot projects have no shared-package mechanism between them, so
## "reusable" means "the same well-designed file," same as other ported
## techniques already noted between them (pan/zoom, drag-then-track).
##
## Two configurations of the same object, not two implementations:
## docked (Paratarot's bottom info bar) has no titlebar chrome and can't be
## dragged or closed; floating (a torn-away snapshot) has both. Both share
## the same header row and body RichTextLabel underneath.

signal closed(window: ContextWindow)

var _header_label: Label
var _close_button: Button
var _body_label: RichTextLabel
var _draggable: bool = false
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
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
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header_row.add_child(margin)
	var header_hbox := HBoxContainer.new()
	margin.add_child(header_hbox)

	_header_label = Label.new()
	_header_label.add_theme_font_size_override("font_size", 15)
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_hbox.add_child(_header_label)

	_close_button = Button.new()
	_close_button.text = "x"
	_close_button.custom_minimum_size = Vector2(24.0, 24.0)
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.visible = false
	_close_button.pressed.connect(func() -> void:
		closed.emit(self)
		queue_free()
	)
	header_hbox.add_child(_close_button)

	vbox.add_child(header_row)
	vbox.add_child(HSeparator.new())

	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 8)
	body_margin.add_theme_constant_override("margin_right", 8)
	body_margin.add_theme_constant_override("margin_top", 6)
	body_margin.add_theme_constant_override("margin_bottom", 8)
	body_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body_margin)

	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	body_margin.add_child(_body_label)


## Floating: fixed width, positioned once, draggable via its own header
## row, closable. Body grows to fit its content — a one-off snapshot never
## needs to scroll.
func configure_floating(pos: Vector2, width: float = 260.0) -> void:
	_draggable = true
	_close_button.visible = true
	z_index = 30
	custom_minimum_size = Vector2(width, 0.0)
	position = pos
	_body_label.custom_minimum_size = Vector2(width - 16.0, 0.0)
	_body_label.fit_content = true
	_body_label.scroll_active = false


## Docked: anchored to span from left_offset to the right edge (clearing
## whatever sits to the left — Paratarot's side rollup panel, in
## particular — not just the table), pinned to the bottom edge at a fixed
## height. Not draggable, no close button — this instance is meant to
## always be there. Content updates live (set_content() called repeatedly)
## rather than being a one-time snapshot, so the body scrolls internally
## instead of growing the bar past its fixed footprint.
func configure_docked(left_offset: float, height: float) -> void:
	_draggable = false
	_close_button.visible = false
	z_index = 15
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = left_offset
	offset_right = 0.0
	offset_top = -height
	offset_bottom = 0.0
	_body_label.custom_minimum_size = Vector2(0.0, 0.0)
	_body_label.fit_content = false
	_body_label.scroll_active = true


func set_content(header: String, body: String) -> void:
	if is_node_ready():
		_apply_content(header, body)
	else:
		ready.connect(func() -> void: _apply_content(header, body), CONNECT_ONE_SHOT)


func _apply_content(header: String, body: String) -> void:
	_header_label.text = header
	_body_label.text = body


## Same press-then-track-via-_input() technique CardWorld's own slot
## markers use — gui_input alone stops firing the instant the cursor
## leaves the header row's own rect mid-drag.
func _on_header_input(event: InputEvent) -> void:
	if not _draggable:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = get_global_mouse_position() - position
			get_viewport().set_input_as_handled()
		else:
			_dragging = false


func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseMotion:
		position = get_global_mouse_position() - _drag_offset
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
