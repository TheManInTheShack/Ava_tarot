class_name ControllerPanel
extends VBoxContainer

## Minimal rollup-panel side UI for the controller. Pattern ported from
## Paradotz's UI/GraphPanel.gd (_make_sub_rollup / _rollup_color /
## _style_rollup_header / _wrap_rollup_panel): a collapsible, color-coded
## section per concern. Built entirely in code, not a hand-authored .tscn.

signal start_pressed()
signal record_pressed()
signal end_pressed()
signal payment_saved(method: String, amount: float, waived: bool)
signal session_theme_saved(theme: String)
signal reset_pressed()
signal reshuffle_pressed()
signal unshuffle_pressed()
signal deal_next_pressed()
signal deal_to_slot_pressed(slot_id: String, layer: String)
signal deal_loose_pressed()
signal acl_changed(slot_id: String, layer: String, is_visible: bool, actions: Array)
signal deck_acl_changed(is_visible: bool, actions: Array)
signal show_all_pressed()
signal hide_all_pressed()
signal layout_acl_changed(is_visible: bool)
signal loose_acl_changed(is_visible: bool)
signal layout_selected(layout_id: String)
signal layout_created(name: String)
signal layout_deleted(layout_id: String)
signal layout_mod_mode_changed(on: bool)
signal slot_added(name: String, x: float, y: float)
signal slots_saved(updates: Array)  # [{"slot_id","x","y"}, ...] — Save Layout's batch commit
signal slot_deleted(slot_id: String)
signal slot_renamed(slot_id: String, name: String)
signal slot_scale_preview(slot_id: String, scale: float)  # live, not persisted — see set_slots()
signal slot_position_preview(slot_id: String, x: float, y: float)  # live, not persisted
signal trait_created(name: String)
signal trait_deleted(trait_id: String)
signal trait_modified(trait_id: String, name: String, note: String)
signal trait_toggled(trait_id: String, has_trait: bool)  # add (true) / remove (false) for the focused client
signal client_focus_changed()
signal querent_focus_changed()
signal querent_worksheet_toggled()
signal exit_pressed()
signal ctx_toggled()  # "Ctx" button — see Main.gd's _on_ctx_toggled(); style kept in sync via set_ctx_on()

## Low-tech and manual by design (Venmo personal link + her own confirmation
## at session time, not a processor integration) — see Session section.
const PAYMENT_METHODS := ["Venmo", "Cash", "Other"]

const PALETTE := [
	Color(0.29, 0.62, 1.00),  # Blue   — Session
	Color(0.30, 0.85, 0.85),  # Cyan   — Deck
	Color(0.95, 0.75, 0.25),  # Yellow — Client Access
	Color(0.95, 0.55, 0.20),  # Orange — Layout (spatial/compositional, matches Paradotz's convention)
	Color(0.75, 0.45, 0.95),  # Violet — Traits
	Color(0.90, 0.35, 0.55),  # Magenta — Querent (deliberately distinct from Traits' violet even
	                          # though the two "overlap" conceptually — they stay separate rollups)
]

## (0,0) landed a new slot right behind the panel, in the one corner of the
## table nothing is ever clipped away from (Controls aren't clipped to their
## parent's bounds by default — see _make_spin_box()'s own note on the same
## problem). Roughly centered in the visible table area instead.
const DEFAULT_NEW_SLOT_POS := Vector2(300.0, 300.0)

var _status_label: Label
var _version_label: Label
var _ctx_btn: Button
var _visible_cbs: Dictionary = {}   # "slot_id:layer" -> CheckBox
var _flip_cbs: Dictionary = {}      # "slot_id:layer" -> CheckBox
var _cards_form: VBoxContainer
var _deck_visible_cb: CheckBox
var _deck_deal_next_cb: CheckBox
var _deck_draw_loose_cb: CheckBox
var _deck_draw_select_cb: CheckBox
var _deck_select_loose_cb: CheckBox
var _deck_place_slot_cb: CheckBox
var _deck_place_free_cb: CheckBox
var _deck_modify_cb: CheckBox
var _layout_visible_cb: CheckBox
var _loose_visible_cb: CheckBox
var _layout_menu: MenuButton
var _layout_modify_btn: Button
var _layout_new_row: HBoxContainer
var _layout_new_name: LineEdit
var _layout_mod_group: VBoxContainer
var _layout_mod_mode: bool = false
var _slot_rows_form: VBoxContainer
var _slot_row_boxes: Dictionary = {}  # slot_id -> {"x","y","v_order","h_order": SpinBox}, read by Save Layout
var _renaming_slot_id: String = ""    # which slot's name row is showing the inline rename editor, if any
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
var _payment_method_menu: MenuButton
var _payment_amount_box: SpinBox
var _payment_waived_cb: CheckBox
var _session_theme_edit: TextEdit
var _slots_cache: Dictionary = {}   # most recent set_slots() call, for menu labels
var _deck_slot_menu: MenuButton
var _deck_slot_options: Array = []  # [{"slot_id","layer"}], parallel to popup item ids
var _deck_slot_selected_index: int = -1
var _deck_fill_state: Dictionary = {}  # "slot_id:layer" -> true for currently-occupied layers
var _deal_to_slot_btn: Button
var _traits_cache: Dictionary = {}   # trait_id -> {"name","note"}, most recent set_traits() call
var _assigned_traits_form: VBoxContainer
var _traits_focus_label: Label
var _traits_picker_row: HBoxContainer  # client picker, visible only out-of-session
var _traits_client_menu: MenuButton
var _traits_clients: Array = []
var _traits_selected_client_index: int = -1
var _trait_new_name: LineEdit
var _trait_vocab_menu: MenuButton      # shared selection for Modify + Delete Trait
var _trait_vocab_options: Array = []   # trait_ids, parallel to popup item ids
var _trait_vocab_selected_index: int = -1
var _trait_modify_group: VBoxContainer
var _trait_modify_name: LineEdit
var _trait_modify_note: TextEdit
var _trait_add_menu: MenuButton
var _trait_add_options: Array = []     # trait_ids not yet on the focused client
var _trait_add_selected_index: int = -1
var _querent_picker_row: HBoxContainer  # client picker, visible only out-of-session — own, independent selection, same reasoning as Traits' own picker
var _querent_client_menu: MenuButton
var _querent_clients: Array = []
var _querent_selected_client_index: int = -1
var _querent_focus_label: Label


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

	_ctx_btn = Button.new()
	_ctx_btn.text = "Ctx"
	_ctx_btn.flat = true
	_ctx_btn.focus_mode = Control.FOCUS_NONE
	_ctx_btn.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
	_ctx_btn.pressed.connect(func() -> void: ctx_toggled.emit())
	top_row.add_child(_ctx_btn)

	var exit_btn := Button.new()
	exit_btn.text = "Exit"
	exit_btn.pressed.connect(func() -> void: exit_pressed.emit())
	top_row.add_child(exit_btn)
	add_child(top_row)

	_build_session_section()
	_build_deck_section()
	_build_cards_section()
	_build_layout_section()
	_build_traits_section()
	_build_querent_section()


