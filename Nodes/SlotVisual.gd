class_name SlotVisual
extends Control

## One cohesive object per Slot, replacing what used to be three
## independent, silently-desyncing pieces: a sibling Label for the slot
## name (positioned once by CardWorld.set_slots() and never touched again
## until the next full rebuild — which is why it used to snap into place
## after a drag instead of following it live), and two CardNode instances
## created/destroyed ad hoc by CardWorld.apply_state(). Now: name label,
## both card layers, and a name sub-label under each are all real children
## of one node, so moving *this* node (CardWorld.set_slots() sets
## `.position`) carries everything with it in one step.
##
## Glow and halo are drawn directly in this node's own _draw() rather than
## as separate child Controls — a CanvasItem's own _draw() content always
## renders before (behind) its children, so this puts them behind the cards
## and labels for free, no manual z-ordering needed. Both are pure
## draw_circle()/draw_arc() primitives, deliberately not GradientTexture2D
## — its fill/fill_from/fill_to shape isn't grounded against any existing
## code in this repo, whereas draw_circle/draw_arc are basic, certain
## CanvasItem primitives.

signal card_tapped(layer: String)
signal card_context_requested(layer: String)

## The crossing pair's combined footprint (Vertical + a 90°-rotated
## Horizontal, both centered on the same point) is roughly 280x280 — but
## since the cards themselves are fully opaque, only the ring OUTSIDE that
## footprint is ever visible at all. First pass (200) was "indiscernible"
## once cards are in place; 320 was liked but asked to be reined in
## slightly. Tune freely; nothing else depends on these exact numbers.
const GLOW_RADIUS := 280.0
const HALO_INNER_RADIUS := 296.0
const HALO_OUTER_RADIUS := 312.0
const GLOW_STEPS := 24  # concentric rings approximating a radial fade
const GLOW_FALLOFF_EXPONENT := 1.4
const GLOW_PEAK_ALPHA := 0.4

var slot_id: String = ""
var _name_label: Label
var _cards: Dictionary = {}       # "vertical"/"horizontal" -> CardNode
var _sub_labels: Dictionary = {}  # "vertical"/"horizontal" -> Label
var _glow_color: Color = Color.WHITE
var _halo_color: Color = Color(1.0, 1.0, 1.0, 0.0)  # alpha 0 — nothing to show yet, see class doc


func _ready() -> void:
	custom_minimum_size = CardNode.CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # only the cards themselves are interactive
	# Scaling (CardWorld.set_slots() sets .scale directly — Godot's own
	# transform, no wrapper method needed) pivots around the crossing pair's
	# center rather than the slot's x/y origin (top-left of the Vertical
	# card), so resizing doesn't visibly shift the slot's table position.
	pivot_offset = CardNode.CARD_SIZE / 2.0

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_name_label.position = Vector2(-40, -26)
	_name_label.size = Vector2(CardNode.CARD_SIZE.x + 80, 20)
	add_child(_name_label)

	# Vertical first, Horizontal after — later siblings draw on top, so this
	# is the default stack order: "default to vertical with horizontal
	# closer to the user" (closer to the viewer = in front).
	_build_card_layer("vertical")
	_build_card_layer("horizontal")

	_build_sub_label("vertical", CardNode.CARD_SIZE.y + 4.0)
	_build_sub_label("horizontal", CardNode.CARD_SIZE.y + 22.0)


func _draw() -> void:
	var center: Vector2 = CardNode.CARD_SIZE / 2.0
	for i in range(GLOW_STEPS, 0, -1):
		var t: float = float(i) / float(GLOW_STEPS)
		var r: float = GLOW_RADIUS * t
		var a: float = _glow_color.a * GLOW_PEAK_ALPHA * pow(1.0 - t, GLOW_FALLOFF_EXPONENT)
		draw_circle(center, r, Color(_glow_color.r, _glow_color.g, _glow_color.b, a))
	if _halo_color.a > 0.0:
		var mid_r: float = (HALO_INNER_RADIUS + HALO_OUTER_RADIUS) / 2.0
		draw_arc(center, mid_r, 0.0, TAU, 64, _halo_color, HALO_OUTER_RADIUS - HALO_INNER_RADIUS)


func _build_card_layer(layer: String) -> void:
	var node := CardNode.new()
	node.slot_id = slot_id
	node.layer = layer
	node.visible = false
	node.tapped.connect(func(_sid: String, _lyr: String) -> void:
		_bring_to_top(layer)
		card_tapped.emit(layer)
	)
	node.context_requested.connect(func(_sid: String, _lyr: String) -> void: card_context_requested.emit(layer))
	add_child(node)
	_cards[layer] = node


func _build_sub_label(layer: String, y: float) -> void:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	label.position = Vector2(-40, y)
	label.size = Vector2(CardNode.CARD_SIZE.x + 80, 18)
	label.visible = false
	add_child(label)
	_sub_labels[layer] = label


## Purely a render-order swap, local to this node's own children — no data
## changes, matches the ask exactly ("switch their positions visibly,
## without changing any data behavior").
func _bring_to_top(layer: String) -> void:
	var node: CardNode = _cards.get(layer)
	if node != null:
		move_child(node, get_child_count() - 1)


func set_name_text(text: String) -> void:
	_name_label.text = text


func set_glow_color(color: Color) -> void:
	_glow_color = color
	queue_redraw()


func set_halo_color(color: Color) -> void:
	_halo_color = color
	queue_redraw()


## info: {"deck_card_id","name","face_up","orientation","image"} or null to
## clear/hide this layer entirely. The name sub-label only ever shows once
## face_up is true — it must not leak a face-down card's identity to a
## client who can see a card is *there* (ACL "visible") but shouldn't know
## *what* it is yet. Same rule for controller and client: this is the same
## shared component either way.
func set_layer(layer: String, info, interactive: bool) -> void:
	var node: CardNode = _cards[layer]
	var label: Label = _sub_labels[layer]
	if info == null:
		node.visible = false
		label.visible = false
		return
	node.visible = true
	node.deck_card_id = info.get("deck_card_id", "")
	node.card_name = info.get("name", "")
	node.set_face_up(info.get("face_up", false))
	node.set_orientation(info.get("orientation", "upright"))
	node.set_image(info.get("image", ""))
	node.set_interactive(interactive)

	var face_up: bool = info.get("face_up", false)
	label.visible = face_up
	if face_up:
		var suffix: String = " (inv)" if info.get("orientation", "upright") == "reversed" else ""
		label.text = "%s%s" % [info.get("name", ""), suffix]


## For the modifier mechanic's connecting-line lookup (CardWorld._find_card_node)
## — a modify target isn't restricted to loose cards, it can be a slotted one.
func get_card_node_for(deck_card_id: String) -> CardNode:
	for layer in ["vertical", "horizontal"]:
		var node: CardNode = _cards[layer]
		if node.visible and node.deck_card_id == deck_card_id:
			return node
	return null
