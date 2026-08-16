extends Control

## Orchestrator. Determines controller vs client mode from /auth/me (no
## query-param mode switch — the client logs in as themselves, same as the
## controller) and wires up the corresponding UI. Controller holds the
## authoritative reading state locally and pushes it over the WebSocket on
## every change; client only ever renders what the server has already
## filtered through the live ACL.

const CONTROLLER_ROLES := ["admin", "dev", "user"]
const DECK_PATH := "res://Data/cards.json"
const GRAPH_NAME := "tarot-deck"

## Bump on every commit that touches this repo's source — same convention as
## Paradotz's MainMenu.gd — it's the only way to confirm a deploy took effect
## in the browser (nginx now sends Cache-Control: no-cache for /paratarot/,
## same fix as /paradotz/, but this is the actual proof).
const VERSION := "0.15.0"

var _mode: String = ""  # "controller" | "client" | ""
var _me: Dictionary = {}
var _deck: Dictionary = {}  # card_id -> card info from cards.json

var _world: CardWorld
var _panel: ControllerPanel
var _overlay: ClientOverlay
var _status_label: Label

var _state: Dictionary = {"cards": {}, "loose": {}}
var _acl: Dictionary = {}
var _pending_client: Dictionary = {}   # last client_joined info, for the checkpoint
var _last_acl: Dictionary = {}         # client mode only: most recent ACL received
var _context_menu: Control = null      # controller mode only: the currently-open card context menu

# Controller mode only: the graph-backed Layout/Slot model — see
# Meta/Reading-Model.md's Layout -> Slot -> Vertical/Horizontal hierarchy.
var _graph: Dictionary = {}
var _layouts: Dictionary = {}          # layout_id -> {"name"}
var _slots: Dictionary = {}            # slot_id -> {"name","x","y","layout_id","vertical_id","horizontal_id"}
var _active_layout_id: String = ""
var _next_id_counter: int = 1          # shared node/edge id counter, seeded from the loaded graph
var _graph_session_node_id: String = ""  # this session's Session graph node, set at Start Reading
var _deck_order: Array = []            # undealt cards, standing order, top = index 0 — see Deck section
var _traits: Dictionary = {}           # trait_id -> name, parsed from _graph — see Traits section


func _ready() -> void:
	randomize()

	_status_label = Label.new()
	_status_label.text = "Loading…"
	_status_label.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_status_label)

	_deck = _load_deck()
	_deck_order = _canonical_deck_order()
	_me = await ApiClient.get_me()
	if is_instance_valid(_status_label):
		_status_label.queue_free()

	if _me.is_empty():
		_show_error("Not signed in.")
		return

	var roles: Array = _me.get("roles", [])
	if roles.any(func(r): return CONTROLLER_ROLES.has(r)):
		_mode = "controller"
		_setup_controller()
	elif roles.has("public"):
		_mode = "client"
		_setup_client()
	else:
		_show_error("This account has no access to Paratarot.")