func set_version(v: String) -> void:
	_version_label.text = "Paratarot v" + v


func set_ctx_on(on: bool) -> void:
	_ctx_btn.add_theme_color_override("font_color",
		Color(0.88, 0.88, 0.88) if on else Color(0.35, 0.35, 0.42))


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
	btn.text = title + "  [+]"
	_style_rollup_header(btn, color)
	add_child(btn)

	var wrapped := _wrap_rollup_panel(form, color, false)
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
	_layout_modify_btn.pressed.connect(func() -> void: set_layout_mod_mode(true))
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

	# Two rows, not one — a single row of name + x + y + button wants ~360px
	# and the panel is a hard 320px now (see Main.gd's PANEL_W). Squeezed
	# into one row, the button (the one element with no explicit minimum
	# width) got shrunk down to almost nothing by the HBoxContainer, with
	# its label still rendering past its own tiny actual rect unclicked —
	# found live: the button LOOKED normal-sized but only its top-left
	# corner was actually clickable.
	_slot_new_name = LineEdit.new()
	_slot_new_name.placeholder_text = "Slot name"
	_slot_new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout_mod_group.add_child(_slot_new_name)

	var add_row := HBoxContainer.new()
	_slot_new_x = _make_spin_box()
	_slot_new_x.value = DEFAULT_NEW_SLOT_POS.x
	add_row.add_child(_slot_new_x)
	_slot_new_y = _make_spin_box()
	_slot_new_y.value = DEFAULT_NEW_SLOT_POS.y
	add_row.add_child(_slot_new_y)
	var add_slot_btn := Button.new()
	add_slot_btn.text = "Add Slot"
	add_slot_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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

	# "Save Layout" lives here now, not on the top Modify button — Modify
	# only ever enters mod mode; this is the one explicit commit-and-exit
	# action, next to Delete Layout since both are "I'm done with this
	# layout" gestures. Switching the dropdown selection or deleting the
	# layout are still the other (non-committing) ways out of mod mode.
	var bottom_row := HBoxContainer.new()
	var save_layout_btn := Button.new()
	save_layout_btn.text = "Save Layout"
	save_layout_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_layout_btn.pressed.connect(_commit_and_exit_layout_mod_mode)
	bottom_row.add_child(save_layout_btn)
	var delete_layout_btn := Button.new()
	delete_layout_btn.text = "Delete Layout"
	delete_layout_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_layout_btn.pressed.connect(_confirm_delete_layout)
	bottom_row.add_child(delete_layout_btn)
	_layout_mod_group.add_child(bottom_row)

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
	_renaming_slot_id = ""  # don't leave a stale rename editor showing next time this reopens
	layout_mod_mode_changed.emit(on)


## Save Layout (bottom of the mod group, next to Delete Layout) commits
## every slot row's current x/y/scale/deal-order in one batch (there are no
## per-row Save buttons) and exits mod mode. Dragging a slot on the table
## still commits position immediately on drop, same as before; this is
## specifically for the numeric-field/slider editing path.
func _commit_and_exit_layout_mod_mode() -> void:
	var updates: Array = []
	for slot_id in _slot_row_boxes.keys():
		var boxes: Dictionary = _slot_row_boxes[slot_id]
		updates.append({
			"slot_id": slot_id,
			"x": boxes["x"].value,
			"y": boxes["y"].value,
			"scale": boxes["scale"].value,
			"v_order": boxes["v_order"].value,
			"h_order": boxes["h_order"].value,
			"horizontal_enabled": boxes["horizontal_enabled"].button_pressed,
		})
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


## Narrower than _make_spin_box()'s position fields — deal order is a small
## relative rank (1, 2, 3...), not a pixel coordinate, and the row it shares
## with the Delete button doesn't have room for two 80px fields on top of
## that (see set_slots()'s own note on the width budget).
func _make_order_spin_box() -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = 0
	sb.max_value = 999
	sb.step = 1
	sb.custom_minimum_size = Vector2(50, 0)
	return sb


## Two states for a slot's name line: normal (name + Rename + Delete) or,
## while _renaming_slot_id == slot_id, editing (a LineEdit + Save + Cancel
## in its place). Only one slot can be mid-rename at a time — same
## single-editor-at-once rule as Layout's own mod mode and Traits' Modify
## editor elsewhere in this panel.
func _build_slot_name_row(slot_id: String, info: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	var slot_name: String = info.get("name", slot_id)

	if _renaming_slot_id == slot_id:
		var name_edit := LineEdit.new()
		name_edit.text = slot_name
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_edit)

		var save_btn := Button.new()
		save_btn.text = "Save"
		save_btn.pressed.connect(func() -> void:
			var n: String = name_edit.text.strip_edges()
			if n != "":
				slot_renamed.emit(slot_id, n)
			_renaming_slot_id = ""
			set_slots(_slots_cache)
		)
		row.add_child(save_btn)

		var cancel_btn := Button.new()
		cancel_btn.text = "Cancel"
		cancel_btn.pressed.connect(func() -> void:
			_renaming_slot_id = ""
			set_slots(_slots_cache)
		)
		row.add_child(cancel_btn)
	else:
		var label := Label.new()
		label.text = slot_name
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var rename_btn := Button.new()
		rename_btn.text = "Rename"
		rename_btn.pressed.connect(func() -> void:
			_renaming_slot_id = slot_id
			set_slots(_slots_cache)
		)
		row.add_child(rename_btn)

		var del_btn := Button.new()
		del_btn.text = "Delete"
		del_btn.pressed.connect(func() -> void: _confirm_delete_slot(slot_id, slot_name))
		row.add_child(del_btn)

	return row


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


