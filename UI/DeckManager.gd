extends PanelContainer

signal shuffle_requested
signal deal_requested(count: int)
signal next_requested
signal save_requested
signal history_requested

@onready var shuffle_button:  Button = $MarginContainer/VBoxContainer/ShuffleButton
@onready var deal_button:     Button = $MarginContainer/VBoxContainer/DealButton
@onready var next_button:     Button = $MarginContainer/VBoxContainer/NextButton
@onready var remaining_label: Label  = $MarginContainer/VBoxContainer/RemainingLabel
@onready var save_button:     Button = $MarginContainer/VBoxContainer/SaveButton
@onready var history_button:  Button = $MarginContainer/VBoxContainer/HistoryButton

func _ready() -> void:
	shuffle_button.pressed.connect(_on_shuffle_pressed)
	deal_button.pressed.connect(_on_deal_pressed)
	next_button.pressed.connect(_on_next_pressed)
	save_button.pressed.connect(_on_save_pressed)
	history_button.pressed.connect(_on_history_pressed)
	update_remaining()

func update_remaining() -> void:
	remaining_label.text = "Cards remaining: %d" % DeckState.cards_remaining()

func flash_saved() -> void:
	save_button.text = "Saved!"
	await get_tree().create_timer(1.5).timeout
	save_button.text = "Save Reading"

func _on_shuffle_pressed() -> void:
	emit_signal("shuffle_requested")

func _on_deal_pressed() -> void:
	emit_signal("deal_requested", 1)

func _on_next_pressed() -> void:
	emit_signal("next_requested")

func _on_save_pressed() -> void:
	emit_signal("save_requested")

func _on_history_pressed() -> void:
	emit_signal("history_requested")