func _load_deck() -> Dictionary:
	if not FileAccess.file_exists(DECK_PATH):
		return {}
	var f := FileAccess.open(DECK_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary and parsed.has("nodes"):
		return parsed["nodes"]
	return {}


func _show_error(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	add_child(lbl)


# ── Controller ───────────────────────────────────────────────────────────────

## Fixed-width side panel + full-remaining-width canvas, positioned via
## anchor/offset math directly on this Control root — ported technique (not
## code) from Paradotz's Editor.gd, which solves the exact problem an
## HBoxContainer here used to cause: HBoxContainer resizes children off
## their minimum size, so a wide rollup (Client Access, with its per-layer
## labels) grew the whole panel past PANEL_W, shifting where CardWorld's
## local coordinate origin landed on screen and putting new slots/cards at
## local (0,0) behind the panel. A plain Control parent never does that —
## each sibling's rect is exactly what its own anchors/offsets say.
const PANEL_W := 320.0


func _setup_controller() -> void:
	# ScrollContainer with horizontal scrolling off clips anything that's
	# still too wide instead of growing the panel — Controls aren't clipped
	# to their parent's bounds by default otherwise (the very bug this
	# whole layout change exists to fix). Vertical scrolling stays on, so
	# several rollups expanded at once scroll instead of overflowing the
	# window's bottom edge.
	var panel_scroll := ScrollContainer.new()
	panel_scroll.anchor_left = 0.0
	panel_scroll.anchor_right = 0.0
	panel_scroll.anchor_top = 0.0
	panel_scroll.anchor_bottom = 1.0
	panel_scroll.offset_right = PANEL_W
	panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(panel_scroll)

	_panel = ControllerPanel.new()
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_scroll.add_child(_panel)
	_panel.set_version(VERSION)

	_world = CardWorld.new()
	_world.anchor_left = 0.0
	_world.anchor_right = 1.0
	_world.anchor_top = 0.0
	_world.anchor_bottom = 1.0
	_world.offset_left = PANEL_W
	add_child(_world)

	_panel.start_pressed.connect(_on_start_pressed)
	_panel.record_pressed.connect(_on_record_pressed)
	_panel.end_pressed.connect(_on_end_pressed)
	_panel.reset_pressed.connect(_on_reset_pressed)
	_panel.reshuffle_pressed.connect(_on_reshuffle_pressed)
	_panel.unshuffle_pressed.connect(_on_unshuffle_pressed)
	_panel.deal_next_pressed.connect(_on_deal_next_pressed)
	_panel.deal_to_slot_pressed.connect(_on_deal_to_slot_pressed)
	_panel.deal_loose_pressed.connect(_on_deal_loose_pressed)
	_panel.acl_changed.connect(_on_acl_changed)
	_panel.layout_selected.connect(_on_layout_selected)
	_panel.layout_created.connect(_on_layout_created)
	_panel.layout_deleted.connect(_on_layout_deleted)
	_panel.layout_mod_mode_changed.connect(_world.set_layout_mod_mode)
	_panel.slot_added.connect(_on_slot_added)
	_panel.slots_saved.connect(_on_slots_saved)
	_panel.slot_deleted.connect(_on_slot_deleted)
	_panel.slot_renamed.connect(_on_slot_renamed)
	_panel.slot_scale_preview.connect(_world.preview_slot_scale)
	_panel.slot_position_preview.connect(_world.preview_slot_position)
	_panel.trait_created.connect(_on_trait_created)
	_panel.trait_deleted.connect(_on_trait_deleted)
	_panel.trait_modified.connect(_on_trait_modified)
	_panel.trait_toggled.connect(_on_trait_toggled)
	_panel.client_focus_changed.connect(_refresh_traits_panel)
	_panel.exit_pressed.connect(_on_exit_pressed)
	_world.card_tapped.connect(_on_controller_card_tapped)
	_world.card_context_requested.connect(_on_card_context_requested)
	_world.slot_drag_ended.connect(_on_slot_updated)
	_world.slot_dragging.connect(_panel.set_slot_position_fields)
	_world.loose_drag_resolved.connect(_on_loose_drag_resolved)
	_world.loose_edge_resolved.connect(_on_loose_edge_resolved)
	_world.deck_draw_requested.connect(_on_deck_draw_requested)

	ApiClient.action_received.connect(_on_client_action_received)
	ApiClient.client_joined.connect(_on_client_joined)

	await _load_layouts()
	# Session's picker (who to Start Reading with) and Traits' own picker
	# (whose traits am I looking at) are deliberately independent selections
	# — see _build_traits_section()'s doc comment — but both start from the
	# same fetched client list, no reason to hit the endpoint twice.
	var clients: Array = await ApiClient.get_clients()
	_panel.set_clients(clients)
	_panel.set_traits_clients(clients)
	# Traits' "current focus" depends on its own picker, so this can only
	# happen once both the graph (trait vocabulary) and that picker (initial
	# selection) are loaded — see _refresh_traits_panel's own doc comment.
	_refresh_traits_panel()


# ── Layout / Slot (graph-backed) ────────────────────────────────────────────

func _load_layouts() -> void:
	_graph = await ApiClient.get_graph(GRAPH_NAME)
	if _graph.is_empty():
		_graph = {"name": GRAPH_NAME}
	_seed_id_counter()
	_parse_layouts()
	if _layouts.is_empty():
		_bootstrap_default_layout()
		await _save_graph()
		_parse_layouts()
	if not _layouts.has(_active_layout_id):
		_active_layout_id = _layouts.keys()[0] if not _layouts.is_empty() else ""
	_apply_active_layout()


func _seed_id_counter() -> void:
	var max_id := 0
	for n in _graph.get("nodes", []):
		var nid: String = str(n.get("id", "0"))
		if nid.is_valid_int() and int(nid) > max_id:
			max_id = int(nid)
	for e in _graph.get("edges", []):
		var eid: String = str(e.get("id", "0"))
		if eid.is_valid_int() and int(eid) > max_id:
			max_id = int(eid)
	_next_id_counter = max_id + 1


func _next_id() -> String:
	var id := str(_next_id_counter)
	_next_id_counter += 1
	return id


## Rebuilds _layouts/_slots from _graph's nodes/edges. Structural data only
## (name, x, y) — inversion/session/scenario are instance-level, live on
## placement edges written at deal time, not here. See Reading-Model.md's
## structural-vs-instance property split.
func _parse_layouts() -> void:
	_layouts.clear()
	_slots.clear()
	var nodes: Array = _graph.get("nodes", [])
	var edges: Array = _graph.get("edges", [])
	var node_by_id: Dictionary = {}
	for n in nodes:
		node_by_id[str(n.get("id", ""))] = n
		if n.get("type", "") == "Layout":
			_layouts[str(n["id"])] = {"name": n.get("name", "")}

	var slot_layout: Dictionary = {}   # slot_id -> layout_id
	for e in edges:
		if e.get("type", "") == "HAS_SLOT":
			slot_layout[str(e.get("to", ""))] = str(e.get("from", ""))

	var layer_ids: Dictionary = {}     # slot_id -> {"vertical": id, "horizontal": id}
	for e in edges:
		if e.get("type", "") == "HAS_LAYER":
			var slot_id: String = str(e.get("from", ""))
			var layer_node = node_by_id.get(str(e.get("to", "")))
			if layer_node == null:
				continue
			var layer_kind: String = "vertical" if layer_node.get("type", "") == "Vertical" else "horizontal"
			var d: Dictionary = layer_ids.get(slot_id, {})
			d[layer_kind] = str(layer_node["id"])
			layer_ids[slot_id] = d

	for slot_id in slot_layout.keys():
		var node = node_by_id.get(slot_id)
		if node == null or node.get("type", "") != "Slot":
			continue
		var props: Dictionary = node.get("properties", {})
		var layers: Dictionary = layer_ids.get(slot_id, {})
		var vertical_id: String = layers.get("vertical", "")
		var horizontal_id: String = layers.get("horizontal", "")
		_slots[slot_id] = {
			"name": node.get("name", slot_id),
			"x": float(props.get("x", 0.0)),
			"y": float(props.get("y", 0.0)),
			"scale": float(props.get("scale", 1.0)),
			"horizontal_enabled": bool(props.get("horizontal_enabled", true)),
			"layout_id": slot_layout[slot_id],
			"vertical_id": vertical_id,
			"horizontal_id": horizontal_id,
			"vertical_deal_order": _layer_deal_order(node_by_id, vertical_id),
			"horizontal_deal_order": _layer_deal_order(node_by_id, horizontal_id),
		}


## deal_order lives as a plain property on the Vertical/Horizontal layer
## node itself, not the Slot — a slot's two layers need independently
## orderable positions in the deal sequence (e.g. slot1-V, slot2-V, slot1-H),
## not just "this slot comes before that one."
func _layer_deal_order(node_by_id: Dictionary, layer_id: String) -> int:
	if layer_id == "":
		return 0
	var layer_node = node_by_id.get(layer_id)
	if layer_node == null:
		return 0
	return int(layer_node.get("properties", {}).get("deal_order", 0))


func _slots_for_layout(layout_id: String) -> Dictionary:
	var result := {}
	for slot_id in _slots.keys():
		if _slots[slot_id].get("layout_id", "") == layout_id:
			result[slot_id] = _slots[slot_id]
	return result


func _apply_active_layout() -> void:
	_panel.set_layouts(_layouts, _active_layout_id)
	var active_slots := _slots_for_layout(_active_layout_id)
	_panel.set_slots(active_slots)
	_world.set_slots(active_slots)


## Tells the Deck section's "Deal to Slot" picker which layers are currently
## occupied, so it can never offer one that's already filled. Called from
## every place that changes fill status: dealing, and _reset_table() (which
## already covers Reset/End Reading/Record Scenario/layout switch — see its
## own callers) and _on_slot_deleted() (a card can vanish along with its slot).
func _refresh_deck_slot_availability() -> void:
	var filled: Dictionary = {}
	var cards: Dictionary = _state.get("cards", {})
	for slot_id in cards.keys():
		var slot: Dictionary = cards[slot_id]
		for layer in ["vertical", "horizontal"]:
			if slot.get(layer) != null:
				filled["%s:%s" % [slot_id, layer]] = true
	_panel.set_deck_fill_state(filled)


## Clears whatever's currently dealt — a different layout's slot ids don't
## match the new one's, so leftover cards would otherwise render collapsed
## at the origin instead of just vanishing. Used on layout creation
## (explicitly, so a new layout starts from a clean table ready for slots)
## and on switching to a different existing layout (same staleness problem).
func _reset_table() -> void:
	_state = {"cards": {}, "loose": {}}
	_acl = {}
	_world.apply_state(_state["cards"])
	_world.set_loose(_state["loose"])
	ApiClient.send_ws({"type": "state", "payload": _state})
	ApiClient.send_ws({"type": "acl", "payload": _acl})
	_refresh_deck_slot_availability()


func _save_graph() -> void:
	var result: Dictionary = await ApiClient.save_graph(GRAPH_NAME, _graph)
	if not result.is_empty():
		_graph = result


func _bootstrap_default_layout() -> void:
	var layout_id := _create_layout_node("Classic Simple")
	_create_slot_with_layers(layout_id, "Past", 120.0, 380.0)
	_create_slot_with_layers(layout_id, "Present", 480.0, 380.0)
	_create_slot_with_layers(layout_id, "Future", 840.0, 380.0)


func _create_layout_node(name: String) -> String:
	var id := _next_id()
	var nodes: Array = _graph.get("nodes", [])
	nodes.append({"id": id, "type": "Layout", "name": name, "properties": {}})
	_graph["nodes"] = nodes
	return id


func _create_slot_with_layers(layout_id: String, name: String, x: float, y: float) -> String:
	var nodes: Array = _graph.get("nodes", [])
	var edges: Array = _graph.get("edges", [])

	var slot_id := _next_id()
	nodes.append({"id": slot_id, "type": "Slot", "name": name, "properties": {"x": x, "y": y, "scale": 1.0, "horizontal_enabled": true}})
	edges.append({"id": _next_id(), "from": layout_id, "to": slot_id, "type": "HAS_SLOT", "properties": {}})

	# Sensible default (vertical then horizontal, after everything that
	# already exists) — fully overridable afterward via the Layout editor's
	# V#/H# fields. Global max rather than scoped to this layout: simpler,
	# and correctness only ever depends on relative order *within* a layout
	# (_next_deal_target() already scopes there), so a big-looking number is
	# harmless. Scoping to _slots_for_layout() instead would under-count
	# during _bootstrap_default_layout()'s three sequential calls, since
	# _slots isn't re-parsed between them.
	var next_order := _next_deal_order()
	for layer_kind in ["Vertical", "Horizontal"]:
		var layer_id := _next_id()
		var layer_name := "%s-%s-%s" % [layout_id, name.to_lower().replace(" ", "-"), layer_kind.to_lower()]
		nodes.append({"id": layer_id, "type": layer_kind, "name": layer_name, "properties": {"deal_order": next_order}})
		edges.append({"id": _next_id(), "from": slot_id, "to": layer_id, "type": "HAS_LAYER", "properties": {}})
		next_order += 1

	_graph["nodes"] = nodes
	_graph["edges"] = edges
	return slot_id


func _next_deal_order() -> int:
	var max_order := 0
	for n in _graph.get("nodes", []):
		if n.get("type", "") == "Vertical" or n.get("type", "") == "Horizontal":
			var order: int = int(n.get("properties", {}).get("deal_order", 0))
			if order > max_order:
				max_order = order
	return max_order + 1


## Reading-Model.md: "If cards were already placed when a mid-session Layout
## change happens, the current table state gets recorded first, same as any
## other mid-session save — a Layout switch is just another trigger for
## that mechanic, not a new one." Out of session (_graph_session_node_id
## empty) there's no Session to protect, so nothing to save — "changing the
## selection is passive."
func _auto_save_before_layout_switch() -> void:
	if _graph_session_node_id == "":
		return
	var cards: Dictionary = _state.get("cards", {})
	var loose: Dictionary = _state.get("loose", {})
	if cards.is_empty() and loose.is_empty():
		return
	_send_checkpoint(false)
	# Same wait-then-resync shape as Record Scenario/End Reading — the WS
	# "save" message has no ack yet, and _create_layout_node() (the caller
	# right after this, for a brand-new layout) mutates _graph locally, so
	# it must already be the post-checkpoint copy or the PUT that follows
	# would silently erase the Session/Scenario nodes this save just wrote.
	await get_tree().create_timer(0.5).timeout
	await _resync_graph()


## "Reshuffles back to its ready state" (Reading-Model.md) — a layout switch
## gets a fresh full deck, not just an empty table. Recomputed directly from
## the full catalog rather than tracking what to return, since
## _reset_table() (called right before this) already clears every card
## that was on the table — nothing dealt is unaccounted for.
func _reset_deck_to_ready_state() -> void:
	_deck_order = _canonical_deck_order()


func _on_layout_selected(layout_id: String) -> void:
	if layout_id == _active_layout_id:
		return
	await _auto_save_before_layout_switch()
	_active_layout_id = layout_id
	_reset_table()
	_reset_deck_to_ready_state()
	_apply_active_layout()


func _on_layout_created(name: String) -> void:
	await _auto_save_before_layout_switch()
	var new_id := _create_layout_node(name)
	await _save_graph()
	_parse_layouts()
	_active_layout_id = new_id
	_reset_table()
	_reset_deck_to_ready_state()
	_apply_active_layout()
	# Only now, after the new layout is genuinely active and set_slots() has
	# already pushed its (empty) slot list to the panel, does mod mode turn
	# on — doing this from ControllerPanel's own Create button raced this
	# whole async chain and flashed the previous layout's slots for a frame.
	_panel.set_layout_mod_mode(true)


func _on_slot_added(name: String, x: float, y: float) -> void:
	if _active_layout_id == "":
		return
	_create_slot_with_layers(_active_layout_id, name, x, y)
	await _save_graph()
	_parse_layouts()
	_apply_active_layout()


## Drag-and-drop's immediate single-slot commit (CardWorld.slot_drag_ended).
func _on_slot_updated(slot_id: String, x: float, y: float) -> void:
	var nodes: Array = _graph.get("nodes", [])
	for n in nodes:
		if str(n.get("id", "")) == slot_id:
			var props: Dictionary = n.get("properties", {})
			props["x"] = x
			props["y"] = y
			n["properties"] = props
			break
	await _save_graph()
	_parse_layouts()
	_apply_active_layout()


## Only ever called after ControllerPanel's own inline rename editor — see
## _build_slot_name_row there. The Slot node's own "name" field, not a
## property — same field SlotVisual's name label and the sub-labels
## displaying "card name in slot" both read from.
func _on_slot_renamed(slot_id: String, name: String) -> void:
	var n: String = name.strip_edges()
	if n == "":
		return
	var nodes: Array = _graph.get("nodes", [])
	for node in nodes:
		if str(node.get("id", "")) == slot_id:
			node["name"] = n
			break
	await _save_graph()
	_parse_layouts()
	_apply_active_layout()


## "Save Layout"'s batch commit for the numeric-field/slider editing path —
## every row's current x/y/scale/deal-order in one graph write, instead of
## the old one-save-per-row button. Position and scale live on the Slot
## node itself; deal_order lives on the Slot's own Vertical/Horizontal
## layer nodes (see _create_slot_with_layers) — a second node lookup per
## update, not folded into the same one.
func _on_slots_saved(updates: Array) -> void:
	var nodes: Array = _graph.get("nodes", [])
	for u in updates:
		var slot_id: String = u.get("slot_id", "")
		for n in nodes:
			if str(n.get("id", "")) == slot_id:
				var props: Dictionary = n.get("properties", {})
				props["x"] = u.get("x", 0.0)
				props["y"] = u.get("y", 0.0)
				props["scale"] = u.get("scale", 1.0)
				props["horizontal_enabled"] = u.get("horizontal_enabled", true)
				n["properties"] = props
				break
		var info: Dictionary = _slots.get(slot_id, {})
		_set_layer_deal_order(nodes, info.get("vertical_id", ""), u.get("v_order", 0))
		_set_layer_deal_order(nodes, info.get("horizontal_id", ""), u.get("h_order", 0))
	await _save_graph()
	_parse_layouts()
	_apply_active_layout()


func _set_layer_deal_order(nodes: Array, layer_id: String, order) -> void:
	if layer_id == "":
		return
	for n in nodes:
		if str(n.get("id", "")) == layer_id:
			var props: Dictionary = n.get("properties", {})
			props["deal_order"] = order
			n["properties"] = props
			return


## Only ever called after ControllerPanel's own delete-confirmation dialog —
## see _confirm_delete_slot there.
func _on_slot_deleted(slot_id: String) -> void:
	if not _slots.has(slot_id):
		return
	var info: Dictionary = _slots[slot_id]
	var remove_ids: Array = [slot_id, info.get("vertical_id", ""), info.get("horizontal_id", "")]

	var nodes: Array = _graph.get("nodes", [])
	_graph["nodes"] = nodes.filter(func(n): return not remove_ids.has(str(n.get("id", ""))))

	var edges: Array = _graph.get("edges", [])
	_graph["edges"] = edges.filter(func(e): return not (remove_ids.has(str(e.get("from", ""))) or remove_ids.has(str(e.get("to", "")))))

	await _save_graph()
	_parse_layouts()
	if not _layouts.has(_active_layout_id):
		_active_layout_id = _layouts.keys()[0] if not _layouts.is_empty() else ""

	# Match the confirmation dialog's promise: any card on this slot is
	# actually gone, not left rendering collapsed at the origin.
	var cards: Dictionary = _state.get("cards", {})
	if cards.erase(slot_id):
		_state["cards"] = cards
		_acl.erase(slot_id)
		ApiClient.send_ws({"type": "state", "payload": _state})
		ApiClient.send_ws({"type": "acl", "payload": _acl})
		_refresh_deck_slot_availability()

	_apply_active_layout()


## Deleting a Layout removes it and everything under it (Slots, their
## Vertical/Horizontal layers, all HAS_SLOT/HAS_LAYER edges) — same
## cascade-removal shape as _on_slot_deleted, one level up. If this was the
## active layout mid-session, auto-saves first (same trigger as switching
## layouts — deleting the active one out from under a reading is
## functionally a switch, just to nothing). Re-bootstraps a default layout
## if this was the last one, so the app is never left with zero layouts.
func _on_layout_deleted(layout_id: String) -> void:
	if not _layouts.has(layout_id):
		return
	var is_active: bool = layout_id == _active_layout_id
	if is_active:
		await _auto_save_before_layout_switch()

	var remove_ids: Array = [layout_id]
	for slot_id in _slots_for_layout(layout_id).keys():
		var info: Dictionary = _slots[slot_id]
		remove_ids.append(slot_id)
		remove_ids.append(info.get("vertical_id", ""))
		remove_ids.append(info.get("horizontal_id", ""))

	var nodes: Array = _graph.get("nodes", [])
	_graph["nodes"] = nodes.filter(func(n): return not remove_ids.has(str(n.get("id", ""))))

	var edges: Array = _graph.get("edges", [])
	_graph["edges"] = edges.filter(func(e): return not (remove_ids.has(str(e.get("from", ""))) or remove_ids.has(str(e.get("to", "")))))

	await _save_graph()
	_parse_layouts()

	if _layouts.is_empty():
		_bootstrap_default_layout()
		await _save_graph()
		_parse_layouts()

	if is_active:
		_active_layout_id = _layouts.keys()[0] if not _layouts.is_empty() else ""
		_reset_table()
		_reset_deck_to_ready_state()
	_apply_active_layout()


func _on_exit_pressed() -> void:
	if OS.get_name() == "Web":
		JavaScriptBridge.eval("window.location.href = '/dashboard'", true)


func _on_start_pressed() -> void:
	var selected: Dictionary = _panel.get_selected_client()
	if selected.is_empty():
		_panel.set_status("Pick a client first")
		return
	# The controller declares the client at instantiation — see
	# Meta/Reading-Model.md's Session design. display_name is already sitting
	# right here in the picker's data, no cross-service header plumbing needed
	# to get it onto the checkpoint's Client node.
	var client_display: String = selected.get("display_name", "")
	var client_user_id: int = selected.get("id", 0)
	var client_username: String = selected.get("username", "")
	_pending_client = {
		"user_id": client_user_id,
		"username": client_username,
		"display_name": client_display,
	}

	var session_info: Dictionary = await ApiClient.get_current_session()
	if session_info.is_empty():
		session_info = await ApiClient.start_session(client_user_id, client_username, client_display)
	var session_id: String = session_info.get("session_id", "")
	if session_id == "":
		_panel.set_status("Failed to start session")
		return
	_graph_session_node_id = session_info.get("graph_session_node_id", "")
	# The Session node (and possibly a new Client node) were just written
	# server-side — resync so this controller's own Layout/Slot edits don't
	# PUT a stale copy back and clobber them.
	await _resync_graph()

	ApiClient.connect_ws(session_id)
	_panel.set_in_session(true)
	_panel.set_status("Reading in progress — %s" % (client_display if client_display else client_username))
	_refresh_traits_panel()  # focus is now this session's client, not the picker
	# Push current state immediately so a reconnect doesn't show stale data.
	ApiClient.send_ws({"type": "state", "payload": _state})
	ApiClient.send_ws({"type": "acl", "payload": _acl})


## Re-fetches _graph from the server. Needed after anything that touches the
## graph server-side outside Godot's own GET/PUT round trip (Session/Scenario/
## Client writes go through the WS "save" path and /paratarot/sessions, not
## through Main.gd's own _save_graph()) — otherwise a later Layout/Slot edit
## would PUT a stale local copy back and silently erase what the server wrote.
func _resync_graph() -> void:
	var fresh: Dictionary = await ApiClient.get_graph(GRAPH_NAME)
	if not fresh.is_empty():
		_graph = fresh
		_seed_id_counter()
		_parse_layouts()


func _on_end_pressed() -> void:
	var cards: Dictionary = _state.get("cards", {})
	var loose: Dictionary = _state.get("loose", {})
	if not cards.is_empty() or not loose.is_empty():
		_send_checkpoint(true)
		# No ack on the WS "save" message — give the server a moment to
		# finish its own read-modify-write before resyncing, or we'd just
		# refetch the pre-checkpoint graph. Not airtight without a real ack,
		# but the controller isn't going to edit a Slot in the same instant.
		await get_tree().create_timer(0.5).timeout
		await _resync_graph()
	_state = {"cards": {}, "loose": {}}
	_acl = {}
	_pending_client = {}
	_graph_session_node_id = ""
	# Push the cleared state before disconnecting so any connected client's
	# view resets instead of freezing on the last-seen cards.
	ApiClient.send_ws({"type": "state", "payload": _state})
	ApiClient.send_ws({"type": "acl", "payload": _acl})
	ApiClient.disconnect_ws()
	_panel.set_in_session(false)
	_panel.set_status("No active reading")
	_world.apply_state(_state["cards"])
	_world.set_loose(_state["loose"])
	_refresh_traits_panel()  # focus reverts to whatever the picker has selected


## Mid-session save — "record it and start over in the same session":
## writes a Scenario but leaves the Session (and its ended_at) untouched, so
## the table clears while the reading stays open. See Reading-Model.md.
func _on_record_pressed() -> void:
	var cards: Dictionary = _state.get("cards", {})
	var loose: Dictionary = _state.get("loose", {})
	if cards.is_empty() and loose.is_empty():
		_panel.set_status("Nothing to record")
		return
	_send_checkpoint(false)
	await get_tree().create_timer(0.5).timeout
	await _resync_graph()
	_state = {"cards": {}, "loose": {}}
	_acl = {}
	ApiClient.send_ws({"type": "state", "payload": _state})
	ApiClient.send_ws({"type": "acl", "payload": _acl})
	_world.apply_state(_state["cards"])
	_world.set_loose(_state["loose"])
	var client_display: String = _pending_client.get("display_name", "")
	var client_username: String = _pending_client.get("username", "")
	_panel.set_status("Scenario recorded — %s" % (client_display if client_display else client_username))


# ── Traits (Step 6) ──────────────────────────────────────────────────────────
# Reading-Model.md: "Exactly Paradotz's Tag/HAS_TAG mechanism, not a new
# system" — Trait nodes + Client--HAS_TRAIT-->Trait edges, both already live
# in the tarot-deck graph (seeded 2026-08-11 via seed-personas.js, complete
# with the OCEAN Trait--LOADS_ON-->OceanFactor weighting) but never exposed
# in this controller's own UI until now. State-independent tier — available
# regardless of session state, per the doc's controller panel structure.

func _parse_traits() -> void:
	_traits.clear()
	for n in _graph.get("nodes", []):
		if n.get("type", "") == "Trait":
			_traits[str(n["id"])] = {
				"name": n.get("name", ""),
				"note": n.get("properties", {}).get("note", ""),
			}


## Registers Trait.note as "text_long" (Paradotz's long-text property type)
## in the graph's own type_schemas, with show_in_hover so it surfaces in
## Paradotz's node tooltip once populated — verified directly against
## Paradotz's GraphPanel.gd/NodePanel.gd/Editor.gd rather than guessed at.
## Idempotent: a no-op once the entry exists (checked live — tarot-deck's
## type_schemas has no Trait entry yet before this first runs).
func _ensure_trait_note_schema() -> void:
	var schemas: Dictionary = _graph.get("type_schemas", {})
	var trait_schema: Dictionary = schemas.get("Trait", {})
	var props: Array = trait_schema.get("properties", [])
	for p in props:
		if p.get("key", "") == "note":
			return
	props.append({"key": "note", "type": "text_long", "show_in_hover": true})
	trait_schema["properties"] = props
	schemas["Trait"] = trait_schema
	_graph["type_schemas"] = schemas


func _client_trait_ids_for(client_id: String) -> Dictionary:
	var result := {}
	for e in _graph.get("edges", []):
		if e.get("type", "") == "HAS_TRAIT" and str(e.get("from", "")) == client_id:
			result[str(e.get("to", ""))] = true
	return result


## "The Trait vocabulary and assign to whichever Client is currently in
## focus" — Reading-Model.md, adapted per live feedback: in-session,
## _pending_client (set atomically at Start Reading) IS that client — locked,
## not pickable. Out of session, it's whatever Traits' own client picker
## currently has selected (deliberately separate from the Session section's
## picker — see _build_traits_section()'s doc comment in ControllerPanel.gd).
func _focused_client_id() -> String:
	if not _pending_client.is_empty():
		return "client-%d" % int(_pending_client.get("user_id", 0))
	var selected: Dictionary = _panel.get_traits_selected_client()
	if selected.is_empty():
		return ""
	return "client-%d" % int(selected.get("id", 0))


func _focused_client_label() -> String:
	var info: Dictionary = _pending_client if not _pending_client.is_empty() else _panel.get_traits_selected_client()
	if info.is_empty():
		return ""
	var dn: String = info.get("display_name", "")
	return dn if dn != "" else info.get("username", "")


## Called after anything that could change either the trait vocabulary, the
## focused client's assigned traits, or which client is focused at all
## (Start/End Reading, the picker's own selection, adding/toggling a trait).
func _refresh_traits_panel() -> void:
	_parse_traits()
	var client_id := _focused_client_id()
	var client_trait_ids: Dictionary = _client_trait_ids_for(client_id) if client_id != "" else {}
	_panel.set_traits(_traits, client_trait_ids, _focused_client_label())


func _on_trait_created(name: String) -> void:
	var n: String = name.strip_edges()
	if n == "":
		return
	_ensure_trait_note_schema()
	var nodes: Array = _graph.get("nodes", [])
	nodes.append({"id": _next_id(), "type": "Trait", "name": n, "properties": {"note": ""}})
	_graph["nodes"] = nodes
	await _save_graph()
	_refresh_traits_panel()


## Respelling (name) and Paradotz's "long text" note field together — see
## _ensure_trait_note_schema(). Only ever called after ControllerPanel's own
## Modify editor — see _open_trait_modify_editor there.
func _on_trait_modified(trait_id: String, name: String, note: String) -> void:
	var n: String = name.strip_edges()
	if n == "":
		return
	_ensure_trait_note_schema()
	var nodes: Array = _graph.get("nodes", [])
	for node in nodes:
		if str(node.get("id", "")) == trait_id:
			node["name"] = n
			var props: Dictionary = node.get("properties", {})
			props["note"] = note
			node["properties"] = props
			break
	await _save_graph()
	_refresh_traits_panel()


## Removes the Trait node itself, plus every edge touching it — HAS_TRAIT
## from any client who had it, and LOADS_ON to its OceanFactor if it was
## part of the seeded weighting bank. Only ever called after
## ControllerPanel's own delete-confirmation dialog — see
## _confirm_delete_trait there.
func _on_trait_deleted(trait_id: String) -> void:
	var nodes: Array = _graph.get("nodes", [])
	_graph["nodes"] = nodes.filter(func(n): return str(n.get("id", "")) != trait_id)
	var edges: Array = _graph.get("edges", [])
	_graph["edges"] = edges.filter(func(e): return str(e.get("from", "")) != trait_id and str(e.get("to", "")) != trait_id)
	await _save_graph()
	_refresh_traits_panel()


## No-op if no client is currently focused — the Add/Remove controls only
## ever act on the currently-focused client's traits, so this only fires
## for a real, targeted change.
func _on_trait_toggled(trait_id: String, has_trait: bool) -> void:
	var client_id := _focused_client_id()
	if client_id == "":
		return
	var edges: Array = _graph.get("edges", [])
	if has_trait:
		var already: bool = edges.any(func(e): return e.get("type", "") == "HAS_TRAIT" and str(e.get("from", "")) == client_id and str(e.get("to", "")) == trait_id)
		if not already:
			edges.append({"id": _next_id(), "from": client_id, "to": trait_id, "type": "HAS_TRAIT", "properties": {}})
	else:
		edges = edges.filter(func(e): return not (e.get("type", "") == "HAS_TRAIT" and str(e.get("from", "")) == client_id and str(e.get("to", "")) == trait_id))
	_graph["edges"] = edges
	await _save_graph()
	_refresh_traits_panel()


# ── Deck (Step 4) ────────────────────────────────────────────────────────────
# Reading-Model.md: dealing is state-independent (works in or out of session;
# out-of-session dealing already produces zero graph writes for free, since
# Record Scenario/End Reading — the only checkpoint writers — are gated to
# in-session by ControllerPanel.set_in_session()). _deck_order holds only
# undealt cards; already-dealt cards leave the pool until Reset returns them,
# so Reshuffle/Unshuffle never conjure a duplicate of a card already on the
# table.

const SUIT_ORDER := ["Wands", "Cups", "Swords", "Pentacles"]


func _canonical_deck_order() -> Array:
	var majors := []
	var by_suit: Dictionary = {}
	for suit in SUIT_ORDER:
		by_suit[suit] = []
	for card_id in _deck.keys():
		var info: Dictionary = _deck[card_id]
		if info.get("arcana", "") == "Major":
			majors.append(card_id)
		else:
			var suit: String = info.get("suit", "")
			if by_suit.has(suit):
				by_suit[suit].append(card_id)
	majors.sort_custom(func(a, b): return int(_deck[a].get("number", 0)) < int(_deck[b].get("number", 0)))
	var order: Array = majors.duplicate()
	for suit in SUIT_ORDER:
		var suit_cards: Array = by_suit[suit]
		suit_cards.sort_custom(func(a, b): return int(_deck[a].get("number", 0)) < int(_deck[b].get("number", 0)))
		order.append_array(suit_cards)
	return order


## Deals the deck's top card into a specific slot/layer — the shared landing
## point for both Deal Next and Deal to Slot. Enforces the same
## vertical-before-horizontal placement constraint as everywhere else.
func _deal_into(slot_id: String, layer: String) -> void:
	if not _slots.has(slot_id):
		return
	var cards: Dictionary = _state.get("cards", {})
	var slot: Dictionary = cards.get(slot_id, {"vertical": null, "horizontal": null})
	if slot.get(layer) != null:
		_panel.set_status("That layer is already filled")
		return
	if layer == "horizontal" and slot.get("vertical") == null:
		_panel.set_status("Vertical must be filled first")
		return
	if layer == "horizontal" and not _slots.get(slot_id, {}).get("horizontal_enabled", true):
		_panel.set_status("Horizontal is off for this slot")
		return
	if _deck_order.is_empty():
		_panel.set_status("Deck is empty")
		return
	var card_id: String = _deck_order.pop_front()
	slot[layer] = _new_card_layer(card_id)
	cards[slot_id] = slot
	_state["cards"] = cards
	_world.apply_state(cards)
	ApiClient.send_ws({"type": "state", "payload": _state})
	_refresh_deck_slot_availability()


## Deal-order sequence (Reading-Model.md: "a structural property set when
## the layout is designed") is a per-layer "deal_order" property, editable
## in the Layout editor's V#/H# fields — not slot-creation order. Lets a
## slot's own two layers land anywhere relative to each other in the
## sequence (e.g. slot1-V, slot2-V, slot1-H), not just adjacent.
##
## A horizontal layer only becomes a candidate once its own vertical is
## already filled — if someone sets a horizontal's order lower than its own
## vertical's (asking for something vertical-before-horizontal physically
## can't allow), this self-corrects by skipping it until it's actually
## fillable, rather than handing _deal_into() a target it would just reject.
func _next_deal_target() -> Dictionary:
	var slots: Dictionary = _slots_for_layout(_active_layout_id)
	var cards: Dictionary = _state.get("cards", {})
	var candidates: Array = []
	for slot_id in slots.keys():
		var info: Dictionary = slots[slot_id]
		var slot_cards: Dictionary = cards.get(slot_id, {})
		var vertical_filled: bool = slot_cards.get("vertical") != null
		if not vertical_filled:
			candidates.append({"slot_id": slot_id, "layer": "vertical", "order": info.get("vertical_deal_order", 0)})
		if vertical_filled and slot_cards.get("horizontal") == null and info.get("horizontal_enabled", true):
			candidates.append({"slot_id": slot_id, "layer": "horizontal", "order": info.get("horizontal_deal_order", 0)})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a, b):
		if a["order"] != b["order"]:
			return a["order"] < b["order"]
		return int(a["slot_id"]) < int(b["slot_id"])
	)
	return {"slot_id": candidates[0]["slot_id"], "layer": candidates[0]["layer"]}


