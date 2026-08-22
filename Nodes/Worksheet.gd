class_name Worksheet
extends FloatingWindow

## An editable form — "ContextWindow in reverse": the same floating-window
## shell (drag/resize/roll-up/close, see FloatingWindow) but the body is a
## dynamic list of plain editable fields, each with its own explicit Save
## button, not a read-only BBCode display. Same "explicit Save, not
## live-per-keystroke" reasoning already used everywhere else in this repo.
##
## Schema-driven, per the Querent worksheet's own design: the *set* of
## fields shown isn't fixed by this class at all — Main.gd resolves
## however many graph_query-shaped properties the backing Worksheet graph
## node currently has (see Main._resolve_worksheet_fields()) and hands
## them here as a plain list. Zero client-notes-specific code lives here —
## like ContextWindow, this takes plain data in and reports plain data
## back, nothing tarot-specific.

signal field_saved(window: Worksheet, key: String, text: String)

var _field_edits: Dictionary = {}  # key -> TextEdit
var _fields_vbox: VBoxContainer


func _build_body(body_margin: MarginContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_margin.add_child(scroll)

	_fields_vbox = VBoxContainer.new()
	_fields_vbox.add_theme_constant_override("separation", 10)
	_fields_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_fields_vbox)


## Shown immediately on open/refresh, before the (possibly several) queries
## that resolve each field's actual value have come back — otherwise the
## window sits blank for however long that round trip takes, with nothing
## telling the user it's actually doing something.
func set_loading(header: String) -> void:
	if is_node_ready():
		_apply_loading(header)
	else:
		ready.connect(func() -> void: _apply_loading(header), CONNECT_ONE_SHOT)


func _apply_loading(header: String) -> void:
	_header_label.text = header
	_field_edits.clear()
	for c in _fields_vbox.get_children():
		c.queue_free()
	var loading_label := Label.new()
	loading_label.text = "Loading..."
	loading_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_fields_vbox.add_child(loading_label)


## fields: [{"key": String, "label": String, "text": String}, ...] — however
## many graph_query-shaped properties the backing Worksheet node currently
## has, resolved to their current text. Rebuilds the whole field list each
## call (open, or a focus-change refresh) — any unsaved typed text is
## discarded, same tradeoff already accepted elsewhere in this repo for a
## selection switch mid-edit.
func set_fields(header: String, fields: Array) -> void:
	if is_node_ready():
		_apply_fields(header, fields)
	else:
		ready.connect(func() -> void: _apply_fields(header, fields), CONNECT_ONE_SHOT)


func _apply_fields(header: String, fields: Array) -> void:
	_header_label.text = header
	_field_edits.clear()
	for c in _fields_vbox.get_children():
		c.queue_free()

	for field in fields:
		var key: String = field.get("key", "")
		var label := Label.new()
		label.text = field.get("label", key)
		label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_fields_vbox.add_child(label)

		var edit := TextEdit.new()
		edit.custom_minimum_size = Vector2(0.0, 100.0)
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		edit.text = field.get("text", "")
		_fields_vbox.add_child(edit)
		_field_edits[key] = edit

		var save_btn := Button.new()
		save_btn.text = "Save"
		save_btn.pressed.connect(func() -> void: field_saved.emit(self, key, edit.text))
		_fields_vbox.add_child(save_btn)
