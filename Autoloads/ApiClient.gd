extends Node

## Backend client autoload. REST idiom mirrored from Paradotz's GraphStore.gd:
## spawn an HTTPRequest child, await request_completed, queue_free it. Session
## auth is handled implicitly by the browser cookie — no manual token handling.
## Adds a WebSocketPeer connection for the tarot realtime sync on top of that.

signal state_received(cards: Dictionary, acl: Dictionary)
signal action_received(card_id: String, layer: String, action: String, user_id: int)
signal client_joined(user_id: int, username: String)
signal ws_opened()
signal ws_closed()

var _base_url: String = ""   # grant-api, via nginx's /api/ prefix
var _auth_url: String = ""   # grant-auth, via nginx's /auth/ prefix
var _ws_base: String = ""    # same origin as _base_url, ws(s):// scheme

var _ws: WebSocketPeer = null
var ws_connected: bool = false


func _ready() -> void:
	if OS.get_name() == "Web":
		var origin: String = JavaScriptBridge.eval("window.location.origin", true)
		_base_url = origin + "/api"
		_auth_url = origin + "/auth"
		_ws_base = origin.replace("https://", "wss://").replace("http://", "ws://")
	else:
		# Local/desktop fallback for testing outside a browser — talks directly
		# to the backend services, bypassing nginx (no session cookie handling,
		# so /auth/me will 401 here; only useful for non-auth local checks).
		_base_url = "http://127.0.0.1:8001"
		_auth_url = "http://127.0.0.1:3001"
		_ws_base = "ws://127.0.0.1:8001"


# ── REST ─────────────────────────────────────────────────────────────────────

func _req(method: int, base: String, path: String, body: String = "") -> Array:
	var req := HTTPRequest.new()
	add_child(req)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := req.request(base + path, headers, method, body)
	if err != OK:
		req.queue_free()
		return [err, -1, PackedStringArray(), PackedByteArray()]
	var result: Array = await req.request_completed
	req.queue_free()
	return result


func _parse_body(result: Array) -> Variant:
	var body: PackedByteArray = result[3]
	if body.is_empty():
		return null
	return JSON.parse_string(body.get_string_from_utf8())


func get_me() -> Dictionary:
	var r: Array = await _req(HTTPClient.METHOD_GET, _auth_url, "/me")
	if r[1] != 200:
		return {}
	var parsed: Variant = _parse_body(r)
	return parsed if parsed is Dictionary else {}


## The controller declares the client at instantiation (Meta/Reading-Model.md)
## — server writes the Session node + FOR_CLIENT edge atomically before this
## returns. Returns {} on failure, else {"session_id", "session_number",
## "graph_session_node_id"}.
func start_session(client_user_id: int, client_username: String, client_display_name: String) -> Dictionary:
	var body := JSON.stringify({
		"client_user_id": client_user_id,
		"client_username": client_username,
		"client_display_name": client_display_name,
	})
	var r: Array = await _req(HTTPClient.METHOD_POST, _base_url, "/paratarot/sessions", body)
	if r[1] != 201:
		return {}
	var parsed: Variant = _parse_body(r)
	return parsed if parsed is Dictionary and parsed.has("session_id") else {}


## Controller-side client picker for Session start — public-role accounts only.
func get_clients() -> Array:
	var r: Array = await _req(HTTPClient.METHOD_GET, _auth_url, "/clients")
	if r[1] != 200:
		return []
	var parsed: Variant = _parse_body(r)
	return parsed if parsed is Array else []


## Returns {} if there's no active reading, else {"session_id",
## "session_number", "graph_session_node_id"} of the site's one active session.
func get_current_session() -> Dictionary:
	var r: Array = await _req(HTTPClient.METHOD_GET, _base_url, "/paratarot/sessions/current")
	if r[1] != 200:
		return {}
	var parsed: Variant = _parse_body(r)
	return parsed if parsed is Dictionary and parsed.has("session_id") else {}


## Generic graph read/write — the same GET/PUT /graphs/{name} endpoints
## Paradotz itself uses to edit a graph. Layout/Slot editing is a graph
## read-mutate-write, not a bespoke Paratarot endpoint — see
## Meta/Reading-Model.md's guiding principle.
func get_graph(name: String) -> Dictionary:
	var r: Array = await _req(HTTPClient.METHOD_GET, _base_url, "/graphs/" + name.uri_encode())
	if r[1] != 200:
		return {}
	var parsed: Variant = _parse_body(r)
	return parsed if parsed is Dictionary else {}


func save_graph(name: String, data: Dictionary) -> Dictionary:
	var r: Array = await _req(HTTPClient.METHOD_PUT, _base_url, "/graphs/" + name.uri_encode(), JSON.stringify(data))
	if r[1] != 200:
		return {}
	var parsed: Variant = _parse_body(r)
	return parsed if parsed is Dictionary else {}


# ── WebSocket ────────────────────────────────────────────────────────────────

func connect_ws(session_id: String) -> void:
	_ws = WebSocketPeer.new()
	var url := _ws_base + "/ws/paratarot/" + session_id
	var err := _ws.connect_to_url(url)
	if err != OK:
		push_warning("ApiClient: failed to start WebSocket connection: %s" % err)
		_ws = null
		return
	set_process(true)


func disconnect_ws() -> void:
	if _ws != null:
		_ws.close()
	_ws = null
	ws_connected = false
	set_process(false)


func _process(_delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not ws_connected:
			ws_connected = true
			ws_opened.emit()
		while _ws.get_available_packet_count() > 0:
			var pkt := _ws.get_packet().get_string_from_utf8()
			_handle_ws_message(pkt)
	elif state == WebSocketPeer.STATE_CLOSED:
		if ws_connected:
			ws_connected = false
			ws_closed.emit()
		set_process(false)
		_ws = null


func _handle_ws_message(raw: String) -> void:
	var msg: Variant = JSON.parse_string(raw)
	if not (msg is Dictionary):
		return
	match msg.get("type", ""):
		"state":
			var payload: Dictionary = msg.get("payload", {})
			state_received.emit(payload.get("cards", {}), msg.get("acl", {}))
		"action":
			action_received.emit(
				String(msg.get("card_id", "")),
				String(msg.get("layer", "vertical")),
				String(msg.get("action", "")),
				int(msg.get("user_id", 0))
			)
		"client_joined":
			client_joined.emit(int(msg.get("user_id", 0)), String(msg.get("username", "")))


func send_ws(msg: Dictionary) -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))