func _on_deal_next_pressed() -> void:
	var target: Dictionary = _next_deal_target()
	if target.is_empty():
		_panel.set_status("Layout is full")
		return
	_deal_into(target["slot_id"], target["layer"])


func _on_deal_to_slot_pressed(slot_id: String, layer: String) -> void:
	_deal_into(slot_id, layer)


## Cascades loose cards from a fixed tray origin so multiple dealt-loose
## cards stay visually distinguishable without the controller needing to
## drag each one apart right after dealing. Wraps into a new row after a
## handful so a long reading doesn't run loose cards off the right edge of
## the table.
const LOOSE_TRAY_ORIGIN := Vector2(120.0, 40.0)
const LOOSE_TRAY_STEP := Vector2(40.0, 0.0)
const LOOSE_TRAY_ROW_STEP := Vector2(0.0, 40.0)
const LOOSE_TRAY_PER_ROW := 8


func _on_deal_loose_pressed() -> void:
	if _deck_order.is_empty():
		_panel.set_status("Deck is empty")
		return
	var card_id: String = _deck_order.pop_front()
	var loose: Dictionary = _state.get("loose", {})
	var i: int = loose.size()
	var pos: Vector2 = LOOSE_TRAY_ORIGIN + LOOSE_TRAY_STEP * (i % LOOSE_TRAY_PER_ROW) + LOOSE_TRAY_ROW_STEP * (i / LOOSE_TRAY_PER_ROW)
	var info: Dictionary = _new_card_layer(card_id)
	info["x"] = pos.x
	info["y"] = pos.y
	info["modifies_target"] = ""
	loose[card_id] = info
	_state["loose"] = loose
	_world.set_loose(loose)
	ApiClient.send_ws({"type": "state", "payload": _state})


