extends Node2D

@onready var table:           Node2D        = $Table
@onready var card_info:       PanelContainer = $UILayer/CardInfo
@onready var deck_manager:    PanelContainer = $UILayer/DeckManager
@onready var layout_selector: PanelContainer = $UILayer/LayoutSelector

var _card_scene: PackedScene = preload("res://Cards/CardBase.tscn")
var _layout_data: Dictionary = {}
var _active_layout: LayoutBase = null
var _spawned_cards: Array[CardBase] = []

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
	layout_selector.layout_selected.connect(_apply_layout)
	layout_selector.populate(_layout_data.values())
	var all_ids := GraphDB.get_all_card_ids()
	DeckState.shuffle_deck(all_ids)
	deck_manager.update_remaining()

func _apply_layout(layout_id: String) -> void:
	for card in _spawned_cards:
		card.queue_free()
	_spawned_cards.clear()
	if _active_layout:
		_active_layout.queue_free()
		_active_layout = null

	var layout_info: Dictionary = _layout_data.get(layout_id, {})
	if layout_info.is_empty():
		return

	var scene_path: String = layout_info.get("godot_scene", "")
	if scene_path and ResourceLoader.exists(scene_path):
		var scene: PackedScene = load(scene_path)
		_active_layout = scene.instantiate()
		table.add_child(_active_layout)

func _on_shuffle() -> void:
	DeckState.shuffle_deck(GraphDB.get_all_card_ids())
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
	card.global_position = Vector2(randf_range(-80, 80), randf_range(-40, 40))
	card.card_clicked.connect(_on_card_clicked)
	if _active_layout:
		_active_layout.register_card(card)
	table.add_child(card)
	_spawned_cards.append(card)

func _on_card_clicked(card: CardBase) -> void:
	card.flip()
	card_info.show_card(card)