## slots: {slot_id: {"name": String, "x": float, "y": float, "scale": float}}
## — the active layout's slots. Rebuilds both this section's editable rows
## and Client Access's per-layer rows, since they always change together.
## No per-row Save button anymore — a row's fields are just pending edits
## until "Save Layout" (bottom of the mod group) commits every row at once
## and exits mod mode. _slot_row_boxes is what that commit reads from.
##
## Two columns per live feedback: Order (V#, H# — stacked vertically, so
## scanning down the left column reads all of them) on the left, Position
## (X, Y — stays side by side, unchanged) with the size slider under it on
## the right. No column headers ("not helping" per feedback that killed
## the previous "Order"/"Position" labels).
const POSITION_ROW_WIDTH := 170.0  # matches x_box+y_box's combined width, so the slider below lines up


func set_slots(slots: Dictionary) -> void:
	_slots_cache = slots
	for c in _slot_rows_form.get_children():
		c.queue_free()
	_slot_row_boxes.clear()

	for slot_id in slots.keys():
		var info: Dictionary = slots[slot_id]
		var entry := VBoxContainer.new()
		entry.add_child(_build_slot_name_row(slot_id, info))

		var fields_row := HBoxContainer.new()

		var order_column := VBoxContainer.new()
		var v_order_box := _make_order_spin_box()
		v_order_box.value = info.get("vertical_deal_order", 0)
		v_order_box.tooltip_text = "Vertical deal order"
		order_column.add_child(v_order_box)
		var h_order_box := _make_order_spin_box()
		h_order_box.value = info.get("horizontal_deal_order", 0)
		h_order_box.tooltip_text = "Horizontal deal order"
		order_column.add_child(h_order_box)
		fields_row.add_child(order_column)

		var position_column := VBoxContainer.new()
		var xy_row := HBoxContainer.new()
		var x_box := _make_spin_box()
		x_box.value = info.get("x", 0.0)
		xy_row.add_child(x_box)
		var y_box := _make_spin_box()
		y_box.value = info.get("y", 0.0)
		xy_row.add_child(y_box)
		# Live preview on the table as either field changes — found live
		# ("the x/y changes should show live too") alongside the same ask
		# for the size slider below. Doesn't persist anything; Save Layout
		# still does that, same as every field here.
		var emit_position_preview := func() -> void: slot_position_preview.emit(slot_id, x_box.value, y_box.value)
		x_box.value_changed.connect(func(_v: float) -> void: emit_position_preview.call())
		y_box.value_changed.connect(func(_v: float) -> void: emit_position_preview.call())
		position_column.add_child(xy_row)

		var size_row := HBoxContainer.new()
		var size_slider := HSlider.new()
		size_slider.min_value = 0.5
		size_slider.max_value = 2.0
		size_slider.step = 0.05
		size_slider.value = info.get("scale", 1.0)
		size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_slider.tooltip_text = "Slot size"
		size_row.add_child(size_slider)
		var size_label := Label.new()
		size_label.text = "%d%%" % int(round(size_slider.value * 100.0))
		size_label.custom_minimum_size = Vector2(40, 0)
		size_row.add_child(size_label)
		# Live preview while dragging — found live: not previewing this one
		# specifically read as broken ("I have to save the layout in order
		# to see the results"). Doesn't persist anything; Save Layout still
		# does that, same as every other field here.
		size_slider.value_changed.connect(func(value: float) -> void:
			size_label.text = "%d%%" % int(round(value * 100.0))
			slot_scale_preview.emit(slot_id, value)
		)
		size_row.custom_minimum_size = Vector2(POSITION_ROW_WIDTH, 0)
		position_column.add_child(size_row)
		fields_row.add_child(position_column)

		entry.add_child(fields_row)

		# Off means this slot only ever takes a Vertical card — Main.gd's deal
		# targeting and the loose-card drag resolution both treat a filled
		# Vertical as the whole slot being full once this is off, instead of
		# offering Horizontal as a second thing to fill.
		var h_enable_cb := CheckBox.new()
		h_enable_cb.text = "Horizontal on"
		h_enable_cb.button_pressed = info.get("horizontal_enabled", true)
		entry.add_child(h_enable_cb)

		_slot_row_boxes[slot_id] = {
			"x": x_box, "y": y_box, "v_order": v_order_box, "h_order": h_order_box, "scale": size_slider,
			"horizontal_enabled": h_enable_cb,
		}

		_slot_rows_form.add_child(entry)

	_refresh_cards_section(slots)
	_refresh_deck_slot_menu(slots)