## DeckVisual's own draw gesture (hover/hold-then-drag on the deck marker) —
## same deal as _on_deal_loose_pressed() (state-independent, no session
## gating), except the new card is handed straight to CardWorld's
## begin_loose_drag() instead of landing in the tray, so it's already
## following the cursor for the user to place. The x/y here don't matter
## visually (begin_loose_drag repositions under the live mouse before this
## next frame ever renders) but still need to be real numbers for a card
## that gets released without moving, or if the deck is ever empty.
func _on_deck_draw_requested() -> void:
	if _deck_order.is_empty():
		_panel.set_status("Deck is empty")
		return
	var card_id: String = _deck_order.pop_front()
	var loose: Dictionary = _state.get("loose", {})
	var info: Dictionary = _new_card_layer(card_id)
	info["x"] = 0.0
	info["y"] = 0.0
	info["modifies_target"] = ""
	loose[card_id] = info
	_state["loose"] = loose
	_world.set_loose(loose)
	_world.begin_loose_drag(card_id)
	ApiClient.send_ws({"type": "state", "payload": _state})


## Tap-to-reveal, one-way only — same rule as _reveal_layer() for slotted
## cards: a tap only ever turns a loose card face-up, never back down.
## Turning it back over is a deliberate act via the right-click "Turn" menu
## (_flip_loose, still a real toggle).
func _reveal_loose(card_id: String) -> void:
	var loose: Dictionary = _state.get("loose", {})
	var info: Dictionary = loose.get(card_id, {})
	if info.is_empty() or info.get("face_up", false):
		return
	info["face_up"] = true
	_world.set_loose(loose)
	ApiClient.send_ws({"type": "state", "payload": _state})


