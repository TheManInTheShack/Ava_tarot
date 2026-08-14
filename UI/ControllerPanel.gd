class_name ControllerPanel
extends VBoxContainer

## Minimal rollup-panel side UI for the controller. Pattern ported from
## Paradotz's UI/GraphPanel.gd (_make_sub_rollup / _rollup_color /
## _style_rollup_header / _wrap_rollup_panel): a collapsible, color-coded
## section per concern. Built entirely in code, not a hand-authored .tscn.

signal start_pressed()
signal record_pressed()
signal end_pressed()
signal reset_pressed()
signal reshuffle_pressed()
signal unshuffle_pressed()
signal deal_next_pressed()
signal deal_to_slot_pressed(slot_id: String, layer: String)
signal deal_loose_pressed()
signal acl_changed(slot_id: String, layer: String, is_visible: bool, actions: Array)
signal layout_selected(layout_id: String)
signal layout_created(name: String)
signal layout_deleted(layout_id: String)
signal layout_mod_mode_changed(on: bool)
signal slot_added(name: String, x: float, y: float)
signal slots_saved(updates: Array)  # [{"slot_id","x","y"}, ...] — Save Layout's batch commit
signal slot_deleted(slot_id: String)
signal trait_created(name: String)
signal trait_toggled(trait_id: String, has_trait: bool)
signal client_focus_changed()
signal exit_pressed()

const PALETTE := [
	Color(0.29, 0.62, 1.00),  # Blue   — Session
	Color(0.30, 0.85, 0.85),  # Cyan   — Deck
	Color(0.95, 0.75, 0.25),  # Yellow — Client Access
	Color(0.95, 0.55, 0.20),  # Orange — Layout (spatial/compositional, matches Paradotz's convention)
	Color(0.75, 0.45, 0.95),  # Violet — Traits
]

## (0,0) landed a new slot right behind the panel, in the one corner of the
## table nothing is ever clipped away from (Controls aren't clipped to their
## parent's bounds by default — see _make_spin_box()'s own note on the same
## problem). Roughly centered in the visible table area instead.
const DEFAULT_NEW_SLOT_POS := Vector2(300.0, 300.0)

var _status_label: Label
var _version_label: Label
var _visible_cbs: Dictionary = {}   # "slot_id:layer" -> CheckBox
var _flip_cbs: Dictionary = {}      # "slot_id:layer" -> CheckBox
var _cards_form: VBoxContainer
var _layout_menu: MenuButton
var _layout_modify_btn: Button
var _layout_new_row: HBoxContainer
var _layout_new_name: LineEdit
var _layout_mod_group: VBoxContainer
var _layout_mod_mode: bool = false
var _slot_rows_form: VBoxContainer
var _slot_row_boxes: Dictionary = {}  # slot_id -> {"x": SpinBox, "y": SpinBox}, read by Save Layout
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
var _slots_cache: Dictionary = {}   # most recent set_slots() call, for menu labels
var _deck_slot_menu: MenuButton
var _deck_slot_options: Array = []  # [{"slot_id","layer"}], parallel to popup item ids
var _deck_slot_selected_index: int = -1
var _traits_form: VBoxContainer
var _traits_focus_label: Label
var _trait_new_name: LineEdit


func _ready() -> void:
	# Width is enforced externally now (Main.gd wraps this node in a fixed-
	# width ScrollContainer with SIZE_EXPAND_FILL) — see Main.gd's PANEL_W.
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
	_build_traits_section()
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


