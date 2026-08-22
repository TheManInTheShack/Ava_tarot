class_name ContextWindow
extends FloatingWindow

## A read-only "context window": a header + BBCode property body — Paradotz's
## node-hover context panel, ported. See FloatingWindow's own doc for why
## this is a subclass (shared chrome) rather than a mode flag, and for the
## "canonical version to copy elsewhere" note.
##
## Every instance is the same kind of object, "context windows that can
## exist simultaneously" — Paratarot's hover window is just the first one,
## given a default near-the-bottom position/size via configure(); it isn't
## docked or anchored, the user can drag/resize/roll-up/close it exactly
## like any window a right-click "Show Detail" spawns.

var _body_label: RichTextLabel


func _build_body(body_margin: MarginContainer) -> void:
	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.scroll_active = true
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_margin.add_child(_body_label)


func set_content(header: String, body: String) -> void:
	if is_node_ready():
		_apply_content(header, body)
	else:
		ready.connect(func() -> void: _apply_content(header, body), CONNECT_ONE_SHOT)


func _apply_content(header: String, body: String) -> void:
	_header_label.text = header
	_body_label.text = body
