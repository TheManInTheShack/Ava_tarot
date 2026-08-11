class_name CardWorld
extends Control

## The pannable/zoomable card table. Technique ported from Paradotz's
## Editor.gd: a plain Control `_world` child stands in for a camera — its
## `position`/`scale` do the pan/zoom job (`_apply_world_transform()`'s
## pattern), no Camera2D needed. Pan/zoom input isn't wired up yet (not
## needed for one fixed 3-slot layout that fits on screen) but the structure
## is here so it's a trivial follow-on rather than a rework.
##
## Renders whatever `apply_state()` is given. In controller mode that's the
## full authoritative state (acl omitted); in client mode it's already been
## filtered server-side, but the acl is still passed through so per-card
## `interactive` can be set correctly for tap-to-act.

signal card_tapped(slot_id: String, layer: String)
signal card_context_requested(slot_id: String, layer: String)

const LAYERS := ["vertical", "horizontal"]

var _cards: Dictionary = {}          # "slot_id:layer" -> CardNode
var _slot_geometry: Dictionary = {}  # slot_id -> {"name", "x", "y"} — set via set_slots()
var _slot_labels: Dictionary = {}    # slot_id -> Label
var _world: Control


static func _key(slot_id: String, layer: String) -> String:
	return "%s:%s" % [slot_id, layer]


func _ready() -> void:
	_world = Control.new()
	_world.name = "World"
	_world.set_anchors_preset(Control.PRESET_FULL_RECT)
	_world.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_world)


## slots: {slot_id: {"name": String, "x": float, "y": float}} — loaded from
## the active Layout's graph nodes (Main._apply_active_layout), replacing
## what used to be the hardcoded THREE_CARD_SLOTS/SLOT_LABELS consts.
func set_slots(slots: Dictionary) -> void:
	_slot_geometry = slots
	for slot_id in _slot_labels.keys().duplicate():
		if not slots.has(slot_id):
			_slot_labels[slot_id].queue_free()
			_slot_labels.erase(slot_id)
	for slot_id in slots.keys():
		var info: Dictionary = slots[slot_id]
		var pos := Vector2(info.get("x", 0.0), info.get("y", 0.0))
		var label: Label = _slot_labels.get(slot_id)
		if label == null:
			label = Label.new()
			label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			_world.add_child(label)
			_slot_labels[slot_id] = label
		label.text = info.get("name", "")
		label.position = pos + Vector2(0, -26)
	# Re-apply any already-placed cards so they follow updated positions.
	for key in _cards.keys():
		var node: CardNode = _cards[key]
		if _slot_geometry.has(node.slot_id):
			var g: Dictionary = _slot_geometry[node.slot_id]
			node.position = Vector2(g.get("x", 0.0), g.get("y", 0.0))


## cards: {slot_id: {"vertical": {deck_card_id, name, face_up, orientation}|null,
##                    "horizontal": {...}|null}}
## acl: {} to show everything with no interaction (controller's own view of
## its authoritative state), or
## {slot_id: {"vertical": {"visible": bool, "actions": [...]}, "horizontal": {...}}}
## to both filter and mark which layers are currently tappable — layers are
## controlled independently, per Meta/Reading-Model.md.
func apply_state(cards: Dictionary, acl: Dictionary = {}) -> void:
	var seen: Dictionary = {}
	for slot_id in cards.keys():
		var slot_info: Dictionary = cards[slot_id]
		var slot_acl: Dictionary = acl.get(slot_id, {})
		for layer in LAYERS:
			var info = slot_info.get(layer)
			if info == null:
				continue
			var layer_acl: Dictionary = slot_acl.get(layer, {})
			var visible_to_viewer: bool = acl.is_empty() or layer_acl.get("visible", false)
			if not visible_to_viewer:
				continue
			var key := _key(slot_id, layer)
			seen[key] = true

			var node: CardNode = _cards.get(key)
			if node == null:
				node = CardNode.new()
				node.slot_id = slot_id
				node.layer = layer
				var g: Dictionary = _slot_geometry.get(slot_id, {})
				node.position = Vector2(g.get("x", 0.0), g.get("y", 0.0))
				node.tapped.connect(_on_card_tapped)
				node.context_requested.connect(_on_card_context_requested)
				_world.add_child(node)
				_cards[key] = node

			node.deck_card_id = info.get("deck_card_id", "")
			node.card_name = info.get("name", "")
			node.set_face_up(info.get("face_up", false))
			node.set_orientation(info.get("orientation", "upright"))
			var can_act: Array = layer_acl.get("actions", [])
			node.set_interactive(acl.is_empty() or can_act.size() > 0)

	for key in _cards.keys().duplicate():
		if not seen.has(key):
			_cards[key].queue_free()
			_cards.erase(key)


func _on_card_tapped(slot_id: String, layer: String) -> void:
	card_tapped.emit(slot_id, layer)


func _on_card_context_requested(slot_id: String, layer: String) -> void:
	card_context_requested.emit(slot_id, layer)


func actions_for(slot_id: String, layer: String, acl: Dictionary) -> Array:
	return acl.get(slot_id, {}).get(layer, {}).get("actions", [])
