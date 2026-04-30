extends Node

var deck_order: Array[String] = []
var card_orientations: Dictionary = {}
var reversal_probability: float = 0.33
var draw_index: int = 0

func shuffle_deck(card_ids: Array) -> Array:
	deck_order.assign(card_ids)
	deck_order.shuffle()
	card_orientations.clear()
	for id in deck_order:
		card_orientations[id] = randf() < reversal_probability
	draw_index = 0
	return deck_order

func draw_card() -> String:
	if draw_index >= deck_order.size():
		return ""
	var card_id := deck_order[draw_index]
	draw_index += 1
	return card_id

func is_reversed(card_id: String) -> bool:
	return card_orientations.get(card_id, false)

func cards_remaining() -> int:
	return deck_order.size() - draw_index

func reset_draw() -> void:
	draw_index = 0
