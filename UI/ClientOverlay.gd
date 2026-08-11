class_name ClientOverlay
extends Control

## Bottom action bar for the client. No menus, no rollups — this is the only
## UI chrome a client-role viewer ever gets, and it only appears when the
## controller has currently granted an action on the card just tapped.

signal action_chosen(slot_id: String, layer: String, action: String)

var _bar: HBoxContainer
var _current_slot: String = ""
var _current_layer: String = "vertical"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	custom_minimum_size = Vector2(0, 80)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.06, 0.92)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	_bar = HBoxContainer.new()
	_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_bar.add_theme_constant_override("separation", 12)
	panel.add_child(_bar)

	hide()


func show_actions(slot_id: String, layer: String, actions: Array) -> void:
	_current_slot = slot_id
	_current_layer = layer
	for c in _bar.get_children():
		c.queue_free()

	if actions.is_empty():
		hide()
		return

	for action in actions:
		var btn := Button.new()
		btn.text = _label_for(String(action))
		btn.custom_minimum_size = Vector2(130, 52)
		btn.pressed.connect(_on_action_pressed.bind(action))
		_bar.add_child(btn)

	var dismiss := Button.new()
	dismiss.text = "Dismiss"
	dismiss.custom_minimum_size = Vector2(110, 52)
	dismiss.pressed.connect(func() -> void: hide())
	_bar.add_child(dismiss)

	show()


func _label_for(action: String) -> String:
	match action:
		"flip":
			return "Flip"
		"point":
			return "Point"
		"pick":
			return "Pick"
		_:
			return action.capitalize()


func _on_action_pressed(action: String) -> void:
	action_chosen.emit(_current_slot, _current_layer, action)
	hide()