## Two tiers: a browse row (dropdown + Modify) always visible, and a
## modification group (slot list, add-slot fields, Delete Layout) shown only
## once Modify is pressed — the rollup starts on "what layout am I looking
## at," not the editing furniture. Picking "+ New Layout" from the dropdown
## doesn't create anything by itself; it reveals an inline name prompt,
## and only submitting that prompt actually creates the layout (and enters
## modification mode for it automatically).
func _build_layout_section() -> void:
	var form := VBoxContainer.new()

	var browse_row := HBoxContainer.new()
	_layout_menu = MenuButton.new()
	_layout_menu.text = "No Layout"
	_layout_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout_menu.get_popup().id_pressed.connect(_on_layout_menu_id_pressed)
	browse_row.add_child(_layout_menu)
	_layout_modify_btn = Button.new()
	_layout_modify_btn.text = "Modify"
	_layout_modify_btn.pressed.connect(func() -> void:
		if _layout_mod_mode:
			_commit_and_exit_layout_mod_mode()
		else:
			set_layout_mod_mode(true)
	)
	browse_row.add_child(_layout_modify_btn)
	form.add_child(browse_row)

	_layout_new_row = HBoxContainer.new()
	_layout_new_row.visible = false
	_layout_new_name = LineEdit.new()
	_layout_new_name.placeholder_text = "New layout name"
	_layout_new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout_new_row.add_child(_layout_new_name)
	var create_btn := Button.new()
	create_btn.text = "Create"
	create_btn.pressed.connect(func() -> void:
		var n: String = _layout_new_name.text.strip_edges()
		if n != "":
			layout_created.emit(n)
			_layout_new_name.text = ""
			_layout_new_row.visible = false
			# Entering mod mode happens on Main.gd's side (a plain
			# set_layout_mod_mode(true) call) once the new layout actually
			# becomes active — doing it here instead used to flash the OLD
			# layout's slot list for a frame before the async graph write
			# landed and swapped it.
	)
	_layout_new_row.add_child(create_btn)
	form.add_child(_layout_new_row)

	_layout_mod_group = VBoxContainer.new()
	_layout_mod_group.visible = false

	var slots_label := Label.new()
	slots_label.text = "Slots"
	slots_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_layout_mod_group.add_child(slots_label)

	_slot_rows_form = VBoxContainer.new()
	_layout_mod_group.add_child(_slot_rows_form)

	_layout_mod_group.add_child(HSeparator.new())

	var add_row := HBoxContainer.new()
	_slot_new_name = LineEdit.new()
	_slot_new_name.placeholder_text = "Slot name"
	_slot_new_name.custom_minimum_size = Vector2(110, 0)
	add_row.add_child(_slot_new_name)
	_slot_new_x = _make_spin_box()
	_slot_new_x.value = DEFAULT_NEW_SLOT_POS.x
	add_row.add_child(_slot_new_x)
	_slot_new_y = _make_spin_box()
	_slot_new_y.value = DEFAULT_NEW_SLOT_POS.y
	add_row.add_child(_slot_new_y)
	var add_slot_btn := Button.new()
	add_slot_btn.text = "Add Slot"
	add_slot_btn.pressed.connect(func() -> void:
		var n: String = _slot_new_name.text.strip_edges()
		if n != "":
			var pos: Vector2 = _find_clear_slot_position(Vector2(_slot_new_x.value, _slot_new_y.value))
			slot_added.emit(n, pos.x, pos.y)
			_slot_new_name.text = ""
			# Reflects where it actually landed, and means adding several
			# slots in a row without touching x/y keeps nudging rightward
			# from the last one instead of re-colliding with it every time.
			_slot_new_x.value = pos.x
			_slot_new_y.value = pos.y
	)
	add_row.add_child(add_slot_btn)
	_layout_mod_group.add_child(add_row)

	_layout_mod_group.add_child(HSeparator.new())

	var delete_layout_btn := Button.new()
	delete_layout_btn.text = "Delete Layout"
	delete_layout_btn.pressed.connect(_confirm_delete_layout)
	_layout_mod_group.add_child(delete_layout_btn)

	form.add_child(_layout_mod_group)

	_make_rollup("Layout", _rollup_color(3), form)


## Public: Main.gd calls this directly too, once a freshly-created layout
## has actually become active (not from the Create button itself — doing it
## there raced the async graph write and flashed the previous layout's slot
## list for a frame first). CardWorld also listens to layout_mod_mode_changed
## directly, to show/hide the draggable slot markers only in mod mode — no
## drag input active at all outside it.
func set_layout_mod_mode(on: bool) -> void:
	_layout_mod_mode = on
	_layout_mod_group.visible = on
	_layout_modify_btn.text = "Save Layout" if on else "Modify"
	layout_mod_mode_changed.emit(on)


