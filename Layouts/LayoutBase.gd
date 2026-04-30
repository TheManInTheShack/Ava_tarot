extends Node2D
class_name LayoutBase

const SNAP_RADIUS    := 80.0
const CARD_LABEL_Y1  := 128.0
const CARD_LABEL_Y2  := 153.0
const CARD_LABEL_W   := 220.0

var active_cards: Array[CardBase] = []

func _ready() -> void:
	for slot in get_children():
		if slot is Marker2D:
			_add_slot_labels(slot)

func _add_slot_labels(slot: Marker2D) -> void:
	var y_off: float = slot.get_meta("label_y_offset", 0.0)
	for lbl_name in ["CardLabel1", "CardLabel2"]:
		var lbl := Label.new()
		lbl.name = lbl_name
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.position = Vector2(-CARD_LABEL_W * 0.5, (CARD_LABEL_Y1 if lbl_name == "CardLabel1" else CARD_LABEL_Y2) + y_off)
		lbl.custom_minimum_size = Vector2(CARD_LABEL_W, 0.0)
		lbl.z_index = 200
		slot.add_child(lbl)

func register_card(card: CardBase) -> void:
	active_cards.append(card)
	card.card_dropped.connect(_on_card_dropped)
	card.card_drag_started.connect(_on_card_drag_started)
	card.card_flipped.connect(_on_card_flipped)
	card.card_orientation_changed.connect(_on_card_orientation_changed)

func unregister_card(card: CardBase) -> void:
	active_cards.erase(card)
	if card.card_dropped.is_connected(_on_card_dropped):
		card.card_dropped.disconnect(_on_card_dropped)
	if card.card_drag_started.is_connected(_on_card_drag_started):
		card.card_drag_started.disconnect(_on_card_drag_started)
	if card.card_flipped.is_connected(_on_card_flipped):
		card.card_flipped.disconnect(_on_card_flipped)
	if card.card_orientation_changed.is_connected(_on_card_orientation_changed):
		card.card_orientation_changed.disconnect(_on_card_orientation_changed)

func place_in_slot(card: CardBase, slot: Marker2D) -> void:
	var primary: CardBase = slot.get_meta("assigned_card", null)
	if primary == null or primary == card:
		slot.set_meta("assigned_card", card)
	else:
		slot.set_meta("superposition_card", card)
	card.global_position = slot.global_position
	card.in_slot = true
	if slot.get_meta("force_reversed", false):
		card.is_reversed = true
		card.rotation_degrees = card.slot_rotation_degrees + (180.0 if (card.is_face_up and card.is_reversed) else 0.0)
		card.notify_orientation_changed()
	card.queue_redraw()
	_update_slot_labels(slot)

func _on_card_dropped(card: CardBase, drop_pos: Vector2) -> void:
	for slot in get_children():
		if not slot is Marker2D:
			continue
		if slot.global_position.distance_to(drop_pos) < SNAP_RADIUS:
			place_in_slot(card, slot)
			return

func _on_card_drag_started(card: CardBase) -> void:
	for slot in get_children():
		if not slot is Marker2D:
			continue
		if slot.get_meta("assigned_card", null) == card:
			slot.remove_meta("assigned_card")
			var super_card: CardBase = slot.get_meta("superposition_card", null)
			if super_card:
				slot.set_meta("assigned_card", super_card)
				slot.remove_meta("superposition_card")
			_update_slot_labels(slot)
			return
		if slot.get_meta("superposition_card", null) == card:
			slot.remove_meta("superposition_card")
			_update_slot_labels(slot)
			return

func _on_card_flipped(card: CardBase, _is_face_up: bool) -> void:
	var slot := _find_slot_for_card(card)
	if slot:
		_update_slot_labels(slot)

func _on_card_orientation_changed(card: CardBase) -> void:
	var slot := _find_slot_for_card(card)
	if slot:
		_update_slot_labels(slot)

func _find_slot_for_card(card: CardBase) -> Marker2D:
	for slot in get_children():
		if not slot is Marker2D:
			continue
		if slot.get_meta("assigned_card", null) == card:
			return slot
		if slot.get_meta("superposition_card", null) == card:
			return slot
	return null

func _update_slot_labels(slot: Marker2D) -> void:
	var lbl1: Label = slot.get_node_or_null("CardLabel1")
	var lbl2: Label = slot.get_node_or_null("CardLabel2")
	if not lbl1 or not lbl2:
		return
	var primary: CardBase   = slot.get_meta("assigned_card", null)
	var super_card: CardBase = slot.get_meta("superposition_card", null)
	lbl1.text = _card_slot_text(primary)
	lbl2.text = _card_slot_text(super_card)

func _card_slot_text(card: CardBase) -> String:
	if not card:
		return ""
	if not card.is_face_up:
		return "—"
	var name_str := card.card_name if card.card_name else card.card_id
	return (name_str + " (inverted)") if card.is_reversed else name_str
