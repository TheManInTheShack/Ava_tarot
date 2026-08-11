extends Control

## Orchestrator. Determines controller vs client mode from /auth/me (no
## query-param mode switch — the client logs in as themselves, same as the
## controller) and wires up the corresponding UI. Controller holds the
## authoritative reading state locally and pushes it over the WebSocket on
## every change; client only ever renders what the server has already
## filtered through the live ACL.

const CONTROLLER_ROLES := ["admin", "dev", "user"]
const DECK_PATH := "res://Data/cards.json"

## Bump on every commit that touches this repo's source — same convention as
## Paradotz's MainMenu.gd — it's the only way to confirm a deploy took effect
## in the browser (nginx now sends Cache-Control: no-cache for /paratarot/,
## same fix as /paradotz/, but this is the actual proof).
const VERSION := "0.1.0"

var _mode: String = ""  # "controller" | "client" | ""
var _me: Dictionary = {}
var _deck: Dictionary = {}  # card_id -> card info from cards.json

var _world: CardWorld
var _panel: ControllerPanel
var _overlay: ClientOverlay
var _status_label: Label

var _state: Dictionary = {"layout": "three-card", "cards": {}}
var _acl: Dictionary = {}
var _pending_client: Dictionary = {}   # last client_joined info, for the checkpoint
var _last_acl: Dictionary = {}         # client mode only: most recent ACL received
var _context_menu: Control = null      # controller mode only: the currently-open card context menu


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
	_world.card_tapped.connect(_on_controller_card_tapped)
	_world.card_context_requested.connect(_on_card_context_requested)

	ApiClient.action_received.connect(_on_client_action_received)
	ApiClient.client_joined.connect(_on_client_joined)


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
	_state = {"layout": "three-card", "cards": {}}
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
	var slots := ["1", "2", "3"]
	var cards := {}
	var i := 0
	for slot_id in slots:
		if i >= ids.size():
			break
		var card_id: String = ids[i]
		i += 1
		cards[slot_id] = {
			"vertical": _new_card_layer(card_id),
			"horizontal": null,
		}
	# Step-1-only stopgap: also deal a crossing card onto slot "2" so the
	# two-layer rendering can be verified before real Deck controls (Step 4)
	# and drag-to-layer placement (Step 5) exist. Remove once "Deal to Slot"/
	# "Deal Next" land — see Meta/Reading-Model.md.
	if cards.has("2") and i < ids.size():
		cards["2"]["horizontal"] = _new_card_layer(ids[i])
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
	label.text = "Slot %s — %s" % [slot_id, ControllerPanel.LAYER_LABELS.get(layer, layer)]
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	label.custom_minimum_size = Vector2(220.0, 0.0)
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
	btn.custom_minimum_size = Vector2(220.0, 56.0)
	btn.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
	btn.add_theme_font_size_override("font_size", 19)
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
				"layout": _state.get("layout", "three-card"),
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