## The Modify button becomes "Save Layout" while in mod mode (see above) —
## clicking it then commits every slot row's current x/y in one batch
## (there are no more per-row Save buttons) and exits mod mode. Dragging a
## slot on the table still commits immediately on drop, same as before;
## this is specifically for the numeric-field editing path.
func _commit_and_exit_layout_mod_mode() -> void:
	var updates: Array = []
	for slot_id in _slot_row_boxes.keys():
		var boxes: Dictionary = _slot_row_boxes[slot_id]
		updates.append({"slot_id": slot_id, "x": boxes["x"].value, "y": boxes["y"].value})
	if not updates.is_empty():
		slots_saved.emit(updates)
	set_layout_mod_mode(false)


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


func _confirm_delete_layout() -> void:
	if _active_layout_id == "" or not _layouts.has(_active_layout_id):
		return
	var layout_name: String = _layouts[_active_layout_id].get("name", _active_layout_id)
	var dialog := ConfirmationDialog.new()
	dialog.title = "Delete Layout"
	dialog.dialog_text = "Delete layout \"%s\"?\nAll of its slots, and any cards currently placed on them, will be lost.\nThis cannot be undone." % layout_name
	dialog.ok_button_text = "Delete"
	dialog.cancel_button_text = "Cancel"
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		layout_deleted.emit(_active_layout_id)
		set_layout_mod_mode(false)  # no commit here — the layout itself is gone
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered()


## Floored at 0 — CardWorld's local origin sits at Main.gd's PANEL_W offset
## from the window's left edge, and Controls aren't clipped to their
## parent's bounds by default, so a negative coordinate would render a slot
## underneath the panel itself instead of just off the visible table.
func _make_spin_box() -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = 0
	sb.max_value = 2000
	sb.step = 1
	sb.custom_minimum_size = Vector2(80, 0)
	return sb


## Nudges rightward by a full slot-width step (card + collision margin)
## until clear of every existing slot in the active layout, so adding
## several slots in a row without touching the x/y fields doesn't stack
## them all on top of each other — same collision rule CardWorld's drag
## snap-back uses (CardNode.slot_collision_rect), so the two never disagree
## about what counts as too close.
func _find_clear_slot_position(start: Vector2) -> Vector2:
	var step := CardNode.CARD_SIZE.x + CardNode.SLOT_MARGIN_X * 2.0
	var pos := start
	var guard := 0
	while _overlaps_existing_slot(pos) and guard < 100:
		pos.x += step
		guard += 1
	return pos


func _overlaps_existing_slot(pos: Vector2) -> bool:
	var rect := CardNode.slot_collision_rect(pos)
	for slot_id in _slots_cache.keys():
		var g: Dictionary = _slots_cache[slot_id]
		var other_rect := CardNode.slot_collision_rect(Vector2(g.get("x", 0.0), g.get("y", 0.0)))
		if rect.intersects(other_rect):
			return true
	return false


const NEW_LAYOUT_SENTINEL := "__new_layout__"


func _on_layout_menu_id_pressed(id: int) -> void:
	var popup := _layout_menu.get_popup()
	var layout_id: String = str(popup.get_item_metadata(popup.get_item_index(id)))
	if layout_id == NEW_LAYOUT_SENTINEL:
		_layout_new_row.visible = true
		_layout_new_name.grab_focus()
		return
	_layout_new_row.visible = false
	# Switching which layout you're looking at exits modification mode
	# without committing pending row edits — mod mode is tied to a specific
	# layout's slots, not a general-purpose toggle, so carrying it over onto
	# a different selection would leave "Save Layout" pointing at the wrong
	# one. Explicit Save Layout is the only thing that commits row edits;
	# switching away is "I didn't save that."
	if _layout_mod_mode:
		set_layout_mod_mode(false)
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
	popup.add_separator()
	popup.add_item("+ New Layout", i)
	# set_item_metadata takes a positional index, not the item's id — a
	# separator is a real entry in the popup's item list, so it shifts the
	# "+ New Layout" item's actual position past i by one. get_item_count()-1
	# always points at whatever was just added, regardless of separators.
	popup.set_item_metadata(popup.get_item_count() - 1, NEW_LAYOUT_SENTINEL)
	_layout_menu.text = layouts.get(active_id, {}).get("name", "No Layout")


