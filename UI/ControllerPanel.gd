class_name ControllerPanel
extends VBoxContainer

## Minimal rollup-panel side UI for the controller. Pattern ported from
## Paradotz's UI/GraphPanel.gd (_make_sub_rollup / _rollup_color /
## _style_rollup_header / _wrap_rollup_panel): a collapsible, color-coded
## section per concern. Built entirely in code, not a hand-authored .tscn.

signal start_pressed()
signal end_pressed()
signal deal_pressed()
signal acl_changed(slot_id: String, layer: String, is_visible: bool, actions: Array)

const PALETTE := [
	Color(0.29, 0.62, 1.00),  # Blue   — Session
	Color(0.30, 0.85, 0.85),  # Cyan   — Deck
	Color(0.95, 0.75, 0.25),  # Yellow — Client Access
]

var _status_label: Label
var _visible_cbs: Dictionary = {}   # "slot_id:layer" -> CheckBox
var _flip_cbs: Dictionary = {}      # "slot_id:layer" -> CheckBox


func _ready() -> void:
	custom_minimum_size = Vector2(280, 0)
	add_theme_constant_override("separation", 8)

	_build_session_section()
	_build_deck_section()
	_build_cards_section()


func _rollup_color(idx: int) -> Color:
	return PALETTE[idx % PALETTE.size()]


func _style_rollup_header(btn: Button, color: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = color.darkened(0.8)
	normal.border_color = color.darkened(0.45)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(3)
	normal.set_content_margin_all(8)
	var hover := StyleBoxFlat.new()
	hover.bg_color = color.darkened(0.65)
	hover.border_color = color.lightened(0.1)
	hover.set_border_width_all(1)
	hover.set_corner_radius_all(3)
	hover.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)


func _wrap_rollup_panel(form: Control, color: Color, start_visible: bool = true) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.72)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(form)
	panel.visible = start_visible
	return panel


func _make_rollup(title: String, color: Color, form: Control) -> void:
	var btn := Button.new()
	btn.text = title + "  [-]"
	_style_rollup_header(btn, color)
	add_child(btn)

	var wrapped := _wrap_rollup_panel(form, color, true)
	add_child(wrapped)

	btn.pressed.connect(func() -> void:
		wrapped.visible = not wrapped.visible
		btn.text = title + ("  [-]" if wrapped.visible else "  [+]")
	)


func _build_session_section() -> void:
	var form := VBoxContainer.new()
	_status_label = Label.new()
	_status_label.text = "No active reading"
	form.add_child(_status_label)

	var start_btn := Button.new()
	start_btn.text = "Start Reading"
	start_btn.pressed.connect(func() -> void: start_pressed.emit())
	form.add_child(start_btn)

	var end_btn := Button.new()
	end_btn.text = "End Reading"
	end_btn.pressed.connect(func() -> void: end_pressed.emit())
	form.add_child(end_btn)

	_make_rollup("Session", _rollup_color(0), form)


func _build_deck_section() -> void:
	var form := VBoxContainer.new()
	var deal_btn := Button.new()
	deal_btn.text = "Deal Three-Card"
	deal_btn.pressed.connect(func() -> void: deal_pressed.emit())
	form.add_child(deal_btn)
	_make_rollup("Deck", _rollup_color(1), form)


## Slot list is still hardcoded here, same as CardWorld's THREE_CARD_SLOTS —
## becomes data-driven off the real Layout/Slot graph nodes in Step 2.
const SLOT_IDS := ["1", "2", "3"]
const LAYER_LABELS := {"vertical": "Vertical", "horizontal": "Horizontal"}


func _build_cards_section() -> void:
	var form := VBoxContainer.new()
	for slot_id in SLOT_IDS:
		for layer in ["vertical", "horizontal"]:
			var key := "%s:%s" % [slot_id, layer]
			var row := HBoxContainer.new()
			var label := Label.new()
			label.text = "Slot %s — %s" % [slot_id, LAYER_LABELS[layer]]
			label.custom_minimum_size = Vector2(140, 0)
			row.add_child(label)

			var visible_cb := CheckBox.new()
			visible_cb.text = "Visible"
			row.add_child(visible_cb)
			_visible_cbs[key] = visible_cb

			var flip_cb := CheckBox.new()
			flip_cb.text = "Can flip"
			row.add_child(flip_cb)
			_flip_cbs[key] = flip_cb

			var emit_change := func() -> void:
				var actions: Array = ["flip"] if flip_cb.button_pressed else []
				acl_changed.emit(slot_id, layer, visible_cb.button_pressed, actions)
			visible_cb.toggled.connect(func(_v: bool) -> void: emit_change.call())
			flip_cb.toggled.connect(func(_v: bool) -> void: emit_change.call())

			form.add_child(row)
	_make_rollup("Client Access", _rollup_color(2), form)


## Keeps these checkboxes honest when ACL changes from elsewhere (the card's
## own right-click "Show/Hide" menu item) instead of from this panel.
func sync_acl(slot_id: String, layer: String, is_visible: bool, actions: Array) -> void:
	var key := "%s:%s" % [slot_id, layer]
	if _visible_cbs.has(key):
		_visible_cbs[key].set_pressed_no_signal(is_visible)
	if _flip_cbs.has(key):
		_flip_cbs[key].set_pressed_no_signal(actions.has("flip"))


func set_status(text: String) -> void:
	_status_label.text = text