## Live readout only, while a slot marker is being dragged on the canvas
## (CardWorld's slot_dragging signal) — mirrors preview_slot_position()'s
## rule in reverse. set_value_no_signal() so this doesn't loop back through
## x_box/y_box's value_changed → slot_position_preview → back here.
func set_slot_position_fields(slot_id: String, x: float, y: float) -> void:
	var boxes: Dictionary = _slot_row_boxes.get(slot_id, {})
	var x_box: SpinBox = boxes.get("x")
	var y_box: SpinBox = boxes.get("y")
	if x_box != null:
		x_box.set_value_no_signal(x)
	if y_box != null:
		y_box.set_value_no_signal(y)


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

	# Session Theme — every reading has some question/feeling driving it,
	# whatever it actually is; recorded free-text on the Session node itself,
	# same "explicit Save, not live-per-keystroke" reasoning as Payment below
	# (a half-typed theme shouldn't get written either).
	_in_session_group.add_child(HSeparator.new())
	var theme_label := Label.new()
	theme_label.text = "Session Theme"
	_in_session_group.add_child(theme_label)
	_session_theme_edit = TextEdit.new()
	_session_theme_edit.custom_minimum_size = Vector2(0.0, 60.0)
	_session_theme_edit.placeholder_text = "What question or feeling is this reading about?"
	_session_theme_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_in_session_group.add_child(_session_theme_edit)
	var save_theme_btn := Button.new()
	save_theme_btn.text = "Save Theme"
	save_theme_btn.pressed.connect(func() -> void: session_theme_saved.emit(_session_theme_edit.text))
	_in_session_group.add_child(save_theme_btn)

	# Payment — low-tech and manual by design (Venmo personal link + her own
	# confirmation, not a processor integration): she picks a method, enters
	# what came in, and hits Save; "Waived" is the explicit override for a
	# comped/free session, disabling the other two fields rather than just
	# leaving them at a misleading blank/zero. No live-push-per-keystroke
	# like the ACL checkboxes elsewhere in this panel — a deliberate Save
	# button avoids writing a half-typed amount, same reasoning as Save
	# Layout's own batch commit.
	_in_session_group.add_child(HSeparator.new())
	var payment_label := Label.new()
	payment_label.text = "Payment"
	_in_session_group.add_child(payment_label)
	_payment_method_menu = MenuButton.new()
	_payment_method_menu.text = "Method"
	var pm_popup := _payment_method_menu.get_popup()
	for i in range(PAYMENT_METHODS.size()):
		pm_popup.add_item(PAYMENT_METHODS[i], i)
	pm_popup.id_pressed.connect(func(id: int) -> void: _payment_method_menu.text = PAYMENT_METHODS[id])
	_in_session_group.add_child(_payment_method_menu)
	_payment_amount_box = SpinBox.new()
	_payment_amount_box.prefix = "$"
	_payment_amount_box.min_value = 0
	_payment_amount_box.max_value = 100000
	_payment_amount_box.step = 0.01
	_payment_amount_box.select_all_on_focus = true
	_in_session_group.add_child(_payment_amount_box)
	_payment_waived_cb = CheckBox.new()
	_payment_waived_cb.text = "Waived"
	_payment_waived_cb.toggled.connect(func(v: bool) -> void:
		_payment_method_menu.disabled = v
		_payment_amount_box.editable = not v
	)
	_in_session_group.add_child(_payment_waived_cb)
	var save_payment_btn := Button.new()
	save_payment_btn.text = "Save Payment"
	save_payment_btn.pressed.connect(func() -> void:
		var method: String = "" if _payment_method_menu.text == "Method" else _payment_method_menu.text
		payment_saved.emit(method, _payment_amount_box.value, _payment_waived_cb.button_pressed)
	)
	_in_session_group.add_child(save_payment_btn)

	form.add_child(_in_session_group)

	_make_rollup("Session", _rollup_color(0), form)
	set_in_session(false)


## Toggles which Session controls are shown — client picker/Start when out of
## session, Record Scenario/End Reading when in one. Reading-Model.md: "what
## it does depends on IN_SESSION vs. OUT_OF_SESSION."
func set_in_session(in_session: bool) -> void:
	_out_of_session_group.visible = not in_session
	_in_session_group.visible = in_session
	if in_session:
		# Fresh Session node, fresh theme/payment fields — last reading's
		# entries shouldn't linger and look like they already apply to this one.
		_session_theme_edit.text = ""
		_payment_method_menu.text = "Method"
		_payment_method_menu.disabled = false
		_payment_amount_box.value = 0
		_payment_amount_box.editable = true
		_payment_waived_cb.set_pressed_no_signal(false)
	# Traits' own client picker only matters out of session — in-session,
	# focus is locked to that client and _traits_focus_label already covers
	# saying so. Null-checked: this fires once from _build_session_section()
	# during _ready(), before _build_traits_section() runs and creates it.
	if _traits_picker_row != null:
		_traits_picker_row.visible = not in_session
	# Same rule, same reasoning, Querent's own independent picker.
	if _querent_picker_row != null:
		_querent_picker_row.visible = not in_session


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


## State-independent (per Reading-Model.md, works in or out of a session) —
## Reset/Reshuffle/Unshuffle/Deal Next/Deal to Slot/Deal Loose. A loose card
## can attach to something via either of Reading-Model.md's two paths now:
## the right-click "Modify Card" menu (path 1), or dragging it onto a slot/
## card directly (path 2, Step 5's other half — CardWorld's loose-drag
## handling + Main._on_loose_drag_resolved()'s three-way resolution).
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
	_deal_to_slot_btn = Button.new()
	_deal_to_slot_btn.text = "Deal to Slot"
	_deal_to_slot_btn.pressed.connect(func() -> void:
		if _deck_slot_selected_index < 0 or _deck_slot_selected_index >= _deck_slot_options.size():
			return
		var opt: Dictionary = _deck_slot_options[_deck_slot_selected_index]
		deal_to_slot_pressed.emit(opt["slot_id"], opt["layer"])
	)
	deal_slot_row.add_child(_deal_to_slot_btn)
	form.add_child(deal_slot_row)

	var deal_loose_btn := Button.new()
	deal_loose_btn.text = "Deal Loose"
	deal_loose_btn.pressed.connect(func() -> void: deal_loose_pressed.emit())
	form.add_child(deal_loose_btn)

	_make_rollup("Deck", _rollup_color(1), form)


func _deck_slot_label(opt: Dictionary) -> String:
	var slot_name: String = _slots_cache.get(opt["slot_id"], {}).get("name", opt["slot_id"])
	return "%s — %s" % [slot_name, LAYER_LABELS.get(opt["layer"], opt["layer"])]


## Only ever lists layers that are currently empty — filled ones drop out
## entirely rather than staying pickable and getting rejected by Main.gd's
## _deal_into() ("That layer is already filled"). Since the current
## selection always lands on whatever's first in this filtered list, dealing
## to the selected slot naturally "advances" to the next open one on the
## next refresh — no separate advance-the-selection logic needed.
func _refresh_deck_slot_menu(slots: Dictionary) -> void:
	_deck_slot_options.clear()
	var popup := _deck_slot_menu.get_popup()
	popup.clear()
	for slot_id in slots.keys():
		for layer in ["vertical", "horizontal"]:
			if layer == "horizontal" and not slots[slot_id].get("horizontal_enabled", true):
				continue
			if _deck_fill_state.has("%s:%s" % [slot_id, layer]):
				continue
			var opt := {"slot_id": slot_id, "layer": layer}
			popup.add_item(_deck_slot_label(opt), _deck_slot_options.size())
			_deck_slot_options.append(opt)
	if _deck_slot_options.is_empty():
		_deck_slot_menu.text = "No unfilled slots"
		_deck_slot_selected_index = -1
	else:
		_deck_slot_selected_index = 0
		_deck_slot_menu.text = _deck_slot_label(_deck_slot_options[0])
	_deal_to_slot_btn.disabled = _deck_slot_options.is_empty()


func _on_deck_slot_menu_id_pressed(id: int) -> void:
	_deck_slot_selected_index = id
	_deck_slot_menu.text = _deck_slot_label(_deck_slot_options[id])


