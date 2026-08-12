class_name ControllerPanel
extends VBoxContainer

## Minimal rollup-panel side UI for the controller. Pattern ported from
## Paradotz's UI/GraphPanel.gd (_make_sub_rollup / _rollup_color /
## _style_rollup_header / _wrap_rollup_panel): a collapsible, color-coded
## section per concern. Built entirely in code, not a hand-authored .tscn.

signal start_pressed()
signal record_pressed()
signal end_pressed()
signal deal_pressed()
signal acl_changed(slot_id: String, layer: String, is_visible: bool, actions: Array)
signal layout_selected(layout_id: String)
signal layout_created(name: String)
signal slot_added(name: String, x: float, y: float)
signal slot_updated(slot_id: String, x: float, y: float)
signal slot_deleted(slot_id: String)
signal exit_pressed()

const PALETTE := [
	Color(0.29, 0.62, 1.00),  # Blue   — Session
	Color(0.30, 0.85, 0.85),  # Cyan   — Deck
	Color(0.95, 0.75, 0.25),  # Yellow — Client Access
	Color(0.95, 0.55, 0.20),  # Orange — Layout (spatial/compositional, matches Paradotz's convention)
]

var _status_label: Label
var _version_label: Label
var _visible_cbs: Dictionary = {}   # "slot_id:layer" -> CheckBox
var _flip_cbs: Dictionary = {}      # "slot_id:layer" -> CheckBox
var _cards_form: VBoxContainer
var _layout_menu: MenuButton
var _layout_new_name: LineEdit
var _slot_rows_form: VBoxContainer
var _slot_new_name: LineEdit
var _slot_new_x: SpinBox
var _slot_new_y: SpinBox
var _layouts: Dictionary = {}       # layout_id -> {"name"}, most recent set_layouts() call
var _active_layout_id: String = ""
var _client_menu: MenuButton
var _clients: Array = []            # most recent set_clients() call
var _selected_client_index: int = -1
var _out_of_session_group: VBoxContainer
var _in_session_group: VBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(320, 0)
	add_theme_constant_override("separation", 8)

	var top_row := HBoxContainer.new()
	_version_label = Label.new()
	_version_label.text = "Paratarot"
	_version_label.add_theme_font_size_override("font_size", 16)
	_version_label.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	_version_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(_version_label)

	var exit_btn := Button.new()
	exit_btn.text = "Exit"
	exit_btn.pressed.connect(func() -> void: exit_pressed.emit())
	top_row.add_child(exit_btn)
	add_child(top_row)

	_build_layout_section()
	_build_session_section()
	_build_deck_section()
	_build_cards_section()


func set_version(v: String) -> void:
	_version_label.text = "Paratarot v" + v


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


func _build_layout_section() -> void:
	var form := VBoxContainer.new()

	_layout_menu = MenuButton.new()
	_layout_menu.text = "No Layout"
	_layout_menu.get_popup().id_pressed.connect(_on_layout_menu_id_pressed)
	form.add_child(_layout_menu)

	var new_row := HBoxContainer.new()
	_layout_new_name = LineEdit.new()
	_layout_new_name.placeholder_text = "New layout name"
	_layout_new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_row.add_child(_layout_new_name)
	var new_layout_btn := Button.new()
	new_layout_btn.text = "New Layout"
	new_layout_btn.pressed.connect(func() -> void:
		var n: String = _layout_new_name.text.strip_edges()
		if n != "":
			layout_created.emit(n)
			_layout_new_name.text = ""
	)
	new_row.add_child(new_layout_btn)
	form.add_child(new_row)

	form.add_child(HSeparator.new())

	var slots_label := Label.new()
	slots_label.text = "Slots"
	slots_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	form.add_child(slots_label)

	_slot_rows_form = VBoxContainer.new()
	form.add_child(_slot_rows_form)

	form.add_child(HSeparator.new())

	var add_row := HBoxContainer.new()
	_slot_new_name = LineEdit.new()
	_slot_new_name.placeholder_text = "Slot name"
	_slot_new_name.custom_minimum_size = Vector2(110, 0)
	add_row.add_child(_slot_new_name)
	_slot_new_x = _make_spin_box()
	add_row.add_child(_slot_new_x)
	_slot_new_y = _make_spin_box()
	add_row.add_child(_slot_new_y)
	var add_slot_btn := Button.new()
	add_slot_btn.text = "Add Slot"
	add_slot_btn.pressed.connect(func() -> void:
		var n: String = _slot_new_name.text.strip_edges()
		if n != "":
			slot_added.emit(n, _slot_new_x.value, _slot_new_y.value)
			_slot_new_name.text = ""
	)
	add_row.add_child(add_slot_btn)
	form.add_child(add_row)

	_make_rollup("Layout", _rollup_color(3), form)