func _flip_loose(card_id: String) -> void:
	var loose: Dictionary = _state.get("loose", {})
	var info: Dictionary = loose.get(card_id, {})
	if info.is_empty():
		return
	info["face_up"] = not info.get("face_up", false)
	_world.set_loose(loose)
	ApiClient.send_ws({"type": "state", "payload": _state})


## Reading-Model.md's path 2 for the modifier mechanic: dragging a loose card
## resolves to whichever of the three outcomes CardWorld._resolve_loose_drop()
## found at the drop point. "place"/"modify" are real graph-bound state
## changes; anything else (empty table, or a slot's margin without landing on
## a specific card) just repositions the loose card in place.
func _on_loose_drag_resolved(card_id: String, x: float, y: float, resolution: Dictionary) -> void:
	match resolution.get("kind", ""):
		"place":
			_place_loose_card(card_id, resolution.get("slot_id", ""), resolution.get("layer", ""))
		"modify":
			var loose: Dictionary = _state.get("loose", {})
			var info: Dictionary = loose.get(card_id)
			if info == null:
				return
			info["x"] = x
			info["y"] = y
			info["modifies_target"] = resolution.get("target_card_id", "")
			_world.set_loose(loose)
			ApiClient.send_ws({"type": "state", "payload": _state})
		_:
			_reposition_loose_card(card_id, x, y)


