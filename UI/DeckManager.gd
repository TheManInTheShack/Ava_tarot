extends PanelContainer

signal shuffle_requested
signal deal_requested(count: int)

@onready var shuffle_button:  Button = $MarginContainer/VBoxContainer/ShuffleButton
@onready var deal_button:     Button = $MarginContainer/VBoxContainer/DealButton
@onready var remaining_label: Label  = $MarginContainer/VBoxContainer/RemainingLabel

func _ready() -> void:
	shuffle_button.pressed.connect(_on_shuffle_pressed)
	deal_button.pressed.connect(_on_deal_pressed)
	update_remaining()

func update_remaining() -> void:
	remaining_label.text = "Cards remaining: %d" % DeckState.cards_remaining()

func _on_shuffle_pressed() -> void:
	emit_signal("shuffle_requested")

func _on_deal_pressed() -> void:
	emit_signal("deal_requested", 1)