## filled: {"slot_id:layer": true} for every currently-occupied layer in the
## active layout — Main.gd calls this after anything that could change
## which layers are filled (dealing, Reset, End Reading/Record Scenario,
## a layout switch, deleting a slot that had a card on it).
func set_deck_fill_state(filled: Dictionary) -> void:
	_deck_fill_state = filled
	_refresh_deck_slot_menu(_slots_cache)


## State-independent (per Reading-Model.md), two sub-groups per live
## feedback: managing the trait *vocabulary* itself (add/delete a Trait
## node) is a separate concern from assigning traits to a specific client,
## so they're two distinct control clusters in this one rollup rather than
## one undifferentiated list. Both are shortcuts into the same
## HAS_TRAIT/Trait-node graph writes Paradotz itself could make, not a
## separate rules engine.
func _build_traits_section() -> void:
	var form := VBoxContainer.new()

	var vocab_label := Label.new()
	vocab_label.text = "Vocabulary"
	vocab_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	form.add_child(vocab_label)

	var add_trait_row := HBoxContainer.new()
	_trait_new_name = LineEdit.new()
	_trait_new_name.placeholder_text = "New trait name"
	_trait_new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_trait_row.add_child(_trait_new_name)
	var add_trait_btn := Button.new()
	add_trait_btn.text = "Add Trait"
	add_trait_btn.pressed.connect(func() -> void:
		var n: String = _trait_new_name.text.strip_edges()
		if n != "":
			trait_created.emit(n)
			_trait_new_name.text = ""
	)
	add_trait_row.add_child(add_trait_btn)
	form.add_child(add_trait_row)

	# One shared picker for both Modify and Delete Trait — own row, since a
	# dropdown + two buttons together hits the same width squeeze the Add
	# Slot row already taught us about (see set_slots()'s doc comment).
	_trait_vocab_menu = MenuButton.new()
	_trait_vocab_menu.text = "No traits"
	_trait_vocab_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trait_vocab_menu.get_popup().id_pressed.connect(_on_trait_vocab_menu_id_pressed)
	form.add_child(_trait_vocab_menu)

	var vocab_actions_row := HBoxContainer.new()
	var modify_trait_btn := Button.new()
	modify_trait_btn.text = "Modify"
	modify_trait_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modify_trait_btn.pressed.connect(_open_trait_modify_editor)
	vocab_actions_row.add_child(modify_trait_btn)
	var delete_trait_btn := Button.new()
	delete_trait_btn.text = "Delete Trait"
	delete_trait_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_trait_btn.pressed.connect(_confirm_delete_trait)
	vocab_actions_row.add_child(delete_trait_btn)
	form.add_child(vocab_actions_row)

	# Inline editor, hidden until Modify is pressed — same reveal pattern as
	# Layout's "+ New Layout" name prompt. note is Paradotz's "long text"
	# property type (text_long, show_in_hover) registered on the Trait type
	# schema by Main.gd — verified against Paradotz's own GraphPanel.gd/
	# NodePanel.gd/Editor.gd rather than guessed, so it actually renders as
	# multi-line there and surfaces in its node tooltip once non-empty.
	_trait_modify_group = VBoxContainer.new()
	_trait_modify_group.visible = false

	var modify_name_label := Label.new()
	modify_name_label.text = "Name"
	modify_name_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_trait_modify_group.add_child(modify_name_label)
	_trait_modify_name = LineEdit.new()
	_trait_modify_group.add_child(_trait_modify_name)

	var modify_note_label := Label.new()
	modify_note_label.text = "Note"
	modify_note_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_trait_modify_group.add_child(modify_note_label)
	_trait_modify_note = TextEdit.new()
	_trait_modify_note.custom_minimum_size = Vector2(0, 80)
	_trait_modify_note.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_trait_modify_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trait_modify_group.add_child(_trait_modify_note)

	var modify_save_row := HBoxContainer.new()
	var modify_save_btn := Button.new()
	modify_save_btn.text = "Save"
	modify_save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modify_save_btn.pressed.connect(func() -> void:
		if _trait_vocab_selected_index < 0 or _trait_vocab_selected_index >= _trait_vocab_options.size():
			return
		var n: String = _trait_modify_name.text.strip_edges()
		if n == "":
			return
		trait_modified.emit(_trait_vocab_options[_trait_vocab_selected_index], n, _trait_modify_note.text)
		_trait_modify_group.visible = false
	)
	modify_save_row.add_child(modify_save_btn)
	var modify_cancel_btn := Button.new()
	modify_cancel_btn.text = "Cancel"
	modify_cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modify_cancel_btn.pressed.connect(func() -> void: _trait_modify_group.visible = false)
	modify_save_row.add_child(modify_cancel_btn)
	_trait_modify_group.add_child(modify_save_row)

	form.add_child(_trait_modify_group)

	form.add_child(HSeparator.new())

	var assign_label := Label.new()
	assign_label.text = "Client Traits"
	assign_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	form.add_child(assign_label)

	# In-session, focus is locked to that client (this label covers it, same
	# as the Session section's own status line) — this picker only matters,
	# and is only shown, out of session. Deliberately its own picker rather
	# than reading the Session section's client selection: that one answers
	# "who will the next reading be with," this one answers "whose traits am
	# I looking at right now" — related but genuinely different questions,
	# so conflating them would make it look like changing one changes the
	# other.
	_traits_picker_row = HBoxContainer.new()
	_traits_client_menu = MenuButton.new()
	_traits_client_menu.text = "No clients"
	_traits_client_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_traits_client_menu.get_popup().id_pressed.connect(_on_traits_client_menu_id_pressed)
	_traits_picker_row.add_child(_traits_client_menu)
	form.add_child(_traits_picker_row)

	_traits_focus_label = Label.new()
	_traits_focus_label.text = "No client selected"
	form.add_child(_traits_focus_label)

	_assigned_traits_form = VBoxContainer.new()
	form.add_child(_assigned_traits_form)

	var add_client_trait_row := HBoxContainer.new()
	_trait_add_menu = MenuButton.new()
	_trait_add_menu.text = "No traits to add"
	_trait_add_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trait_add_menu.get_popup().id_pressed.connect(_on_trait_add_menu_id_pressed)
	add_client_trait_row.add_child(_trait_add_menu)
	var add_client_trait_btn := Button.new()
	add_client_trait_btn.text = "Add"
	add_client_trait_btn.pressed.connect(func() -> void:
		if _trait_add_selected_index < 0 or _trait_add_selected_index >= _trait_add_options.size():
			return
		trait_toggled.emit(_trait_add_options[_trait_add_selected_index], true)
	)
	add_client_trait_row.add_child(add_client_trait_btn)
	form.add_child(add_client_trait_row)

	_make_rollup("Traits", _rollup_color(4), form)


