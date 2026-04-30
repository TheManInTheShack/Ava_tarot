extends PanelContainer

signal layout_selected(layout_id: String)

@onready var option_button: OptionButton = $MarginContainer/HBoxContainer/OptionButton

var _layout_ids: Array[String] = []

func _ready() -> void:
	option_button.item_selected.connect(_on_item_selected)
	option_button.get_popup().add_theme_font_size_override("font_size", 30)

func populate(layouts: Array) -> void:
	option_button.clear()
	_layout_ids.clear()
	for layout in layouts:
		option_button.add_item(layout["name"])
		_layout_ids.append(layout["layout_id"])

func _on_item_selected(index: int) -> void:
	if index < _layout_ids.size():
		emit_signal("layout_selected", _layout_ids[index])
