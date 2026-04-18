extends PanelContainer

@onready var name_label:     Label         = $MarginContainer/VBoxContainer/CardNameLabel
@onready var arcana_label:   Label         = $MarginContainer/VBoxContainer/ArcanaLabel
@onready var keywords_label: Label         = $MarginContainer/VBoxContainer/KeywordsLabel
@onready var neighbors_list: VBoxContainer = $MarginContainer/VBoxContainer/NeighborsList
@onready var flip_button:    Button        = $MarginContainer/VBoxContainer/Buttons/FlipButton
@onready var close_button:   Button        = $MarginContainer/VBoxContainer/Buttons/CloseButton

var _current_card: CardBase = null

func _ready() -> void:
	hide()
	flip_button.pressed.connect(_on_flip_pressed)
	close_button.pressed.connect(hide)

func show_card(card: CardBase) -> void:
	_current_card = card
	var data := GraphDB.get_node_data(card.card_id)
	name_label.text = data.get("name", card.card_id) if not data.is_empty() else card.card_id
	var arcana: String  = data.get("arcana", "")
	var element: String = data.get("element", "")
	var planet: String  = data.get("planet", "")
	var parts: Array[String] = []
	if arcana:  parts.append(arcana)
	if element: parts.append(element)
	if planet:  parts.append(planet)
	arcana_label.text = " · ".join(parts)
	var kw_up: Array = data.get("keywords_upright", [])
	var kw_rv: Array = data.get("keywords_reversed", [])
	keywords_label.text = ("↑ " + ", ".join(kw_up) + "\n↓ " + ", ".join(kw_rv)) if not data.is_empty() else ""
	_populate_neighbors(card.card_id)
	show()

func _populate_neighbors(card_id: String) -> void:
	for child in neighbors_list.get_children():
		child.queue_free()
	for edge in GraphDB.get_neighbors(card_id):
		var target_data := GraphDB.get_node_data(edge["target"])
		var target_name: String = target_data.get("name", edge["target"])
		var lbl := Label.new()
		lbl.text = "→ %s  [%s]" % [target_name, edge["relationship"]]
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		neighbors_list.add_child(lbl)

func _on_flip_pressed() -> void:
	if _current_card:
		_current_card.flip()
