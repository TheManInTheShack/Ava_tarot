extends Node

var nodes: Dictionary = {}
var edges: Array = []

func _ready() -> void:
	load_data()

func load_data() -> void:
	var file := FileAccess.open("res://Data/cards.json", FileAccess.READ)
	if not file:
		push_error("GraphDB: could not open Data/cards.json")
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("GraphDB: JSON parse error: " + json.get_error_message())
		return
	var data: Dictionary = json.data
	nodes = data.get("nodes", {})
	edges = data.get("edges", [])

func get_node_data(card_id: String) -> Dictionary:
	return nodes.get(card_id, {})

func get_neighbors(card_id: String) -> Array:
	return edges.filter(func(e): return e["source"] == card_id)

func get_all_card_ids() -> Array:
	return nodes.keys()
