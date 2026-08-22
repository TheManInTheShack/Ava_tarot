class_name Worksheet
extends FloatingWindow

## An editable form — "ContextWindow in reverse": the same floating-window
## shell (drag/resize/roll-up/close, see FloatingWindow) but the body is a
## plain editable TextEdit with an explicit Save button, not a read-only
## BBCode display. Same "explicit Save, not live-per-keystroke" reasoning
## already used everywhere else in this repo (Session Theme, Payment,
## Querent's own old inline field) — a half-typed edit shouldn't get
## written just because the window happened to be open.
##
## First use: Paratarot's Querent worksheet (client notes) — the rollup
## itself now just toggles one of these open/closed rather than holding
## the text inline. Zero client-notes-specific code lives here though;
## like ContextWindow, this takes plain strings and reports plain strings
## back, nothing tarot-specific — same "copy the file, don't share the
## code across repos" candidate for Paradotz/Plotz later.

signal saved(window: Worksheet, text: String)

var _body_edit: TextEdit
var _save_button: Button


func _build_body(body_margin: MarginContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_margin.add_child(vbox)

	_body_edit = TextEdit.new()
	_body_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_body_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_body_edit)

	_save_button = Button.new()
	_save_button.text = "Save"
	_save_button.pressed.connect(func() -> void: saved.emit(self, _body_edit.text))
	vbox.add_child(_save_button)


func set_form(header: String, text: String) -> void:
	if is_node_ready():
		_apply_form(header, text)
	else:
		ready.connect(func() -> void: _apply_form(header, text), CONNECT_ONE_SHOT)


func _apply_form(header: String, text: String) -> void:
	_header_label.text = header
	_body_edit.text = text
