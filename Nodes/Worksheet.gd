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
##
## Two field kinds (2026-08-22): plain text (the default — a TextEdit +
## explicit Save button) and "tag_list" (a resolved node list rendered as
## a removable-chip list plus an Add picker, emitting tag_added/
## tag_removed instead of field_saved — there's no single text value to
## save, and each toggle is meant to write immediately, same as the
## regular Traits rollup's own Add/Remove buttons do). Still fully
## schema-driven: which kind a field is comes from the resolved field
## dict's own "kind" key, not anything hardcoded here.

signal field_saved(window: Worksheet, key: String, text: String)
signal tag_added(window: Worksheet, key: String, item_id: String)
signal tag_removed(window: Worksheet, key: String, item_id: String)

const FIELD_MIN_HEIGHT := 60.0

var _field_edits: Dictionary = {}  # key -> TextEdit
var _fields_vbox: VBoxContainer
var _tag_add_selected: Dictionary = {}  # field key -> currently chosen vocabulary item id (Add picker)

# Per-field vertical resize drag, same press-then-track-via-_input() technique
# FloatingWindow's own bottom/corner handles use — scoped to whichever
# TextEdit's grip is currently held, not the window itself.
var _field_resize_edit: TextEdit = null
var _field_resize_start_mouse: Vector2 = Vector2.ZERO
var _field_resize_start_height: float = 0.0


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
	_tag_add_selected.clear()
	for c in _fields_vbox.get_children():
		c.queue_free()

	for field in fields:
		var key: String = field.get("key", "")
		var label := Label.new()
		label.text = field.get("label", key)
		label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_fields_vbox.add_child(label)

		if field.get("kind", "text") == "tag_list":
			_build_tag_list_field(key, field)
			continue

		var edit := TextEdit.new()
		edit.custom_minimum_size = Vector2(0.0, 100.0)
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		edit.text = field.get("text", "")
		_fields_vbox.add_child(edit)
		_field_edits[key] = edit

		var grip := Control.new()
		grip.custom_minimum_size = Vector2(0.0, 8.0)
		grip.mouse_filter = Control.MOUSE_FILTER_STOP
		grip.mouse_default_cursor_shape = Control.CURSOR_VSIZE
		grip.gui_input.connect(func(event: InputEvent) -> void: _on_field_resize_input(edit, event))
		_fields_vbox.add_child(grip)

		var save_btn := Button.new()
		save_btn.text = "Save"
		save_btn.pressed.connect(func() -> void: field_saved.emit(self, key, edit.text))
		_fields_vbox.add_child(save_btn)


## field: {"key","label","kind":"tag_list","items":[{"id","name"},...] (what
## the resolved query currently matched), "vocabulary":[{"id","name"},...]
## (everything else it could be — plain local data Main.gd already has,
## same as the Traits rollup's own Add picker, not itself a second query)}.
## Each Remove button fires immediately (tag_removed), same as the Add
## button (tag_added) — no batching, no explicit Save, since a single
## toggle is already a complete, well-defined action (matches the regular
## Traits rollup's own Add/Remove buttons exactly).
func _build_tag_list_field(key: String, field: Dictionary) -> void:
	var items: Array = field.get("items", [])
	if items.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(none)"
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_fields_vbox.add_child(empty_label)
	for item in items:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = item.get("name", "")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var remove_btn := Button.new()
		remove_btn.text = "Remove"
		var item_id: String = item.get("id", "")
		remove_btn.pressed.connect(func() -> void: tag_removed.emit(self, key, item_id))
		row.add_child(remove_btn)
		_fields_vbox.add_child(row)

	var vocabulary: Array = field.get("vocabulary", [])
	var add_row := HBoxContainer.new()
	var add_menu := MenuButton.new()
	add_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var popup := add_menu.get_popup()
	for i in range(vocabulary.size()):
		popup.add_item(vocabulary[i].get("name", ""), i)
	if vocabulary.is_empty():
		add_menu.text = "Nothing to add"
	else:
		add_menu.text = vocabulary[0].get("name", "")
		_tag_add_selected[key] = vocabulary[0].get("id", "")
	popup.id_pressed.connect(func(id: int) -> void:
		add_menu.text = vocabulary[id].get("name", "")
		_tag_add_selected[key] = vocabulary[id].get("id", "")
	)
	add_row.add_child(add_menu)

	var add_btn := Button.new()
	add_btn.text = "Add"
	add_btn.disabled = vocabulary.is_empty()
	add_btn.pressed.connect(func() -> void:
		var chosen: String = _tag_add_selected.get(key, "")
		if chosen != "":
			tag_added.emit(self, key, chosen)
	)
	add_row.add_child(add_btn)
	_fields_vbox.add_child(add_row)


func _on_field_resize_input(edit: TextEdit, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_field_resize_edit = edit
			_field_resize_start_mouse = get_global_mouse_position()
			_field_resize_start_height = edit.custom_minimum_size.y
			get_viewport().set_input_as_handled()
		else:
			_field_resize_edit = null


## Only intercepts an active field-grip drag; everything else (window
## drag/resize/roll-up) is FloatingWindow's own concern, untouched.
func _input(event: InputEvent) -> void:
	if _field_resize_edit == null:
		super._input(event)
		return
	if event is InputEventMouseMotion:
		var delta_y: float = get_global_mouse_position().y - _field_resize_start_mouse.y
		_field_resize_edit.custom_minimum_size.y = maxf(FIELD_MIN_HEIGHT, _field_resize_start_height + delta_y)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_field_resize_edit = null
