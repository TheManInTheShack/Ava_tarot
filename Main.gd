extends Node2D

@onready var table:           Node2D         = $Table
@onready var camera:          Camera2D       = $Camera2D
@onready var card_info:        PanelContainer = $UILayer/CardInfo
@onready var deck_manager:     PanelContainer = $UILayer/DeckManager
@onready var layout_selector:  PanelContainer = $UILayer/LayoutSelector
@onready var reading_history:  PanelContainer = $UILayer/ReadingHistory

var _card_scene: PackedScene = preload("res://Cards/CardBase.tscn")
var _layout_data: Dictionary = {}
var _active_layout: LayoutBase = null
var _active_layout_id: String = ""
var _spawned_cards: Array[CardBase] = []
var _z_counter: int = 0

func _ready() -> void:
	_load_layout_data()
	_setup_ui()
	_apply_layout("three-card")

func _load_layout_data() -> void:
	var file := FileAccess.open("res://Data/layouts.json", FileAccess.READ)
	if not file:
		push_error("Main: could not open Data/layouts.json")
		return
	var json := JSON.new()
	json.parse(file.get_as_text())
	file.close()
	for layout in json.data.get("layouts", []):
		_layout_data[layout["layout_id"]] = layout

func _setup_ui() -> void:
	deck_manager.shuffle_requested.connect(_on_shuffle)
	deck_manager.deal_requested.connect(_on_deal)
	deck_manager.next_requested.connect(_on_next)
	deck_manager.save_requested.connect(_on_save_reading)
	deck_manager.history_requested.connect(_on_show_history)
	layout_selector.layout_selected.connect(_apply_layout)
	layout_selector.populate(_layout_data.values())
	var all_ids := GraphDB.get_all_card_ids()
	DeckState.shuffle_deck(all_ids)
	deck_manager.update_remaining()

func _apply_layout(layout_id: String) -> void:
	for card in _spawned_cards:
		card.queue_free()
	_spawned_cards.clear()
	_z_counter = 0
	if _active_layout:
		_active_layout.queue_free()
		_active_layout = null
	DeckState.shuffle_deck(GraphDB.get_all_card_ids())
	deck_manager.update_remaining()

	var layout_info: Dictionary = _layout_data.get(layout_id, {})
	if layout_info.is_empty():
		return

	_active_layout_id = layout_id
	var scene_path: String = layout_info.get("godot_scene", "")
	if scene_path and ResourceLoader.exists(scene_path):
		var scene: PackedScene = load(scene_path)
		_active_layout = scene.instantiate()
		table.add_child(_active_layout)
	camera.global_position = _layout_camera_position()
	camera.zoom = Vector2.ONE

func _on_shuffle() -> void:
	var in_play: Array = _spawned_cards.map(func(c: CardBase) -> String: return c.card_id)
	var remaining: Array = GraphDB.get_all_card_ids().filter(func(id: String) -> bool: return not in_play.has(id))
	DeckState.shuffle_deck(remaining)
	deck_manager.update_remaining()

func _on_deal(_count: int) -> void:
	var card_id := DeckState.draw_card()
	if not card_id.is_empty():
		_spawn_card(card_id)
	deck_manager.update_remaining()

func _spawn_card(card_id: String) -> void:
	var card: CardBase = _card_scene.instantiate()
	card.card_id   = card_id
	var data := GraphDB.get_node_data(card_id)
	card.card_name  = data.get("name", card_id)
	card.is_reversed = DeckState.is_reversed(card_id)
	card.is_face_up  = false
	var image_file: String = data.get("image", "")
	if image_file:
		var tex_path := "res://Assets/Images/" + image_file
		if ResourceLoader.exists(tex_path):
			card.face_texture = load(tex_path) as Texture2D
	var spread := float(_z_counter - 1)
	card.global_position = Vector2(randf_range(-60, 60) + spread * 12.0, randf_range(-20, 20) - spread * 8.0)
	_z_counter += 1
	card.base_z_index = _z_counter
	card.z_index = _z_counter
	card.card_clicked.connect(_on_card_clicked)
	card.card_drag_started.connect(_on_card_drag_started)
	card.card_flipped.connect(_on_card_flipped)
	if _active_layout:
		_active_layout.register_card(card)
	table.add_child(card)
	_spawned_cards.append(card)

func _layout_camera_position() -> Vector2:
	if not _active_layout:
		return Vector2.ZERO
	var min_x := INF;  var max_x := -INF
	var min_y := INF;  var max_y := -INF
	for slot in _active_layout.get_children():
		if slot is Marker2D:
			min_x = minf(min_x, slot.position.x)
			max_x = maxf(max_x, slot.position.x)
			min_y = minf(min_y, slot.position.y)
			max_y = maxf(max_y, slot.position.y)
	if min_x == INF:
		return Vector2.ZERO
	var center := Vector2((min_x + max_x) / 2.0, (min_y + max_y) / 2.0)
	# Place layout center at 30% down from top (shift camera down by 20% of viewport height)
	var vertical_offset := 1920.0 * 0.1
	return Vector2(center.x, center.y + vertical_offset)

func _next_open_slot() -> Marker2D:
	if not _active_layout:
		return null
	var slots: Array = []
	for child in _active_layout.get_children():
		if child is Marker2D:
			slots.append(child)
	slots.sort_custom(func(a: Marker2D, b: Marker2D) -> bool:
		return a.get_meta("slot_id", 0) < b.get_meta("slot_id", 0))
	for slot in slots:
		if not slot.has_meta("assigned_card"):
			return slot
	return null