## slots: {slot_id: {"name": String, "x": float, "y": float}} — the active
## layout's slots. Rebuilds both this section's editable rows and Client
## Access's per-layer rows, since they always change together.
## No per-row Save button anymore — a row's x/y fields are just pending
## edits until "Save Layout" (the Modify button's label while in mod mode)
## commits every row at once and exits mod mode. _slot_row_boxes is what
## that commit reads from.
func set_slots(slots: Dictionary) -> void:
	_slots_cache = slots
	for c in _slot_rows_form.get_children():
		c.queue_free()
	_slot_row_boxes.clear()
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
		_slot_row_boxes[slot_id] = {"x": x_box, "y": y_box}

		var del_btn := Button.new()
		del_btn.text = "Delete"
		var slot_name: String = info.get("name", slot_id)
		del_btn.pressed.connect(func() -> void: _confirm_delete_slot(slot_id, slot_name))
		row.add_child(del_btn)

		_slot_rows_form.add_child(row)

	_refresh_cards_section(slots)
	_refresh_deck_slot_menu(slots)


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
	client_focus_changed.emit()  # Traits section reads whoever's picked here when out of session


## Returns {} if no client is selected (e.g. the picker is still empty).
func get_selected_client() -> Dictionary:
	if _selected_client_index < 0 or _selected_client_index >= _clients.size():
		return {}
	return _clients[_selected_client_index]


## State-independent (per Reading-Model.md, works in or out of a session) —
## Reset/Reshuffle/Unshuffle/Deal Next/Deal to Slot/Deal Loose. A loose
## card's only way to attach to something today is the right-click "Modify
## Card" path (Reading-Model.md's path 1) — drag-and-drop (path 2, Step 5's
## other half) needs real mouse-drag input handling, deliberately held back
## until it can be tested hands-on rather than shipped blind.
func _build_deck_section() -> void:
	var form := VBoxContainer.new()

	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.pressed.connect(func() -> void: reset_pressed.emit())
	form.add_child(reset_btn)

	var shuffle_row := HBoxContainer.new()
	var reshuffle_btn := Button.new()
	reshuffle_btn.text = "Reshuffle"
	reshuffle_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reshuffle_btn.pressed.connect(func() -> void: reshuffle_pressed.emit())
	shuffle_row.add_child(reshuffle_btn)
	var unshuffle_btn := Button.new()
	unshuffle_btn.text = "Unshuffle"
	unshuffle_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unshuffle_btn.pressed.connect(func() -> void: unshuffle_pressed.emit())
	shuffle_row.add_child(unshuffle_btn)
	form.add_child(shuffle_row)

	form.add_child(HSeparator.new())

	var deal_next_btn := Button.new()
	deal_next_btn.text = "Deal Next"
	deal_next_btn.pressed.connect(func() -> void: deal_next_pressed.emit())
	form.add_child(deal_next_btn)

	var deal_slot_row := HBoxContainer.new()
	_deck_slot_menu = MenuButton.new()
	_deck_slot_menu.text = "No slots"
	_deck_slot_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deck_slot_menu.get_popup().id_pressed.connect(_on_deck_slot_menu_id_pressed)
	deal_slot_row.add_child(_deck_slot_menu)
	var deal_to_slot_btn := Button.new()
	deal_to_slot_btn.text = "Deal to Slot"
	deal_to_slot_btn.pressed.connect(func() -> void:
		if _deck_slot_selected_index < 0 or _deck_slot_selected_index >= _deck_slot_options.size():
			return
		var opt: Dictionary = _deck_slot_options[_deck_slot_selected_index]
		deal_to_slot_pressed.emit(opt["slot_id"], opt["layer"])
	)
	deal_slot_row.add_child(deal_to_slot_btn)
	form.add_child(deal_slot_row)

	var deal_loose_btn := Button.new()
	deal_loose_btn.text = "Deal Loose"
	deal_loose_btn.pressed.connect(func() -> void: deal_loose_pressed.emit())
	form.add_child(deal_loose_btn)

	_make_rollup("Deck", _rollup_color(1), form)


