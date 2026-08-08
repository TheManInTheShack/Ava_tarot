extends Control

## Orchestrator. Determines controller vs client mode from /auth/me (no
## query-param mode switch — the client logs in as themselves, same as the
## controller) and wires up the corresponding UI. Controller holds the
## authoritative reading state locally and pushes it over the WebSocket on
## every change; client only ever renders what the server has already
## filtered through the live ACL.

const CONTROLLER_ROLES := ["admin", "dev", "user"]
const DECK_PATH := "res://Data/cards.json"

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

	_world = CardWorld.new()
	_world.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_world.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_world)

	_panel.start_pressed.connect(_on_start_pressed)
	_panel.end_pressed.connect(_on_end_pressed)
	_panel.deal_pressed.connect(_on_deal_pressed)
	_panel.acl_changed.connect(_on_acl_changed)
	_world.card_tapped.connect(_on_controller_card_tapped)

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
	ApiClient.disconnect_ws()
	_panel.set_status("No active reading")
	_state = {"layout": "three-card", "cards": {}}
	_acl = {}
	_pending_client = {}
	_world.apply_state(_state["cards"])


func _on_deal_pressed() -> void:
	var ids: Array = _deck.keys()
	ids.shuffle()
	var slots := ["1", "2", "3"]
	var cards := {}
	for i in range(slots.size()):
		if i >= ids.size():
			break
		var card_id: String = ids[i]
		cards[slots[i]] = {
			"deck_card_id": card_id,
			"name": _deck[card_id].get("name", card_id),
			"face_up": false,
			"orientation": "reversed" if randf() < 0.25 else "upright",
		}
	_state["cards"] = cards
	_world.apply_state(_state["cards"])
	ApiClient.send_ws({"type": "state", "payload": _state})


func _on_controller_card_tapped(slot_id: String) -> void:
	_flip_slot(slot_id)


func _flip_slot(slot_id: String) -> void:
	var cards: Dictionary = _state.get("cards", {})
	if not cards.has(slot_id):
		return
	cards[slot_id]["face_up"] = not cards[slot_id]["face_up"]
	_world.apply_state(cards)
	ApiClient.send_ws({"type": "state", "payload": _state})


func _on_acl_changed(slot_id: String, is_visible: bool, actions: Array) -> void:
	_acl[slot_id] = {"visible": is_visible, "actions": actions}
	ApiClient.send_ws({"type": "acl", "payload": _acl})


func _on_client_action_received(card_id: String, action: String, _user_id: int) -> void:
	if action == "flip":
		_flip_slot(card_id)


func _on_client_joined(user_id: int, username: String) -> void:
	_pending_client = {"user_id": user_id, "username": username}


func _send_checkpoint() -> void:
	var placements := []
	var cards: Dictionary = _state.get("cards", {})
	for slot_id in cards.keys():
		var info: Dictionary = cards[slot_id]
		placements.append({
			"card_id": info.get("deck_card_id", ""),
			"slot": slot_id,
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


func _on_state_received(cards: Dictionary, acl: Dictionary) -> void:
	_last_acl = acl
	_world.apply_state(cards, acl)


func _on_client_card_tapped(slot_id: String) -> void:
	var actions: Array = _world.actions_for(slot_id, _last_acl)
	_overlay.show_actions(slot_id, actions)


func _on_client_action_chosen(slot_id: String, action: String) -> void:
	ApiClient.send_ws({"type": "action", "card_id": slot_id, "action": action})