func _reposition_loose_card(card_id: String, x: float, y: float) -> void:
	var loose: Dictionary = _state.get("loose", {})
	var info: Dictionary = loose.get(card_id)
	if info == null:
		return
	info["x"] = x
	info["y"] = y
	_world.set_loose(loose)
	ApiClient.send_ws({"type": "state", "payload": _state})


## A loose card dropped onto an empty layer leaves the loose tray entirely —
## same vertical-before-horizontal + already-filled checks as _deal_into(),
## since this is the other way a layer gets filled. On rejection, re-applies
## the still-unchanged _state so the dragged node snaps back to wherever it
## actually is on record (CardWorld already moved the live node to the drop
## point during the drag itself; this is what un-does that when the drop
## doesn't stick).
func _place_loose_card(card_id: String, slot_id: String, layer: String) -> void:
	if not _slots.has(slot_id):
		return
	var cards: Dictionary = _state.get("cards", {})
	var slot: Dictionary = cards.get(slot_id, {"vertical": null, "horizontal": null})
	if slot.get(layer) != null:
		_panel.set_status("That layer is already filled")
		_world.set_loose(_state["loose"])
		return
	if layer == "horizontal" and slot.get("vertical") == null:
		_panel.set_status("Vertical must be filled first")
		_world.set_loose(_state["loose"])
		return
	if layer == "horizontal" and not _slots.get(slot_id, {}).get("horizontal_enabled", true):
		_panel.set_status("Horizontal is off for this slot")
		_world.set_loose(_state["loose"])
		return

	var loose: Dictionary = _state.get("loose", {})
	var info: Dictionary = loose.get(card_id)
	if info == null:
		return
	loose.erase(card_id)
	_state["loose"] = loose

	slot[layer] = {
		"deck_card_id": info.get("deck_card_id", card_id),
		"name": info.get("name", ""),
		"face_up": info.get("face_up", false),
		"orientation": info.get("orientation", "upright"),
		"image": info.get("image", ""),
	}
	cards[slot_id] = slot
	_state["cards"] = cards

	_world.apply_state(cards)
	_world.set_loose(loose)
	ApiClient.send_ws({"type": "state", "payload": _state})
	_refresh_deck_slot_availability()


func _invert_loose(card_id: String) -> void:
	var loose: Dictionary = _state.get("loose", {})
	var info: Dictionary = loose.get(card_id, {})
	if info.is_empty():
		return
	info["orientation"] = "reversed" if info.get("orientation", "upright") == "upright" else "upright"
	_world.set_loose(loose)
	ApiClient.send_ws({"type": "state", "payload": _state})