func _on_next() -> void:
	var slot := _next_open_slot()
	if not slot:
		return
	var card_id := DeckState.draw_card()
	if card_id.is_empty():
		deck_manager.update_remaining()
		return
	_spawn_card(card_id)
	var card: CardBase = _spawned_cards.back()
	card.slot_rotation_degrees = slot.get_meta("slot_rotation", 0.0)
	card.rotation_degrees = card.slot_rotation_degrees + (180.0 if (card.is_face_up and card.is_reversed) else 0.0)
	_active_layout.place_in_slot(card, slot)
	deck_manager.update_remaining()

func _on_card_drag_started(card: CardBase) -> void:
	_z_counter += 1
	card.base_z_index = _z_counter
	card.z_index = _z_counter

func _on_card_flipped(card: CardBase, is_face_up: bool) -> void:
	if is_face_up:
		card_info.show_card(card)

func _on_card_clicked(card: CardBase) -> void:
	_z_counter += 1
	card.base_z_index = _z_counter
	card.z_index = _z_counter
	card_info.show_card(card)

# ── Reading capture ───────────────────────────────────────────────────────────

func _on_show_history() -> void:
	reading_history.show_history()

func _on_save_reading() -> void:
	if not _active_layout:
		return
	var placements := _collect_placements()
	if placements.is_empty():
		return
	var dt := Time.get_datetime_dict_from_system()
	var reading := {
		"reading_id": "reading-%04d%02d%02d-%d" % [dt.year, dt.month, dt.day, Time.get_ticks_msec()],
		"layout_id":  _active_layout_id,
		"timestamp":  Time.get_datetime_string_from_system(),
		"querent":    "",
		"notes":      "",
		"placements": placements,
		"metrics":    _compute_metrics(placements),
	}
	_write_reading(reading)
	deck_manager.flash_saved()

func _collect_placements() -> Array:
	var slots: Array = []
	for child in _active_layout.get_children():
		if child is Marker2D:
			slots.append(child)
	slots.sort_custom(func(a: Marker2D, b: Marker2D) -> bool:
		return a.get_meta("slot_id", 0) < b.get_meta("slot_id", 0))
	var result: Array = []
	for slot in slots:
		var card: CardBase = slot.get_meta("assigned_card", null)
		if not card or not card.is_face_up:
			continue
		result.append({
			"slot_id":    int(slot.get_meta("slot_id", 0)),
			"slot_label": slot.get_meta("label", ""),
			"card_id":    card.card_id,
			"card_name":  card.card_name,
			"orientation": _card_orientation(card),
		})
	return result

func _card_orientation(card: CardBase) -> String:
	var is_crossing := absf(fmod(card.slot_rotation_degrees, 180.0)) > 22.5
	if is_crossing:
		return "crosses_reversed" if card.is_reversed else "crosses_upright"
	return "placed_reversed" if card.is_reversed else "placed_upright"

func _compute_metrics(placements: Array) -> Dictionary:
	var total := float(placements.size())
	var majors    := 0
	var suits     := {"Wands": 0, "Cups": 0, "Swords": 0, "Pentacles": 0}
	var reversed  := 0
	var courts    := 0
	for p in placements:
		var data := GraphDB.get_node_data(p["card_id"])
		if data.get("arcana") == "Major":
			majors += 1
		var suit_val = data.get("suit")
		var suit: String = suit_val if suit_val is String else ""
		if suit in suits:
			suits[suit] += 1
		if (p["orientation"] as String).ends_with("_reversed"):
			reversed += 1
		if _is_court(p["card_id"]):
			courts += 1
	return {
		"major_ratio":     majors         / total,
		"wands_frac":      suits["Wands"]     / total,
		"cups_frac":       suits["Cups"]      / total,
		"swords_frac":     suits["Swords"]    / total,
		"pents_frac":      suits["Pentacles"] / total,
		"inversion_ratio": reversed        / total,
		"court_ratio":     courts          / total,
	}

func _is_court(card_id: String) -> bool:
	if card_id.begins_with("MA-"):
		return false
	var parts := card_id.split("-")
	return parts.size() >= 2 and parts[1].to_int() >= 11

func _write_reading(reading: Dictionary) -> void:
	var path := "user://readings.json"
	var all: Array = []
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var j := JSON.new()
			if j.parse(f.get_as_text()) == OK:
				all = j.data
			f.close()
	if _is_duplicate_reading(reading, all):
		return
	all.append(reading)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(all, "\t"))
		f.close()

func _is_duplicate_reading(reading: Dictionary, all: Array) -> bool:
	if all.is_empty():
		return false
	var last: Dictionary = all.back()
	if last.get("layout_id") != reading.get("layout_id"):
		return false
	var new_placements: Array = reading.get("placements", [])
	var last_placements: Array = last.get("placements", [])
	if new_placements.size() != last_placements.size():
		return false
	for i in new_placements.size():
		var a: Dictionary = new_placements[i]
		var b: Dictionary = last_placements[i]
		if a.get("card_id") != b.get("card_id") or a.get("slot_id") != b.get("slot_id") or a.get("orientation") != b.get("orientation"):
			return false
	return true
