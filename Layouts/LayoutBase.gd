extends Node2D
class_name LayoutBase

const SNAP_RADIUS := 80.0

var active_cards: Array[CardBase] = []

func register_card(card: CardBase) -> void:
	active_cards.append(card)
	card.card_dropped.connect(_on_card_dropped)

func unregister_card(card: CardBase) -> void:
	active_cards.erase(card)
	if card.card_dropped.is_connected(_on_card_dropped):
		card.card_dropped.disconnect(_on_card_dropped)

func _on_card_dropped(card: CardBase, drop_pos: Vector2) -> void:
	for slot in get_children():
		if not slot is Marker2D:
			continue
		if slot.global_position.distance_to(drop_pos) < SNAP_RADIUS:
			card.slot_rotation_degrees = slot.get_meta("slot_rotation", 0.0)
			card.global_position = slot.global_position
			card.rotation_degrees = card.slot_rotation_degrees
			if slot.get_meta("force_reversed", false):
				card.is_reversed = true
			slot.set_meta("assigned_card", card)
			return