## Reading-Model.md's path 1 for the modifier mechanic: "right-click menu —
## controller right-clicks the loose card -> 'Modify Card' -> picks a
## target -> edge created. Works regardless of position." target_id == ""
## clears an existing link (the context menu's "Clear Modifier" item).
func _set_modifies_target(card_id: String, target_id: String) -> void:
	var loose: Dictionary = _state.get("loose", {})
	var info: Dictionary = loose.get(card_id, {})
	if info.is_empty():
		return
	info["modifies_target"] = target_id
	_world.set_loose(loose)
	ApiClient.send_ws({"type": "state", "payload": _state})


## CardWorld.begin_edge_drag()'s result — target_id == "" means the drag was
## cancelled (right-click/Escape, or released over nothing valid), in which
## case there's nothing to change.
func _on_loose_edge_resolved(source_id: String, target_id: String) -> void:
	if target_id == "":
		return
	_set_modifies_target(source_id, target_id)


## Returns every currently-tabled card to the pool before clearing — Reset is
## the only action that grows _deck_order back, so testing a layout
## repeatedly doesn't permanently deplete the deck.
func _on_reset_pressed() -> void:
	var cards: Dictionary = _state.get("cards", {})
	for slot_id in cards.keys():
		var slot: Dictionary = cards[slot_id]
		for layer in ["vertical", "horizontal"]:
			var info = slot.get(layer)
			if info != null:
				_deck_order.append(info.get("deck_card_id", ""))
	var loose: Dictionary = _state.get("loose", {})
	for card_id in loose.keys():
		_deck_order.append(card_id)
	_reset_table()


func _on_reshuffle_pressed() -> void:
	_deck_order.shuffle()
	_panel.set_status("Deck reshuffled")


func _on_unshuffle_pressed() -> void:
	var remaining: Dictionary = {}
	for card_id in _deck_order:
		remaining[card_id] = true
	_deck_order = _canonical_deck_order().filter(func(id): return remaining.has(id))
	_panel.set_status("Deck restored to catalog order")


func _new_card_layer(card_id: String) -> Dictionary:
	return {
		"deck_card_id": card_id,
		"name": _deck[card_id].get("name", card_id),
		"face_up": false,
		"orientation": "reversed" if randf() < 0.25 else "upright",
		"image": _deck[card_id].get("image", ""),
	}


func _on_controller_card_tapped(slot_id: String, layer: String) -> void:
	if layer == "loose":
		_reveal_loose(slot_id)  # loose id travels in slot_id — see CardWorld.set_loose()
	else:
		_reveal_layer(slot_id, layer)


## Tap-to-reveal, one-way only: SlotVisual's tap handler also brings a layer
## to the top of local z-order (switching which of Vertical/Horizontal is
## drawn in front), so a plain tap fires on every such switch, not just the
## first "uncover this card" tap. Toggling face_up on every tap made
## switching layers flip an already-revealed card back face-down as a side
## effect. A tap now only ever turns a card face-up; turning it back over is
## a deliberate act via the right-click "Turn" menu (_flip_layer), which
## still does a real toggle.
func _reveal_layer(slot_id: String, layer: String) -> void:
	var cards: Dictionary = _state.get("cards", {})
	var slot: Dictionary = cards.get(slot_id, {})
	var info = slot.get(layer)
	if info == null or info.get("face_up", false):
		return
	info["face_up"] = true
	_world.apply_state(cards)
	ApiClient.send_ws({"type": "state", "payload": _state})


func _flip_layer(slot_id: String, layer: String) -> void:
	var cards: Dictionary = _state.get("cards", {})
	var slot: Dictionary = cards.get(slot_id, {})
	var info = slot.get(layer)
	if info == null:
		return
	info["face_up"] = not info["face_up"]
	_world.apply_state(cards)
	ApiClient.send_ws({"type": "state", "payload": _state})


func _invert_layer(slot_id: String, layer: String) -> void:
	var cards: Dictionary = _state.get("cards", {})
	var slot: Dictionary = cards.get(slot_id, {})
	var info = slot.get(layer)
	if info == null:
		return
	info["orientation"] = "reversed" if info.get("orientation", "upright") == "upright" else "upright"
	_world.apply_state(cards)
	ApiClient.send_ws({"type": "state", "payload": _state})


## Right-click "Remove from Slot" — the un-place path dealing never needed
## until cards could be dragged around: sends a slotted card back to loose
## (still a legitimate on-table card, per Reading-Model.md, not destroyed)
## rather than into the deck. Vertical can't be pulled out from under a
## filled Horizontal — same vertical-before-horizontal rule as everywhere
## else, enforced here too even though the context menu already omits the
## option in that case.
func _remove_from_slot(slot_id: String, layer: String) -> void:
	var cards: Dictionary = _state.get("cards", {})
	var slot: Dictionary = cards.get(slot_id, {})
	var info = slot.get(layer)
	if info == null:
		return
	if layer == "vertical" and slot.get("horizontal") != null:
		_panel.set_status("Remove the Horizontal card first")
		return
	slot[layer] = null
	cards[slot_id] = slot
	_state["cards"] = cards

	# Offset below the slot rather than landing exactly on the vacated card's
	# own footprint — same position the card used to render at, pixel for
	# pixel, read as "nothing happened" (and, worse, sat exactly coincident
	# with the SlotVisual's own drawn area, which is a shared footprint no
	# other loose placement ever lands on by construction — Deal Loose's tray
	# and every drag-drop outcome both keep clear of slot origins).
	var slot_pos: Dictionary = _slots.get(slot_id, {})
	var spawn_pos := Vector2(slot_pos.get("x", 0.0), slot_pos.get("y", 0.0)) \
		+ Vector2(0.0, CardNode.CARD_SIZE.y + 40.0)
	var loose: Dictionary = _state.get("loose", {})
	loose[info.get("deck_card_id", "")] = {
		"deck_card_id": info.get("deck_card_id", ""),
		"name": info.get("name", ""),
		"face_up": info.get("face_up", false),
		"orientation": info.get("orientation", "upright"),
		"image": info.get("image", ""),
		"x": spawn_pos.x,
		"y": spawn_pos.y,
		"modifies_target": "",
	}
	_state["loose"] = loose

	_world.apply_state(cards)
	_world.set_loose(loose)
	ApiClient.send_ws({"type": "state", "payload": _state})
	_refresh_deck_slot_availability()


func _on_acl_changed(slot_id: String, layer: String, is_visible: bool, actions: Array) -> void:
	var slot_acl: Dictionary = _acl.get(slot_id, {})
	slot_acl[layer] = {"visible": is_visible, "actions": actions}
	_acl[slot_id] = slot_acl
	ApiClient.send_ws({"type": "acl", "payload": _acl})


func _on_client_action_received(card_id: String, layer: String, action: String, _user_id: int) -> void:
	if action == "flip":
		_flip_layer(card_id, layer)


# ── Card context menu (right-click) ─────────────────────────────────────────
# Ported UI pattern (not code) from Paradotz's Editor.gd:_show_node_context_menu
# — a hand-built overlay + PanelContainer + flat Buttons, not a native PopupMenu.

func _on_card_context_requested(slot_id: String, layer: String) -> void:
	if layer == "loose":
		_show_loose_context_menu(slot_id)  # loose id travels in slot_id — see CardWorld.set_loose()
	else:
		_show_card_context_menu(slot_id, layer)


func _hide_context_menu() -> void:
	if is_instance_valid(_context_menu):
		_context_menu.queue_free()
	_context_menu = null


## Shared overlay+panel scaffold (click-anywhere-else-to-dismiss) for the
## card context menu.
func _begin_context_menu() -> VBoxContainer:
	_hide_context_menu()

	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 20
	overlay.gui_input.connect(func(ev: InputEvent) -> void:
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
			_hide_context_menu()
	)
	add_child(overlay)
	_context_menu = overlay

	var menu := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.12)
	sb.border_color = Color(0.32, 0.32, 0.32)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(4)
	menu.add_theme_stylebox_override("panel", sb)
	menu.position = get_global_mouse_position()
	overlay.add_child(menu)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	menu.add_child(vbox)
	return vbox


