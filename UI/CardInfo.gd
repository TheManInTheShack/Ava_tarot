extends PanelContainer

@onready var name_label:          Label         = $MarginContainer/VBoxContainer/CardNameLabel
@onready var arcana_label:        Label         = $MarginContainer/VBoxContainer/ArcanaLabel
@onready var keywords_label:      Label         = $MarginContainer/VBoxContainer/KeywordsLabel
@onready var neighbors_list:      VBoxContainer = $MarginContainer/VBoxContainer/NeighborsList
@onready var rotate_left_button:  Button        = $MarginContainer/VBoxContainer/Buttons/RotateLeftButton
@onready var rotate_right_button: Button        = $MarginContainer/VBoxContainer/Buttons/RotateRightButton
@onready var flip_button:         Button        = $MarginContainer/VBoxContainer/Buttons/FlipButton
@onready var close_button:        Button        = $MarginContainer/VBoxContainer/Buttons/CloseButton

var _current_card: CardBase = null

func _ready() -> void:
	hide()
	rotate_left_button.pressed.connect(_on_rotate_left_pressed)
	rotate_right_button.pressed.connect(_on_rotate_right_pressed)
	flip_button.pressed.connect(_on_flip_pressed)
	close_button.pressed.connect(hide)

func show_card(card: CardBase) -> void:
	_current_card = card
	if not card.is_face_up:
		name_label.text = "—"
		arcana_label.text = ""
		keywords_label.text = ""
		for child in neighbors_list.get_children():
			child.queue_free()
		show()
		return
	var data := GraphDB.get_node_data(card.card_id)
	_refresh_header(data)
	var parts: Array[String] = []
	for key in ["arcana", "element", "planet"]:
		var val = data.get(key)
		if val is String and val:
			parts.append(val)
	arcana_label.text = " · ".join(parts)
	var kw_up = data.get("keywords_upright", [])
	var kw_rv = data.get("keywords_reversed", [])
	keywords_label.text = ("↑ " + ", ".join(kw_up) + "\n↓ " + ", ".join(kw_rv)) if not data.is_empty() else ""
	_populate_neighbors(card.card_id)
	show()

func _refresh_header(data: Dictionary = {}) -> void:
	if not _current_card:
		return
	if data.is_empty():
		data = GraphDB.get_node_data(_current_card.card_id)
	var base_name: String = data.get("name", _current_card.card_id) if not data.is_empty() else _current_card.card_id
	name_label.text = (base_name + " (inverted)") if _current_card.is_reversed else base_name

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

func _on_rotate_left_pressed() -> void:
	_rotate_card(-90.0)

func _on_rotate_right_pressed() -> void:
	_rotate_card(90.0)

func _rotate_card(degrees: float) -> void:
	if not _current_card:
		return
	# Work in visual-rotation space so is_reversed and slot_rotation_degrees stay in sync.
	# Four canonical orientations: 0=upright, 90=crossing-upright, 180=inverted, 270=crossing-inverted.
	var current_visual := fmod(_current_card.rotation_degrees + 360.0, 360.0)
	var new_visual     := fmod(current_visual + degrees + 360.0, 360.0)
	var snap           := roundi(new_visual / 90.0) * 90 % 360
	match snap:
		0:
			_current_card.is_reversed          = false
			_current_card.slot_rotation_degrees = 0.0
		90:
			_current_card.is_reversed          = false
			_current_card.slot_rotation_degrees = 90.0
		180:
			_current_card.is_reversed          = true
			_current_card.slot_rotation_degrees = 0.0
		_:  # 270
			_current_card.is_reversed          = true
			_current_card.slot_rotation_degrees = 90.0
	_current_card.rotation_degrees = _current_card.slot_rotation_degrees + (180.0 if _current_card.is_reversed else 0.0)
	_current_card.queue_redraw()
	_current_card.notify_orientation_changed()
	_refresh_header()

func _on_flip_pressed() -> void:
	if _current_card:
		_current_card.flip()