## Ported pattern (not code) from Paradotz's NodePanel.gd:_on_delete_pressed —
## same ConfirmationDialog shape, same confirmed/canceled queue_free cleanup.
func _confirm_delete_slot(slot_id: String, slot_name: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Delete Slot"
	dialog.dialog_text = "Delete slot \"%s\"?\nAny card currently placed here will be lost.\nThis cannot be undone." % slot_name
	dialog.ok_button_text = "Delete"
	dialog.cancel_button_text = "Cancel"
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		slot_deleted.emit(slot_id)
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered()


## Floored at 0 — CardWorld's local origin sits immediately right of this
## panel (HBoxContainer sibling layout, not an overlay), and Controls aren't
## clipped to their parent's bounds by default, so a negative coordinate
## would render a slot underneath the panel itself instead of just off the
## visible table.
func _make_spin_box() -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = 0
	sb.max_value = 2000
	sb.step = 1
	sb.custom_minimum_size = Vector2(80, 0)
	return sb


func _on_layout_menu_id_pressed(id: int) -> void:
	var popup := _layout_menu.get_popup()
	var layout_id: String = str(popup.get_item_metadata(popup.get_item_index(id)))
	layout_selected.emit(layout_id)


## layouts: {layout_id: {"name": String}}
func set_layouts(layouts: Dictionary, active_id: String) -> void:
	_layouts = layouts
	_active_layout_id = active_id
	var popup := _layout_menu.get_popup()
	popup.clear()
	var i := 0
	for layout_id in layouts.keys():
		popup.add_item(layouts[layout_id].get("name", layout_id), i)
		popup.set_item_metadata(i, layout_id)
		i += 1
	_layout_menu.text = layouts.get(active_id, {}).get("name", "No Layout")


## slots: {slot_id: {"name": String, "x": float, "y": float}} — the active
## layout's slots. Rebuilds both this section's editable rows and Client
## Access's per-layer rows, since they always change together.
func set_slots(slots: Dictionary) -> void:
	for c in _slot_rows_form.get_children():
		c.queue_free()
	for slot_id in slots.keys():
		var info: Dictionary = slots[slot_id]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = info.get("name", slot_id)
		label.custom_minimum_size = Vector2(90, 0)
		row.add_child(label)

		var x_box := _make_spin_box()
		x_box.value = info.get("x", 0.0)
		row.add_child(x_box)
		var y_box := _make_spin_box()
		y_box.value = info.get("y", 0.0)
		row.add_child(y_box)

		var save_btn := Button.new()
		save_btn.text = "Save"
		save_btn.pressed.connect(func() -> void: slot_updated.emit(slot_id, x_box.value, y_box.value))
		row.add_child(save_btn)

		var del_btn := Button.new()
		del_btn.text = "Delete"
		var slot_name: String = info.get("name", slot_id)
		del_btn.pressed.connect(func() -> void: _confirm_delete_slot(slot_id, slot_name))
		row.add_child(del_btn)

		_slot_rows_form.add_child(row)

	_refresh_cards_section(slots)


## Split per Meta/Reading-Model.md's controller panel structure: the client
## picker + Start belong to the out-of-session tier, Record Scenario/End
## Reading to the in-session tier — never shown together, see set_in_session().
func _build_session_section() -> void:
	var form := VBoxContainer.new()

	_status_label = Label.new()
	_status_label.text = "No active reading"
	form.add_child(_status_label)

	_out_of_session_group = VBoxContainer.new()
	var client_label := Label.new()
	client_label.text = "Client"
	client_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_out_of_session_group.add_child(client_label)

	_client_menu = MenuButton.new()
	_client_menu.text = "No clients"
	_client_menu.get_popup().id_pressed.connect(_on_client_menu_id_pressed)
	_out_of_session_group.add_child(_client_menu)

	var start_btn := Button.new()
	start_btn.text = "Start Reading"
	start_btn.pressed.connect(func() -> void: start_pressed.emit())
	_out_of_session_group.add_child(start_btn)
	form.add_child(_out_of_session_group)

	_in_session_group = VBoxContainer.new()
	var record_btn := Button.new()
	record_btn.text = "Record Scenario"
	record_btn.pressed.connect(func() -> void: record_pressed.emit())
	_in_session_group.add_child(record_btn)

	var end_btn := Button.new()
	end_btn.text = "End Reading"
	end_btn.pressed.connect(func() -> void: end_pressed.emit())
	_in_session_group.add_child(end_btn)
	form.add_child(_in_session_group)

	_make_rollup("Session", _rollup_color(0), form)
	set_in_session(false)


## Toggles which Session controls are shown — client picker/Start when out of
## session, Record Scenario/End Reading when in one. Reading-Model.md: "what
## it does depends on IN_SESSION vs. OUT_OF_SESSION."
func set_in_session(in_session: bool) -> void:
	_out_of_session_group.visible = not in_session
	_in_session_group.visible = in_session


## clients: [{"id": int, "username": String, "display_name": String|null}, ...]
## — public-role accounts from GET /auth/clients.
func set_clients(clients: Array) -> void:
	_clients = clients
	var popup := _client_menu.get_popup()
	popup.clear()
	for i in range(clients.size()):
		var c: Dictionary = clients[i]
		var label: String = c.get("display_name", "") if c.get("display_name", "") else c.get("username", "")
		popup.add_item(label, i)
	if clients.is_empty():
		_client_menu.text = "No clients"
	else:
		_selected_client_index = 0
		_client_menu.text = _label_for_client(clients[0])


func _label_for_client(c: Dictionary) -> String:
	var dn: String = c.get("display_name", "")
	return dn if dn else c.get("username", "")


func _on_client_menu_id_pressed(id: int) -> void:
	_selected_client_index = id
	_client_menu.text = _label_for_client(_clients[id])


## Returns {} if no client is selected (e.g. the picker is still empty).
func get_selected_client() -> Dictionary:
	if _selected_client_index < 0 or _selected_client_index >= _clients.size():
		return {}
	return _clients[_selected_client_index]


func _build_deck_section() -> void:
	var form := VBoxContainer.new()
	var deal_btn := Button.new()
	deal_btn.text = "Deal Three-Card"
	deal_btn.pressed.connect(func() -> void: deal_pressed.emit())
	form.add_child(deal_btn)
	_make_rollup("Deck", _rollup_color(1), form)


const LAYER_LABELS := {"vertical": "Vertical", "horizontal": "Horizontal"}


func _build_cards_section() -> void:
	_cards_form = VBoxContainer.new()
	_make_rollup("Client Access", _rollup_color(2), _cards_form)


## Rows are data-driven off the active Layout's real Slot list (set_slots()),
## not a hardcoded slot count — see Meta/Reading-Model.md Step 2.
func _refresh_cards_section(slots: Dictionary) -> void:
	for c in _cards_form.get_children():
		c.queue_free()
	_visible_cbs.clear()
	_flip_cbs.clear()
	for slot_id in slots.keys():
		var slot_name: String = slots[slot_id].get("name", slot_id)
		for layer in ["vertical", "horizontal"]:
			var key := "%s:%s" % [slot_id, layer]
			var row := HBoxContainer.new()
			var label := Label.new()
			label.text = "%s — %s" % [slot_name, LAYER_LABELS[layer]]
			label.custom_minimum_size = Vector2(160, 0)
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

			_cards_form.add_child(row)


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