func _show_card_context_menu(slot_id: String, layer: String) -> void:
	var vbox := _begin_context_menu()

	var label := Label.new()
	var slot_name: String = _slots.get(slot_id, {}).get("name", slot_id)
	label.text = "%s — %s" % [slot_name, ControllerPanel.LAYER_LABELS.get(layer, layer)]
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	label.custom_minimum_size = Vector2(160.0, 0.0)
	vbox.add_child(label)
	vbox.add_child(HSeparator.new())

	var is_visible: bool = _acl.get(slot_id, {}).get(layer, {}).get("visible", false)
	_add_ctx_button(vbox, "Hide" if is_visible else "Show", func() -> void: _on_ctx_show_hide(slot_id, layer))
	_add_ctx_button(vbox, "Turn", func() -> void: _flip_layer(slot_id, layer))
	_add_ctx_button(vbox, "Invert", func() -> void: _invert_layer(slot_id, layer))
	# Vertical-before-horizontal cuts both ways: same as Deal to Slot only ever
	# offering empty layers, this just omits "Remove from Slot" outright for a
	# Vertical that still has a Horizontal on it, rather than showing it and
	# rejecting the click.
	var slot_cards: Dictionary = _state.get("cards", {}).get(slot_id, {})
	if layer == "horizontal" or slot_cards.get("horizontal") == null:
		_add_ctx_button(vbox, "Remove from Slot", func() -> void: _remove_from_slot(slot_id, layer))


## Reading-Model.md's path 1 for the modifier mechanic — loose cards only.
func _show_loose_context_menu(card_id: String) -> void:
	var vbox := _begin_context_menu()

	var loose: Dictionary = _state.get("loose", {})
	var info: Dictionary = loose.get(card_id, {})

	var label := Label.new()
	label.text = "%s (loose)" % info.get("name", card_id)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	label.custom_minimum_size = Vector2(180.0, 0.0)
	vbox.add_child(label)
	vbox.add_child(HSeparator.new())

	_add_ctx_button(vbox, "Turn", func() -> void: _flip_loose(card_id))
	_add_ctx_button(vbox, "Invert", func() -> void: _invert_loose(card_id))
	# Grabs the loose end of a would-be MODIFIES edge and lets it follow the
	# mouse (CardWorld.begin_edge_drag) instead of picking a target off a text
	# list that named cards by name even face-down — the amber hover
	# highlight it shares with the loose-card drag is what actually resolves
	# it, same as dragging the card itself onto an occupied slot would.
	_add_ctx_button(vbox, "Modify Card", func() -> void: _world.begin_edge_drag(card_id))
	if info.get("modifies_target", "") != "":
		_add_ctx_button(vbox, "Clear Modifier", func() -> void: _set_modifies_target(card_id, ""))


func _add_ctx_button(vbox: VBoxContainer, text: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(160.0, 40.0)
	btn.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(func() -> void:
		cb.call()
		_hide_context_menu()
	)
	vbox.add_child(btn)


func _on_ctx_show_hide(slot_id: String, layer: String) -> void:
	var slot_acl: Dictionary = _acl.get(slot_id, {})
	var layer_acl: Dictionary = slot_acl.get(layer, {"visible": false, "actions": []})
	var new_visible: bool = not layer_acl.get("visible", false)
	layer_acl["visible"] = new_visible
	slot_acl[layer] = layer_acl
	_acl[slot_id] = slot_acl
	ApiClient.send_ws({"type": "acl", "payload": _acl})
	_panel.sync_acl(slot_id, layer, new_visible, layer_acl.get("actions", []))


func _on_client_joined(user_id: int, username: String) -> void:
	# Start Reading already sets _pending_client from the controller's own
	# picker selection (with display_name) — don't clobber it with the
	# thinner client_joined shape. Only a fallback if that somehow didn't fire.
	if _pending_client.is_empty():
		_pending_client = {"user_id": user_id, "username": username, "display_name": ""}


func _send_checkpoint(close_session: bool) -> void:
	var placements := []
	var cards: Dictionary = _state.get("cards", {})
	for slot_id in cards.keys():
		var slot: Dictionary = cards[slot_id]
		for layer in ["vertical", "horizontal"]:
			var info = slot.get(layer)
			if info == null:
				continue
			placements.append({
				"card_id": info.get("deck_card_id", ""),
				"slot": slot_id,
				"layer": layer,
				"orientation": info.get("orientation", "upright"),
				"placement": "slotted",
			})
	# Loose placements (Reading-Model.md: "Card --PLACED--> Scenario directly,
	# skipping Layer entirely... Loose-and-never-attached is a legitimate,
	# permanent end state") and any MODIFIES links go alongside, both keyed
	# by deck_card_id since it's already unique per reading (78-card catalog,
	# no duplicates).
	var modifies := []
	var loose: Dictionary = _state.get("loose", {})
	for card_id in loose.keys():
		var info: Dictionary = loose[card_id]
		placements.append({
			"card_id": card_id,
			"slot": null,
			"layer": "",
			"orientation": info.get("orientation", "upright"),
			"placement": "loose",
		})
		var target_id: String = info.get("modifies_target", "")
		if target_id != "":
			modifies.append({"card_id": card_id, "target_card_id": target_id})
	ApiClient.send_ws({
		"type": "save",
		"payload": {
			"client": (_pending_client if not _pending_client.is_empty() else null),
			"scenario": {
				"name": "Reading",
				"layout": _layouts.get(_active_layout_id, {}).get("name", ""),
				"metrics": {},
			},
			"placements": placements,
			"modifies": modifies,
			"close_session": close_session,
		},
	})


# ── Client ───────────────────────────────────────────────────────────────────

func _setup_client() -> void:
	_world = CardWorld.new()
	_world.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_world)

	_overlay = ClientOverlay.new()
	add_child(_overlay)

	_world.card_tapped.connect(_on_client_card_tapped)
	_overlay.action_chosen.connect(_on_client_action_chosen)
	ApiClient.state_received.connect(_on_state_received)
	ApiClient.ws_closed.connect(_on_client_ws_closed)

	_status_label = Label.new()
	_status_label.text = "Waiting for your reading to begin…"
	_status_label.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_status_label)

	_join_current_session()


func _join_current_session() -> void:
	var session_info: Dictionary = await ApiClient.get_current_session()
	var session_id: String = session_info.get("session_id", "")
	if session_id == "":
		await get_tree().create_timer(3.0).timeout
		_join_current_session()
		return
	ApiClient.connect_ws(session_id)
	if is_instance_valid(_status_label):
		_status_label.queue_free()


func _on_client_ws_closed() -> void:
	# Controller ended the reading (or dropped) — clear the board instead of
	# freezing on the last-seen cards, and go back to waiting for the next one.
	_last_acl = {}
	_world.apply_state({})
	_overlay.hide()
	if not is_instance_valid(_status_label):
		_status_label = Label.new()
		_status_label.set_anchors_preset(Control.PRESET_CENTER)
		add_child(_status_label)
	_status_label.text = "Waiting for your reading to begin…"
	_join_current_session()


func _on_state_received(cards: Dictionary, acl: Dictionary) -> void:
	_last_acl = acl
	_world.apply_state(cards, acl)


func _on_client_card_tapped(slot_id: String, layer: String) -> void:
	var actions: Array = _world.actions_for(slot_id, layer, _last_acl)
	_overlay.show_actions(slot_id, layer, actions)


func _on_client_action_chosen(slot_id: String, layer: String, action: String) -> void:
	ApiClient.send_ws({"type": "action", "card_id": slot_id, "layer": layer, "action": action})
