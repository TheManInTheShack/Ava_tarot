class_name CardNode
extends Control

## A single card layer on the table. Slotted layers (vertical/horizontal)
## live at a fixed slot position — tap-to-act (flip) and right-click for the
## context menu, both gated by `interactive`, which the world/panel sets from
## the live ACL. Loose cards (layer == "loose") can additionally be dragged —
## see CardWorld's press-then-track handling of drag_pressed.
## Ported technique (not code) from Paradotz's Nodes/GraphNode.gd: custom
## _draw() per instance, tap/right-click handled in _gui_input.

signal tapped(slot_id: String, layer: String)
signal context_requested(slot_id: String, layer: String)
signal drag_pressed(card_id: String)  # loose cards only — see _gui_input()

const CARD_SIZE := Vector2(160, 280)

## Shared with anything that needs to know "does a slot at this position
## collide with another one" — CardWorld's drag snap-back and
## ControllerPanel's Add Slot nudge both call slot_collision_rect() rather
## than each keeping their own copy of these margins, so the two can never
## quietly disagree about what counts as too close.
const SLOT_MARGIN_X := 10.0   # horizontal breathing room between neighboring slots
const SLOT_MARGIN_TOP := 30.0  # extra room above, for the slot-name label drawn there


static func slot_collision_rect(pos: Vector2) -> Rect2:
	return Rect2(
		pos.x - SLOT_MARGIN_X, pos.y - SLOT_MARGIN_TOP,
		CARD_SIZE.x + SLOT_MARGIN_X * 2.0, CARD_SIZE.y + SLOT_MARGIN_TOP,
	)

var slot_id: String = ""
var layer: String = "vertical"       # "vertical" (primary), "horizontal" (crossing/modifier), or
                                      # "loose" (untethered — slot_id holds deck_card_id instead
                                      # of a real slot, see CardWorld.set_loose())
var deck_card_id: String = ""
var card_name: String = ""
var face_up: bool = false
var orientation: String = "upright"  # "upright" or "reversed"
var interactive: bool = false        # whether a tap currently does anything
var highlighted: bool = false        # drag-hover feedback only — the loose-drag "which
                                      # occupied card would this modify" target (amber),
                                      # distinct from `interactive`'s ACL-driven border
var drop_hint: bool = false          # drag-hover feedback for an EMPTY layer (green) —
                                      # CardWorld forces this node .visible while true and
                                      # this draws an outline only, ignoring face_up/texture/
                                      # any stale data left over from before it was emptied

static var back_texture: Texture2D = null
var front_texture: Texture2D = null
var _loose_label: Label = null  # only built for layer == "loose" — see _build_loose_label()

## Shared across every CardNode — 78 cards, no reason to load the same PNG
## twice for two instances of the same card_id (e.g. a slotted copy and a
## loose one can't coexist, but a fresh deal after Reset reuses card_ids).
static var _texture_cache: Dictionary = {}  # image filename -> Texture2D


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	pivot_offset = CARD_SIZE / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	if back_texture == null:
		back_texture = _load_texture("card_back_default.png")
	if layer == "loose":
		_build_loose_label()


## A loose card's own name sub-label — same idea as SlotVisual's per-layer
## sub-labels (name + " (inv)" when reversed, shown only face_up so a
## face-down card's identity doesn't leak) but simpler, "a mini-slot without
## all the other stuff": just a plain child Label, no glow/halo/second layer.
## Being a real child means it travels with this node for free on every
## position update, drag included — Godot's own transform composition
## handles that automatically, no per-frame sync code needed. Only its own
## local position/rotation ever need an explicit update, and only when
## orientation or face_up actually change (_refresh_loose_label()).
func _build_loose_label() -> void:
	_loose_label = Label.new()
	_loose_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loose_label.add_theme_font_size_override("font_size", 13)
	_loose_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	_loose_label.size = Vector2(CARD_SIZE.x + 80.0, 18.0)
	_loose_label.visible = false
	add_child(_loose_label)


## Counter-rotates against this node's own reversed_angle() so the label
## reads upright regardless of orientation, and swaps which local edge it
## anchors to (the pre-rotation "below" edge when upright, the pre-rotation
## "above" edge when reversed — the 180° flip sends that to the physical
## below either way) so it stays under the card on the table rather than
## flipping to sit above it when reversed — same anchor-point reasoning as
## CardWorld's modify-link endpoints.
func _refresh_loose_label() -> void:
	if _loose_label == null:
		return
	_loose_label.visible = face_up
	if not face_up:
		return
	_loose_label.text = "%s%s" % [card_name, " (inv)" if orientation == "reversed" else ""]
	if orientation == "reversed":
		_loose_label.rotation = -PI
		_loose_label.position = Vector2(-40.0, -22.0)
	else:
		_loose_label.rotation = 0.0
		_loose_label.position = Vector2(-40.0, CARD_SIZE.y + 4.0)


