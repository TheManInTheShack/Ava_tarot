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
const VERSION := "0.2.0"

var _mode: String = ""  # "controller" | "client" | ""
var _me: Dictionary = {}
var _deck: Dictionary = {}  # card_id -> card info from cards.json

var _world: CardWorld
var _panel: ControllerPanel
var _overlay: ClientOverlay
var _status_label: Label

var _state: Dictionary = {"cards": {}}
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


func _ready() -> void:
	randomize()

	_status_label = Label.new()
	_status_label.text = "Loading…"
	_status_label.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_status_label)

	_deck = _load_deck()
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

func _setup_controller() -> void:
	var layout := HBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(layout)

	_panel = ControllerPanel.new()
	layout.add_child(_panel)
	_panel.set_version(VERSION)

	_world = CardWorld.new()
	_world.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_world.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_world)

	_panel.start_pressed.connect(_on_start_pressed)
	_panel.end_pressed.connect(_on_end_pressed)
	_panel.deal_pressed.connect(_on_deal_pressed)
	_panel.acl_changed.connect(_on_acl_changed)
	_panel.layout_selected.connect(_on_layout_selected)
	_panel.layout_created.connect(_on_layout_created)
	_panel.slot_added.connect(_on_slot_added)
	_panel.slot_updated.connect(_on_slot_updated)
	_panel.slot_deleted.connect(_on_slot_deleted)
	_world.card_tapped.connect(_on_controller_card_tapped)
	_world.card_context_requested.connect(_on_card_context_requested)

	ApiClient.action_received.connect(_on_client_action_received)
	ApiClient.client_joined.connect(_on_client_joined)

	await _load_layouts()


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
		_slots[slot_id] = {
			"name": node.get("name", slot_id),
			"x": float(props.get("x", 0.0)),
			"y": float(props.get("y", 0.0)),
			"layout_id": slot_layout[slot_id],
			"vertical_id": layers.get("vertical", ""),
			"horizontal_id": layers.get("horizontal", ""),
		}


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
	nodes.append({"id": slot_id, "type": "Slot", "name": name, "properties": {"x": x, "y": y}})
	edges.append({"id": _next_id(), "from": layout_id, "to": slot_id, "type": "HAS_SLOT", "properties": {}})

	for layer_kind in ["Vertical", "Horizontal"]:
		var layer_id := _next_id()
		var layer_name := "%s-%s-%s" % [layout_id, name.to_lower().replace(" ", "-"), layer_kind.to_lower()]
		nodes.append({"id": layer_id, "type": layer_kind, "name": layer_name, "properties": {}})
		edges.append({"id": _next_id(), "from": slot_id, "to": layer_id, "type": "HAS_LAYER", "properties": {}})

	_graph["nodes"] = nodes
	_graph["edges"] = edges
	return slot_id


func _on_layout_selected(layout_id: String) -> void:
	_active_layout_id = layout_id
	_apply_active_layout()


func _on_layout_created(name: String) -> void:
	var new_id := _create_layout_node(name)
	await _save_graph()
	_parse_layouts()
	_active_layout_id = new_id
	_apply_active_layout()


func _on_slot_added(name: String, x: float, y: float) -> void:
	if _active_layout_id == "":
		return
	_create_slot_with_layers(_active_layout_id, name, x, y)
	await _save_graph()
	_parse_layouts()
	_apply_active_layout()


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
	_apply_active_layout()


func _on_start_pressed() -> void:
	var existing: String = await ApiClient.get_current_session()
	var session_id: String = existing if existing != "" else await ApiClient.start_session()
	if session_id == "":
		_panel.set_status("Failed to start session")
		return
	ApiClient.connect_ws(session_id)
	_panel.set_status("Reading in progress")
	# Push current state immediately so a reconnect doesn't show stale data.
	ApiClient.send_ws({"type": "state", "payload": _state})
	ApiClient.send_ws({"type": "acl", "payload": _acl})


func _on_end_pressed() -> void:
	var cards: Dictionary = _state.get("cards", {})
	if not cards.is_empty():
		_send_checkpoint()
	_state = {"cards": {}}
	_acl = {}
	_pending_client = {}
	# Push the cleared state before disconnecting so any connected client's
	# view resets instead of freezing on the last-seen cards.
	ApiClient.send_ws({"type": "state", "payload": _state})
	ApiClient.send_ws({"type": "acl", "payload": _acl})
	ApiClient.disconnect_ws()
	_panel.set_status("No active reading")
	_world.apply_state(_state["cards"])


func _on_deal_pressed() -> void:
	var ids: Array = _deck.keys()
	ids.shuffle()
	var slot_ids: Array = _slots_for_layout(_active_layout_id).keys()
	var cards := {}
	var i := 0
	for slot_id in slot_ids:
		if i >= ids.size():
			break
		var card_id: String = ids[i]
		i += 1
		cards[slot_id] = {
			"vertical": _new_card_layer(card_id),
			"horizontal": null,
		}
	# Step-1-only stopgap: also deal a crossing card onto the second slot so
	# the two-layer rendering can be verified before real Deck controls
	# (Step 4) and drag-to-layer placement (Step 5) exist. Remove once "Deal
	# to Slot"/"Deal Next" land — see Meta/Reading-Model.md.
	if slot_ids.size() >= 2 and i < ids.size():
		cards[slot_ids[1]]["horizontal"] = _new_card_layer(ids[i])
	_state["cards"] = cards
	_world.apply_state(_state["cards"])
	ApiClient.send_ws({"type": "state", "payload": _state})


func _new_card_layer(card_id: String) -> Dictionary:
	return {
		"deck_card_id": card_id,
		"name": _deck[card_id].get("name", card_id),
		"face_up": false,
		"orientation": "reversed" if randf() < 0.25 else "upright",
	}


func _on_controller_card_tapped(slot_id: String, layer: String) -> void:
	_flip_layer(slot_id, layer)


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
	_show_card_context_menu(slot_id, layer)


func _hide_context_menu() -> void:
	if is_instance_valid(_context_menu):
		_context_menu.queue_free()
	_context_menu = null


func _show_card_context_menu(slot_id: String, layer: String) -> void:
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
	# "Modify Card" (loose cards only) arrives with the modifier mechanic in
	# Step 5 — no loose cards exist yet to trigger it.


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
	_pending_client = {"user_id": user_id, "username": username}


func _send_checkpoint() -> void:
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
			})
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
	var session_id: String = await ApiClient.get_current_session()
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
