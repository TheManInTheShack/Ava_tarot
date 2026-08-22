class_name InfoWindow
extends Panel

## A "torn away" card-info snapshot — content is frozen at setup() time, not
## live-bound to the graph (Reading-Model's own words: "like a frozen
## context window"). Multiple instances can exist at once; each is fully
## self-contained (own drag state, own close button), unlike Paradotz's
## Editor.gd context panel this was adapted from, which is a hardcoded
## singleton with module-level drag vars and no close button — that
## wouldn't support more than one instance without a real rework, so this
## is a from-scratch instantiable version of the same titlebar-drag idea
## rather than a port of that code.

signal closed(window: InfoWindow)

const WINDOW_SIZE := Vector2(240.0, 0.0)  # height grows to fit content
const TITLEBAR_HEIGHT := 28.0

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _titlebar: Panel
var _body_label: RichTextLabel


func _ready() -> void:
	custom_minimum_size = WINDOW_SIZE
	size = WINDOW_SIZE
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

	_titlebar = Panel.new()
	_titlebar.custom_minimum_size = Vector2(0.0, TITLEBAR_HEIGHT)
	_titlebar.mouse_filter = Control.MOUSE_FILTER_STOP
	var tb_sb := StyleBoxFlat.new()
	tb_sb.bg_color = Color(0.18, 0.18, 0.18)
	tb_sb.corner_radius_top_left = 5
	tb_sb.corner_radius_top_right = 5
	_titlebar.add_theme_stylebox_override("panel", tb_sb)
	_titlebar.gui_input.connect(_on_titlebar_input)
	vbox.add_child(_titlebar)

	var tb_hbox := HBoxContainer.new()
	tb_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tb_hbox.offset_left = 8.0
	tb_hbox.offset_right = -4.0
	_titlebar.add_child(tb_hbox)

	var title_label := Label.new()
	title_label.name = "TitleLabel"
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tb_hbox.add_child(title_label)

	var close_button := Button.new()
	close_button.text = "x"
	close_button.custom_minimum_size = Vector2(24.0, 24.0)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(func() -> void:
		closed.emit(self)
		queue_free()
	)
	tb_hbox.add_child(close_button)

	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", 8)
	body_margin.add_theme_constant_override("margin_right", 8)
	body_margin.add_theme_constant_override("margin_top", 6)
	body_margin.add_theme_constant_override("margin_bottom", 8)
	vbox.add_child(body_margin)

	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.fit_content = true
	_body_label.scroll_active = false
	_body_label.custom_minimum_size = Vector2(WINDOW_SIZE.x - 16.0, 0.0)
	body_margin.add_child(_body_label)


## Frozen at call time — never re-reads the graph afterward.
func setup(header: String, body: String) -> void:
	if is_node_ready():
		_apply_content(header, body)
	else:
		ready.connect(func() -> void: _apply_content(header, body), CONNECT_ONE_SHOT)


func _apply_content(header: String, body: String) -> void:
	var title_label: Label = _titlebar.find_child("TitleLabel", true, false)
	title_label.text = header
	_body_label.text = body


## Same press-then-track-via-_input() technique CardWorld's own slot
## markers use — gui_input alone stops firing the instant the cursor
## leaves the titlebar's own rect mid-drag.
func _on_titlebar_input(event: InputEvent) -> void:
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