## Switching which trait is selected closes the Modify editor rather than
## leaving it showing stale content for whatever was previously picked —
## same "switching selection exits edit mode" rule Layout's mod mode uses.
func _on_trait_vocab_menu_id_pressed(id: int) -> void:
	_trait_vocab_selected_index = id
	_trait_vocab_menu.text = _traits_cache.get(_trait_vocab_options[id], {}).get("name", "")
	_trait_modify_group.visible = false


func _open_trait_modify_editor() -> void:
	if _trait_vocab_selected_index < 0 or _trait_vocab_selected_index >= _trait_vocab_options.size():
		return
	var trait_id: String = _trait_vocab_options[_trait_vocab_selected_index]
	var info: Dictionary = _traits_cache.get(trait_id, {})
	_trait_modify_name.text = info.get("name", "")
	_trait_modify_note.text = info.get("note", "")
	_trait_modify_group.visible = true


## Ported pattern (not code) from Paradotz's NodePanel.gd:_on_delete_pressed
## — same ConfirmationDialog shape as slot/layout deletion elsewhere in this
## panel. Warns explicitly that this is vocabulary-wide, not per-client.
func _confirm_delete_trait() -> void:
	if _trait_vocab_selected_index < 0 or _trait_vocab_selected_index >= _trait_vocab_options.size():
		return
	var trait_id: String = _trait_vocab_options[_trait_vocab_selected_index]
	var trait_name: String = _traits_cache.get(trait_id, {}).get("name", trait_id)
	var dialog := ConfirmationDialog.new()
	dialog.title = "Delete Trait"
	dialog.dialog_text = "Delete trait \"%s\" from the vocabulary?\nRemoves it from every client who currently has it.\nThis cannot be undone." % trait_name
	dialog.ok_button_text = "Delete"
	dialog.cancel_button_text = "Cancel"
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		trait_deleted.emit(trait_id)
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.popup_centered()


func _on_traits_client_menu_id_pressed(id: int) -> void:
	_traits_selected_client_index = id
	_traits_client_menu.text = _label_for_client(_traits_clients[id])
	client_focus_changed.emit()


## clients: same shape as set_clients() — populated from the same fetched
## list (see Main.gd), just a second, independent selection.
func set_traits_clients(clients: Array) -> void:
	_traits_clients = clients
	var popup := _traits_client_menu.get_popup()
	popup.clear()
	for i in range(clients.size()):
		popup.add_item(_label_for_client(clients[i]), i)
	if clients.is_empty():
		_traits_client_menu.text = "No clients"
		_traits_selected_client_index = -1
	else:
		_traits_selected_client_index = 0
		_traits_client_menu.text = _label_for_client(clients[0])


## Returns {} if no client is selected (e.g. the picker is still empty).
func get_traits_selected_client() -> Dictionary:
	if _traits_selected_client_index < 0 or _traits_selected_client_index >= _traits_clients.size():
		return {}
	return _traits_clients[_traits_selected_client_index]


func _on_trait_add_menu_id_pressed(id: int) -> void:
	_trait_add_selected_index = id
	_trait_add_menu.text = _traits_cache.get(_trait_add_options[id], {}).get("name", "")


## traits: {trait_id: {"name","note"}} — the full vocabulary, for both the
## vocabulary picker (Modify/Delete Trait) and the Add-to-client picker
## (filtered to what the focused client doesn't already have).
## client_trait_ids: {trait_id: true} — which of those the focused client
## currently has; rendered as a short list with a Remove button each, not a
## checkbox against the whole vocabulary. focus_label: "" when no client is
## focused.
func set_traits(traits: Dictionary, client_trait_ids: Dictionary, focus_label: String) -> void:
	_traits_cache = traits
	_traits_focus_label.text = ("Traits for %s" % focus_label) if focus_label != "" else "No client selected"

	_trait_vocab_options.clear()
	var vocab_popup := _trait_vocab_menu.get_popup()
	vocab_popup.clear()
	for trait_id in traits.keys():
		vocab_popup.add_item(traits[trait_id].get("name", trait_id), _trait_vocab_options.size())
		_trait_vocab_options.append(trait_id)
	if _trait_vocab_options.is_empty():
		_trait_vocab_menu.text = "No traits"
		_trait_vocab_selected_index = -1
	else:
		_trait_vocab_selected_index = 0
		_trait_vocab_menu.text = traits[_trait_vocab_options[0]].get("name", "")
	# The underlying data may have just changed (e.g. this is the refresh
	# right after a Save) — don't leave stale content showing.
	_trait_modify_group.visible = false

	for c in _assigned_traits_form.get_children():
		c.queue_free()
	for trait_id in client_trait_ids.keys():
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = traits.get(trait_id, {}).get("name", trait_id)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var remove_btn := Button.new()
		remove_btn.text = "Remove"
		remove_btn.pressed.connect(func() -> void: trait_toggled.emit(trait_id, false))
		row.add_child(remove_btn)
		_assigned_traits_form.add_child(row)

	_trait_add_options.clear()
	var add_popup := _trait_add_menu.get_popup()
	add_popup.clear()
	for trait_id in traits.keys():
		if client_trait_ids.has(trait_id):
			continue
		add_popup.add_item(traits[trait_id].get("name", trait_id), _trait_add_options.size())
		_trait_add_options.append(trait_id)
	if _trait_add_options.is_empty():
		_trait_add_menu.text = "No traits to add"
		_trait_add_selected_index = -1
	else:
		_trait_add_selected_index = 0
		_trait_add_menu.text = traits[_trait_add_options[0]].get("name", "")