## image_filename comes straight from Data/cards.json's "image" field
## (Main.gd's _new_card_layer()) — empty for a card whose art isn't in
## Assets/Images/ yet, in which case _draw() already falls back to the
## name-text placeholder.
func set_image(image_filename: String) -> void:
	front_texture = _load_texture(image_filename)
	queue_redraw()


static func _load_texture(image_filename: String) -> Texture2D:
	if image_filename == "":
		return null
	if _texture_cache.has(image_filename):
		return _texture_cache[image_filename]
	var path := "res://Assets/Images/%s" % image_filename
	if not ResourceLoader.exists(path):
		_texture_cache[image_filename] = null
		return null
	var tex: Texture2D = load(path)
	_texture_cache[image_filename] = tex
	return tex


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, CARD_SIZE)

	# Drop-hint is a pure outline, deliberately not the normal fill/texture
	# path below — this node is forced .visible while empty specifically to
	# show this, and face_up/deck_card_id/textures can be stale leftovers
	# from whatever last occupied this layer before it was cleared.
	if drop_hint:
		draw_rect(rect, Color(0.35, 0.85, 0.35, 0.9), false, 4.0)
		return

	draw_rect(rect, Color(0.08, 0.08, 0.08), true)
	draw_rect(rect, Color(0.3, 0.3, 0.3), false, 2.0)

	if face_up:
		if front_texture != null:
			draw_texture_rect(front_texture, rect, false)
		else:
			draw_string(ThemeDB.fallback_font, Vector2(10, CARD_SIZE.y / 2.0), card_name,
				HORIZONTAL_ALIGNMENT_LEFT, CARD_SIZE.x - 20, 18)
	else:
		if back_texture != null:
			draw_texture_rect(back_texture, rect, false)
		else:
			draw_rect(rect, Color(0.15, 0.1, 0.25), true)

	if interactive:
		draw_rect(rect, Color(0.63, 0.78, 0.2), false, 3.0)
	if highlighted:
		draw_rect(rect, Color(0.85, 0.65, 0.15), false, 4.0)


func set_face_up(value: bool) -> void:
	face_up = value
	queue_redraw()
	_refresh_loose_label()


func set_orientation(value: String) -> void:
	orientation = value
	_update_rotation()
	_refresh_loose_label()


func set_layer(value: String) -> void:
	layer = value
	_update_rotation()


## Total rotation combines two independent facts: which layer this is
## (vertical=0°, horizontal=90°, structural; loose cards aren't crossing
## anything so they get no layer angle) and whether it's reversed (+180°,
## instance-level) — see Meta/Reading-Model.md's structural-vs-instance
## property split.
func _update_rotation() -> void:
	rotation = layer_angle() + reversed_angle()


func layer_angle() -> float:
	return (PI / 2.0) if layer == "horizontal" else 0.0


func reversed_angle() -> float:
	return PI if orientation == "reversed" else 0.0


## The transform this node would have if it were upright — used for the
## modify-link anchor points, which should sit at the physical edge of where
## the card structurally sits in its slot (top for Vertical/loose, the
## crossing rotation's equivalent for Horizontal) regardless of whether the
## card itself happens to be reversed. Temporarily drops rotation to just the
## structural layer_angle, reads Godot's own real global transform (already
## correctly composed through pivot/scale/the parent chain), then restores
## it — far less error-prone than re-deriving Control's transform
## composition by hand for a one-off calculation.
func get_layer_transform() -> Transform2D:
	var real_rotation := rotation
	rotation = layer_angle()
	var t := get_global_transform()
	rotation = real_rotation
	return t


func set_interactive(value: bool) -> void:
	interactive = value
	queue_redraw()


func set_highlighted(value: bool) -> void:
	highlighted = value
	queue_redraw()


## Loose cards defer the left-press to drag_pressed instead of firing tapped
## immediately — CardWorld tracks press-then-motion (same press-then-track
## technique as its slot markers) to tell a plain tap (still flips, via
## CardWorld re-emitting tapped itself once a press resolves as a non-drag)
## apart from a real drag. Slotted layers are untouched: no drag mechanic for
## them yet, tapped still fires immediately on press.
func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if layer == "loose":
				drag_pressed.emit(slot_id)
			else:
				tapped.emit(slot_id, layer)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			context_requested.emit(slot_id, layer)
			accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		if layer == "loose":
			drag_pressed.emit(slot_id)
		else:
			tapped.emit(slot_id, layer)
		accept_event()