func _deck_slot_label(opt: Dictionary) -> String:
	var slot_name: String = _slots_cache.get(opt["slot_id"], {}).get("name", opt["slot_id"])
	return "%s — %s" % [slot_name, LAYER_LABELS.get(opt["layer"], opt["layer"])]


func _refresh_deck_slot_menu(slots: Dictionary) -> void:
	_deck_slot_options.clear()
	var popup := _deck_slot_menu.get_popup()
	popup.clear()
	for slot_id in slots.keys():
		for layer in ["vertical", "horizontal"]:
			var opt := {"slot_id": slot_id, "layer": layer}
			popup.add_item(_deck_slot_label(opt), _deck_slot_options.size())
			_deck_slot_options.append(opt)
	if _deck_slot_options.is_empty():
		_deck_slot_menu.text = "No slots"
		_deck_slot_selected_index = -1
	else:
		_deck_slot_selected_index = 0
		_deck_slot_menu.text = _deck_slot_label(_deck_slot_options[0])


func _on_deck_slot_menu_id_pressed(id: int) -> void:
	_deck_slot_selected_index = id
	_deck_slot_menu.text = _deck_slot_label(_deck_slot_options[id])


## State-independent (per Reading-Model.md) — "the Trait vocabulary and
## assign to whichever Client is currently in focus." A checkbox list rather
## than a full editor: this is a shortcut into the same HAS_TRAIT graph
## write Paradotz itself could make, not a separate rules engine.
func _build_traits_section() -> void:
	var form := VBoxContainer.new()

	_traits_focus_label = Label.new()
	_traits_focus_label.text = "No client selected"
	_traits_focus_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	form.add_child(_traits_focus_label)
	form.add_child(HSeparator.new())

	# The live vocabulary is already 80 traits (seed-personas.js's OCEAN bank)
	# — one checkbox per trait in a plain VBoxContainer would run to ~2000px,
	# taller than the whole 1080px viewport, with no other section of this
	# panel having any scroll story to fall back on. Bounded ScrollContainer
	# so the list scrolls internally instead of blowing out the panel.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	form.add_child(scroll)

	_traits_form = VBoxContainer.new()
	_traits_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_traits_form)

	form.add_child(HSeparator.new())

	var add_row := HBoxContainer.new()
	_trait_new_name = LineEdit.new()
	_trait_new_name.placeholder_text = "New trait name"
	_trait_new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(_trait_new_name)
	var add_btn := Button.new()
	add_btn.text = "Add Trait"
	add_btn.pressed.connect(func() -> void:
		var n: String = _trait_new_name.text.strip_edges()
		if n != "":
			trait_created.emit(n)
			_trait_new_name.text = ""
	)
	add_row.add_child(add_btn)
	form.add_child(add_row)

	_make_rollup("Traits", _rollup_color(4), form)


## traits: {trait_id: name} — the full vocabulary. client_trait_ids:
## {trait_id: true} — which of those the focused client currently has.
## focus_label: "" when no client is focused (picker empty, out of
## session) — checkboxes are shown disabled in that case rather than
## hidden, so the vocabulary itself is still visible/reviewable.
func set_traits(traits: Dictionary, client_trait_ids: Dictionary, focus_label: String) -> void:
	_traits_focus_label.text = ("Traits for %s" % focus_label) if focus_label != "" else "No client selected"

	for c in _traits_form.get_children():
		c.queue_free()

	var has_focus: bool = focus_label != ""
	for trait_id in traits.keys():
		var cb := CheckBox.new()
		cb.text = traits[trait_id]
		cb.disabled = not has_focus
		cb.button_pressed = client_trait_ids.has(trait_id)
		cb.toggled.connect(func(pressed: bool) -> void: trait_toggled.emit(trait_id, pressed))
		_traits_form.add_child(cb)


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