# ── Querent (client notes) ───────────────────────────────────────────────────
# "Overlaps" with Traits conceptually (both are about the client currently in
# focus) but is deliberately its own rollup/picker, not a merge — Traits is a
# shared, reusable vocabulary tagged onto whichever client; this is free-text
# notes specific to one client, written back onto their own Client graph
# node. Same focus rule as Traits: in-session locked to that client, out of
# session picked from its own independent picker (not shared with Traits' or
# Session's — same reasoning as _build_traits_section()'s own doc comment:
# "who will the next reading be with," "whose traits am I looking at," and
# now "whose notes am I looking at" are three different questions).

func _build_querent_section() -> void:
	var form := VBoxContainer.new()

	_querent_picker_row = HBoxContainer.new()
	_querent_client_menu = MenuButton.new()
	_querent_client_menu.text = "No clients"
	_querent_client_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_querent_client_menu.get_popup().id_pressed.connect(_on_querent_client_menu_id_pressed)
	_querent_picker_row.add_child(_querent_client_menu)
	form.add_child(_querent_picker_row)

	_querent_focus_label = Label.new()
	_querent_focus_label.text = "No client selected"
	form.add_child(_querent_focus_label)

	# The rollup itself only ever toggles the worksheet open/closed now —
	# it doesn't hold the note content inline anymore (that was too cramped
	# for real use). Main.gd owns building/tracking the actual Worksheet
	# floating window; this button is a pure trigger.
	var worksheet_btn := Button.new()
	worksheet_btn.text = "Worksheet"
	worksheet_btn.pressed.connect(func() -> void: querent_worksheet_toggled.emit())
	form.add_child(worksheet_btn)

	_make_rollup("Querent", _rollup_color(5), form)


func _on_querent_client_menu_id_pressed(id: int) -> void:
	_querent_selected_client_index = id
	_querent_client_menu.text = _label_for_client(_querent_clients[id])
	querent_focus_changed.emit()


## clients: same shape as set_clients()/set_traits_clients() — populated from
## the same fetched list, a third, independent selection.
func set_querent_clients(clients: Array) -> void:
	_querent_clients = clients
	var popup := _querent_client_menu.get_popup()
	popup.clear()
	for i in range(clients.size()):
		popup.add_item(_label_for_client(clients[i]), i)
	if clients.is_empty():
		_querent_client_menu.text = "No clients"
		_querent_selected_client_index = -1
	else:
		_querent_selected_client_index = 0
		_querent_client_menu.text = _label_for_client(clients[0])


## Returns {} if no client is selected (e.g. the picker is still empty).
func get_querent_selected_client() -> Dictionary:
	if _querent_selected_client_index < 0 or _querent_selected_client_index >= _querent_clients.size():
		return {}
	return _querent_clients[_querent_selected_client_index]


## The actual notes content now lives only in the Worksheet floating window
## (Main.gd owns it) — this just keeps the rollup's own label in sync with
## whichever client is currently focused.
func set_querent_focus_label(focus_label: String) -> void:
	_querent_focus_label.text = ("Notes for %s" % focus_label) if focus_label != "" else "No client selected"


const LAYER_LABELS := {"vertical": "Vertical", "horizontal": "Horizontal"}


func _build_cards_section() -> void:
	var form := VBoxContainer.new()

	var bulk_row := HBoxContainer.new()
	var show_all_btn := Button.new()
	show_all_btn.text = "Show All"
	show_all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	show_all_btn.pressed.connect(func() -> void: show_all_pressed.emit())
	bulk_row.add_child(show_all_btn)
	var hide_all_btn := Button.new()
	hide_all_btn.text = "Hide All"
	hide_all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hide_all_btn.pressed.connect(func() -> void: hide_all_pressed.emit())
	bulk_row.add_child(hide_all_btn)
	form.add_child(bulk_row)

	form.add_child(HSeparator.new())

	# Layout/Loose — Reading-Model.md: everything on the table except the
	# deck is a child of the Layout. Layout's own row gates whether the
	# client sees the table shape at all (the empty slot glow/halo/labels,
	# independent of whether any specific card is individually visible);
	# unchecking it also forces every per-slot row and the Loose row off
	# (Main._cascade_layout_off()) so a client can't be left seeing a lone
	# card floating with no table around it. Starts checked — "practically
	# it would begin in the 'on' state" per the ask.
	var layout_label := Label.new()
	layout_label.text = "Layout"
	form.add_child(layout_label)
	_layout_visible_cb = CheckBox.new()
	_layout_visible_cb.text = "Visible"
	_layout_visible_cb.button_pressed = true
	_layout_visible_cb.toggled.connect(func(v: bool) -> void: layout_acl_changed.emit(v))
	form.add_child(_layout_visible_cb)

	var loose_label := Label.new()
	loose_label.text = "Loose Cards"
	form.add_child(loose_label)
	_loose_visible_cb = CheckBox.new()
	_loose_visible_cb.text = "Visible"
	_loose_visible_cb.toggled.connect(func(v: bool) -> void: loose_acl_changed.emit(v))
	form.add_child(_loose_visible_cb)

	form.add_child(HSeparator.new())

	# Deck row — state-independent (the deck marker isn't tied to the active
	# layout's slots the way the rows below are), so it lives here as a
	# fixed row rather than inside _cards_form, which _refresh_cards_section
	# tears down and rebuilds on every layout change. One checkbox per row,
	# not two/three side by side — the same 320px-panel-width squeeze the
	# per-slot rows below already learned to avoid (see their own comment).
	var deck_label := Label.new()
	deck_label.text = "Deck"
	form.add_child(deck_label)
	_deck_visible_cb = CheckBox.new()
	_deck_visible_cb.text = "Visible"
	form.add_child(_deck_visible_cb)
	_deck_deal_next_cb = CheckBox.new()
	_deck_deal_next_cb.text = "Can Deal Next"
	form.add_child(_deck_deal_next_cb)
	_deck_draw_loose_cb = CheckBox.new()
	_deck_draw_loose_cb.text = "Can Draw Loose"
	form.add_child(_deck_draw_loose_cb)

	# Two more selection methods, alongside Deal Next/Draw Loose above —
	# these two are "selection-only": tapping either just picks a card up
	# (begins a click-to-carry drag, no button-held-down needed — moves
	# with the mouse until the next click), it doesn't resolve anything by
	# itself. Draw/Select draws a fresh card and picks it up in one step
	# (vs. Draw Loose, which draws and stops); Select Loose picks up a card
	# already sitting on the table (shown on that card's own tap menu, not
	# the deck's — but kept in this same Deck cluster of controls, matching
	# how the ask grouped all of this as "deck" controls regardless).
	_deck_draw_select_cb = CheckBox.new()
	_deck_draw_select_cb.text = "Can Draw & Select"
	form.add_child(_deck_draw_select_cb)
	_deck_select_loose_cb = CheckBox.new()
	_deck_select_loose_cb.text = "Can Select Loose"
	form.add_child(_deck_select_loose_cb)

	# Once a card is selected and the client drags it, one of these three
	# governs how the drop resolves. A resolution kind that isn't checked
	# here falls back to a fixed tray position instead of wherever they
	# actually dropped it ("loose_fallback", not a checkbox — always
	# implicitly granted whenever a drag can even start, see
	# emit_deck_change below), which also covers the rare case of a
	# permission being revoked mid-drag. Not buttons — these are outcomes
	# of a drag, not commands, so they never appear in ClientOverlay.
	_deck_place_slot_cb = CheckBox.new()
	_deck_place_slot_cb.text = "Can Place in Slot"
	form.add_child(_deck_place_slot_cb)
	_deck_place_free_cb = CheckBox.new()
	_deck_place_free_cb.text = "Can Place Freely"
	form.add_child(_deck_place_free_cb)
	_deck_modify_cb = CheckBox.new()
	_deck_modify_cb.text = "Can Modify"
	form.add_child(_deck_modify_cb)

	var emit_deck_change := func() -> void:
		var actions: Array = []
		if _deck_deal_next_cb.button_pressed:
			actions.append("deal_next")
		if _deck_draw_loose_cb.button_pressed:
			actions.append("draw_loose")
		if _deck_draw_select_cb.button_pressed:
			actions.append("draw_select")
		if _deck_select_loose_cb.button_pressed:
			actions.append("select_loose")
		if _deck_place_slot_cb.button_pressed:
			actions.append("place_slot")
		if _deck_place_free_cb.button_pressed:
			actions.append("place_free")
		if _deck_modify_cb.button_pressed:
			actions.append("modify")
		if actions.has("draw_select") or actions.has("select_loose") or actions.has("place_slot") or actions.has("place_free") or actions.has("modify"):
			actions.append("loose_fallback")
		deck_acl_changed.emit(_deck_visible_cb.button_pressed, actions)
	_deck_visible_cb.toggled.connect(func(_v: bool) -> void: emit_deck_change.call())
	_deck_deal_next_cb.toggled.connect(func(_v: bool) -> void: emit_deck_change.call())
	_deck_draw_loose_cb.toggled.connect(func(_v: bool) -> void: emit_deck_change.call())
	_deck_draw_select_cb.toggled.connect(func(_v: bool) -> void: emit_deck_change.call())
	_deck_select_loose_cb.toggled.connect(func(_v: bool) -> void: emit_deck_change.call())
	_deck_place_slot_cb.toggled.connect(func(_v: bool) -> void: emit_deck_change.call())
	_deck_place_free_cb.toggled.connect(func(_v: bool) -> void: emit_deck_change.call())
	_deck_modify_cb.toggled.connect(func(_v: bool) -> void: emit_deck_change.call())

	form.add_child(HSeparator.new())

	_cards_form = VBoxContainer.new()
	form.add_child(_cards_form)

	_make_rollup("Client Access", _rollup_color(2), form)


## Keeps the deck checkboxes honest when its ACL changes from elsewhere
## (Show All/Hide All) instead of from this panel's own deck row — same
## reasoning as sync_acl() below.
func sync_deck_acl(is_visible: bool, actions: Array) -> void:
	_deck_visible_cb.set_pressed_no_signal(is_visible)
	_deck_deal_next_cb.set_pressed_no_signal(actions.has("deal_next"))
	_deck_draw_loose_cb.set_pressed_no_signal(actions.has("draw_loose"))
	_deck_draw_select_cb.set_pressed_no_signal(actions.has("draw_select"))
	_deck_select_loose_cb.set_pressed_no_signal(actions.has("select_loose"))
	_deck_place_slot_cb.set_pressed_no_signal(actions.has("place_slot"))
	_deck_place_free_cb.set_pressed_no_signal(actions.has("place_free"))
	_deck_modify_cb.set_pressed_no_signal(actions.has("modify"))


## Keeps the Layout checkbox honest across a table reset (Reset/Record/End
## restore it to whatever _layout_visible currently is, not unconditionally
## true) — this panel's own row is the only other writer.
func sync_layout_acl(is_visible: bool) -> void:
	_layout_visible_cb.set_pressed_no_signal(is_visible)


## Keeps the Loose checkbox honest when it changes from elsewhere (a table
## reset, or Layout's own off-cascade) instead of from this panel's row.
func sync_loose_acl(is_visible: bool) -> void:
	_loose_visible_cb.set_pressed_no_signal(is_visible)


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
			if layer == "horizontal" and not slots[slot_id].get("horizontal_enabled", true):
				continue  # never fillable, so an ACL row for it is dead clutter
			var key := "%s:%s" % [slot_id, layer]
			var entry := VBoxContainer.new()

			# This row (label + two checkboxes wanting ~330px against a
			# 320px-fixed panel) is the original "Client Access is wider
			# than the others" bug — it used to grow the whole panel to
			# make room; now that the panel can't do that, it'd silently
			# squeeze a checkbox down to a near-unclickable sliver instead
			# (same failure mode found live on the Add Slot button). Label
			# on its own row avoids the same fate here.
			var label := Label.new()
			label.text = "%s — %s" % [slot_name, LAYER_LABELS[layer]]
			entry.add_child(label)

			var cb_row := HBoxContainer.new()
			var visible_cb := CheckBox.new()
			visible_cb.text = "Visible"
			cb_row.add_child(visible_cb)
			_visible_cbs[key] = visible_cb

			var flip_cb := CheckBox.new()
			flip_cb.text = "Can flip"
			cb_row.add_child(flip_cb)
			_flip_cbs[key] = flip_cb
			entry.add_child(cb_row)

			var emit_change := func() -> void:
				var actions: Array = ["flip"] if flip_cb.button_pressed else []
				acl_changed.emit(slot_id, layer, visible_cb.button_pressed, actions)
			visible_cb.toggled.connect(func(_v: bool) -> void: emit_change.call())
			flip_cb.toggled.connect(func(_v: bool) -> void: emit_change.call())

			_cards_form.add_child(entry)


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
