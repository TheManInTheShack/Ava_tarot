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
signal slot_drag_ended(slot_id: String, x: float, y: float)
signal slot_dragging(slot_id: String, x: float, y: float)  # fires every drag-motion frame, for ControllerPanel's live X/Y fields
## Fires once a loose-card drag ends with real movement. resolution is one of:
## {"kind":"reposition"} — dropped on empty table, just moved
## {"kind":"place","slot_id":..,"layer":..} — dropped on an empty layer
## {"kind":"modify","target_card_id":..} — dropped on an already-occupied card
signal loose_drag_resolved(card_id: String, x: float, y: float, resolution: Dictionary)
## Reading-Model.md's path 1 (right-click "Modify Card"), now resolved by
## dragging the edge's loose end rather than picking from a text list — see
## begin_edge_drag(). target_card_id == "" means the drag was cancelled
## (released over nothing valid).
signal loose_edge_resolved(source_id: String, target_card_id: String)
## The deck's own draw gesture (DeckVisual.draw_started) resolved — Main.gd
## owns _deck_order/_state, so it creates the actual loose card, then calls
## begin_loose_drag() to hand it back already following the cursor.
signal deck_draw_requested()

const LAYERS := ["vertical", "horizontal"]
const DRAG_THRESHOLD := 6.0

var _slot_geometry: Dictionary = {}  # slot_id -> {"name", "x", "y", "horizontal_enabled"} — set via set_slots()
var _slot_visuals: Dictionary = {}   # slot_id -> SlotVisual — see Nodes/SlotVisual.gd
var _world: Control
var _loose_nodes: Dictionary = {}    # deck_card_id -> CardNode, set via set_loose()
var _modify_links: Array = []        # [[Vector2 from, Vector2 to], ...], world-local, for _draw()

# Layout-editing (mod mode) slot markers — see set_layout_mod_mode().
var _layout_mod_mode: bool = false
var _slot_markers: Dictionary = {}   # slot_id -> Control, draggable placeholder shown only in mod mode
var _drag_slot_id: String = ""
var _dragging: bool = false
var _press_start_local: Vector2 = Vector2.ZERO
var _drag_grab_offset: Vector2 = Vector2.ZERO
var _drag_orig_pos: Vector2 = Vector2.ZERO

# Loose-card dragging (Reading-Model.md's modifier-mechanic drag path) — same
# press-then-track technique as the slot markers above, tracked separately
# since the two drags are mutually exclusive but otherwise independent.
var _drag_loose_id: String = ""
var _loose_dragging: bool = false
var _loose_press_start_local: Vector2 = Vector2.ZERO
var _loose_drag_grab_offset: Vector2 = Vector2.ZERO
var _loose_drag_orig_pos: Vector2 = Vector2.ZERO
var _last_loose: Dictionary = {}  # most recent set_loose() call, so a live drag can re-run _rebuild_modify_links() mid-motion

# Shared drag-hover highlight — at most one node highlighted at a time, used
# by both the loose-card drag above and the edge drag below. _kind decides
# whether clearing it means "un-amber an occupied card" (highlighted flag,
# node stays as it was) or "un-green an empty layer" (drop_hint flag, and the
# node must go back to .visible = false since it was only shown for the hint).
var _drag_hover_node: CardNode = null
var _drag_hover_kind: String = ""  # "modify" | "place"

# Edge dragging (Reading-Model.md's path 1, "Modify Card") — begins from a
# context-menu click rather than a canvas press, so there's no press-then-
# track threshold here: the pending edge just follows the mouse from the
# moment it starts until the next click resolves or right-click cancels it.
var _edge_drag_source_id: String = ""

# The deck marker — see Nodes/DeckVisual.gd. Always present (not data-driven
# from _state the way slots/loose cards are), one per CardWorld. Reposition-
# dragging it is handled entirely here, same press-then-track shape as the
# slot markers; drawing from it hands off to the loose-card drag machinery
# above via begin_loose_drag().
var _deck_visual: DeckVisual
var _dragging_deck: bool = false
var _deck_drag_grab_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	_world = Control.new()
	_world.name = "World"
	_world.set_anchors_preset(Control.PRESET_FULL_RECT)
	_world.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_world)

	_deck_visual = DeckVisual.new()
	_deck_visual.drag_started.connect(_on_deck_drag_started)
	_deck_visual.draw_started.connect(_on_deck_draw_started)
	_world.add_child(_deck_visual)


## slots: {slot_id: {"name": String, "x": float, "y": float}} — loaded from
## the active Layout's graph nodes (Main._apply_active_layout), replacing
## what used to be the hardcoded THREE_CARD_SLOTS/SLOT_LABELS consts.
## Each slot is one SlotVisual (name label + both card layers + their name
## sub-labels + glow/halo, all as one node) — moving *it* on drag/Save
## Layout carries everything with it, unlike the old separate sibling Label
## that only snapped into place on the next full rebuild.
func set_slots(slots: Dictionary) -> void:
	_slot_geometry = slots
	for slot_id in _slot_visuals.keys().duplicate():
		if not slots.has(slot_id):
			_slot_visuals[slot_id].queue_free()
			_slot_visuals.erase(slot_id)
	for slot_id in slots.keys():
		var info: Dictionary = slots[slot_id]
		var pos := Vector2(info.get("x", 0.0), info.get("y", 0.0))
		var visual: SlotVisual = _slot_visuals.get(slot_id)
		if visual == null:
			visual = SlotVisual.new()
			visual.slot_id = slot_id
			visual.card_tapped.connect(func(layer: String) -> void: _on_card_tapped(slot_id, layer))
			visual.card_context_requested.connect(func(layer: String) -> void: _on_card_context_requested(slot_id, layer))
			_world.add_child(visual)
			_slot_visuals[slot_id] = visual
		visual.position = pos
		visual.set_name_text(info.get("name", ""))
		# Plain Control.scale — SlotVisual's own pivot_offset centers it on
		# the crossing pair, so this scales glow/halo/cards/labels together
		# around that point without shifting the slot's table position.
		var s: float = info.get("scale", 1.0)
		visual.scale = Vector2(s, s)
	_rebuild_slot_markers()


## Live preview only, while the size slider is being dragged — doesn't
## touch _slot_geometry or persist anything. The next real set_slots()
## call (Save Layout committing, or switching away without saving)
## re-applies the authoritative scale from parsed graph data, which
## naturally snaps an unsaved preview back to whatever's actually saved.
func preview_slot_scale(slot_id: String, scale: float) -> void:
	var visual: SlotVisual = _slot_visuals.get(slot_id)
	if visual != null:
		visual.scale = Vector2(scale, scale)


## Live preview only, while the x/y fields are being edited — doesn't touch
## _slot_geometry or persist anything, same rule as preview_slot_scale.
## Also moves this slot's own drag marker (if mod mode is showing one) so
## the two don't visibly drift apart from each other during the preview.
func preview_slot_position(slot_id: String, x: float, y: float) -> void:
	var pos := Vector2(x, y)
	var visual: SlotVisual = _slot_visuals.get(slot_id)
	if visual != null:
		visual.position = pos
	var marker: Control = _slot_markers.get(slot_id)
	if marker != null and slot_id != _drag_slot_id:  # don't fight an active drag
		marker.position = pos


## Shows/hides the draggable slot-position markers — only live while
## actually editing a Layout (ControllerPanel's "Modify" button), so no drag
## input runs at all during normal reading interactions.
func set_layout_mod_mode(on: bool) -> void:
	_layout_mod_mode = on
	_rebuild_slot_markers()


## Reused (not fully torn down and rebuilt) so a slot mid-drag isn't yanked
## out from under the user if this gets called for an unrelated reason —
## reposition existing markers, add new ones, remove stale ones, same shape
## as set_slots()'s own label handling above.
func _rebuild_slot_markers() -> void:
	if not _layout_mod_mode:
		for m in _slot_markers.values():
			m.queue_free()
		_slot_markers.clear()
		return
	for slot_id in _slot_markers.keys().duplicate():
		if not _slot_geometry.has(slot_id):
			_slot_markers[slot_id].queue_free()
			_slot_markers.erase(slot_id)
	for slot_id in _slot_geometry.keys():
		var g: Dictionary = _slot_geometry[slot_id]
		var marker: Control = _slot_markers.get(slot_id)
		if marker == null:
			marker = _make_slot_marker(slot_id)
			_world.add_child(marker)
			_slot_markers[slot_id] = marker
		if slot_id != _drag_slot_id:  # don't fight the position of whatever's actively being dragged
			marker.position = Vector2(g.get("x", 0.0), g.get("y", 0.0))


func _make_slot_marker(slot_id: String) -> Control:
	var marker := Panel.new()
	marker.custom_minimum_size = CardNode.CARD_SIZE
	marker.size = CardNode.CARD_SIZE
	marker.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.4, 0.7, 1.0, 0.12)
	sb.border_color = Color(0.4, 0.7, 1.0, 0.65)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	marker.add_theme_stylebox_override("panel", sb)
	marker.gui_input.connect(func(ev: InputEvent) -> void: _on_slot_marker_gui_input(slot_id, marker, ev))
	return marker


## Only handles the press — gui_input stops firing the moment the mouse
## leaves the marker's own bounds, which a real drag does almost
## immediately, so tracking motion/release has to happen at the CardWorld
## level via _input() instead (see below). Ported concept, not code, from
## the same problem Paradotz's Editor.gd solves for node dragging.
func _on_slot_marker_gui_input(slot_id: String, marker: Control, ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		_drag_slot_id = slot_id
		_drag_orig_pos = marker.position
		_press_start_local = _world.get_local_mouse_position()
		_drag_grab_offset = marker.position - _press_start_local
		_dragging = false
		marker.get_parent().move_child(marker, marker.get_parent().get_child_count() - 1)
		set_process_input(true)


## The four drags (slot markers, loose cards, a pending modify edge, the deck
## marker) are mutually exclusive — only one can be active at a time — so a
## single _input() dispatches to whichever one is active rather than needing
## its own per-mode signal.
func _input(event: InputEvent) -> void:
	if _drag_slot_id != "":
		_input_slot_drag(event)
	elif _drag_loose_id != "":
		_input_loose_drag(event)
	elif _edge_drag_source_id != "":
		_input_edge_drag(event)
	elif _dragging_deck:
		_input_deck_drag(event)


func _input_slot_drag(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cur: Vector2 = _world.get_local_mouse_position()
		if not _dragging and cur.distance_to(_press_start_local) > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			var marker: Control = _slot_markers.get(_drag_slot_id)
			if marker != null:
				marker.position = cur + _drag_grab_offset
				# Live preview, same rule as preview_slot_position()/preview_slot_scale():
				# the real SlotVisual (cards/glow) tracks the drag, not just the
				# translucent marker, and ControllerPanel's X/Y fields follow along too
				# — none of this touches _slot_geometry or persists anything.
				var visual: SlotVisual = _slot_visuals.get(_drag_slot_id)
				if visual != null:
					visual.position = marker.position
				slot_dragging.emit(_drag_slot_id, marker.position.x, marker.position.y)
				# Keep any modify-link line honest while its slotted endpoint moves —
				# same fix as the loose-drag path below, same underlying cause
				# (_rebuild_modify_links only ran from set_loose(), never mid-drag).
				_rebuild_modify_links(_last_loose)
				queue_redraw()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_end_slot_drag()
		get_viewport().set_input_as_handled()


## A plain click (no real movement) just releases the press with no effect
## — slot markers have nothing else to do on tap, unlike cards. A drag that
## would land on top of another slot (margin included) snaps back to where
## it started rather than partially clamping to the nearest legal spot;
## simplest rule that's still always predictable.
func _end_slot_drag() -> void:
	var slot_id: String = _drag_slot_id
	var marker: Control = _slot_markers.get(slot_id)
	var was_dragging: bool = _dragging
	_drag_slot_id = ""
	_dragging = false
	set_process_input(false)
	if marker == null or not was_dragging:
		return
	if _overlaps_others(slot_id, marker.position):
		marker.position = _drag_orig_pos
		var visual: SlotVisual = _slot_visuals.get(slot_id)
		if visual != null:
			visual.position = _drag_orig_pos
		slot_dragging.emit(slot_id, _drag_orig_pos.x, _drag_orig_pos.y)
		return
	slot_drag_ended.emit(slot_id, marker.position.x, marker.position.y)


## Collision margins live on CardNode (slot_collision_rect) — shared with
## ControllerPanel's Add Slot nudge, so drag snap-back and placement-time
## nudging can never disagree about what counts as too close.
func _overlaps_others(slot_id: String, pos: Vector2) -> bool:
	var rect := CardNode.slot_collision_rect(pos)
	for other_id in _slot_geometry.keys():
		if other_id == slot_id:
			continue
		var g: Dictionary = _slot_geometry[other_id]
		var other_rect := CardNode.slot_collision_rect(Vector2(g.get("x", 0.0), g.get("y", 0.0)))
		if rect.intersects(other_rect):
			return true
	return false


# ── Loose-card dragging (Reading-Model.md's drag-and-drop modifier path) ────
# Press-then-track technique, same shape as the slot markers above but a
# separate state block since a card is a real CardNode being moved directly
# (no separate marker object needed - there's nothing to keep in sync).

func _on_loose_drag_pressed(card_id: String) -> void:
	var node: CardNode = _loose_nodes.get(card_id)
	if node == null:
		return
	_drag_loose_id = card_id
	_loose_drag_orig_pos = node.position
	_loose_press_start_local = _world.get_local_mouse_position()
	_loose_drag_grab_offset = node.position - _loose_press_start_local
	_loose_dragging = false
	node.get_parent().move_child(node, node.get_parent().get_child_count() - 1)
	set_process_input(true)


func _input_loose_drag(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cur: Vector2 = _world.get_local_mouse_position()
		if not _loose_dragging and cur.distance_to(_loose_press_start_local) > DRAG_THRESHOLD:
			_loose_dragging = true
		if _loose_dragging:
			var node: CardNode = _loose_nodes.get(_drag_loose_id)
			if node != null:
				node.position = cur + _loose_drag_grab_offset
				_update_loose_drag_highlight(node)
				# Same fix as the slot-drag path above: a modify-link line was only
				# ever recomputed from set_loose(), so it used to sit still until the
				# drag finished and the state round-tripped back, then jump to catch
				# up. Recomputed from the live node position every motion frame now.
				_rebuild_modify_links(_last_loose)
				queue_redraw()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_end_loose_drag()
		get_viewport().set_input_as_handled()


## A plain click (no real movement past DRAG_THRESHOLD) is the existing
## tap-to-flip gesture - CardNode deferred its tapped.emit() to us via
## drag_pressed precisely so we could tell the two apart here, so a
## non-drag release re-emits it ourselves to preserve that behavior exactly.
func _end_loose_drag() -> void:
	var card_id: String = _drag_loose_id
	var node: CardNode = _loose_nodes.get(card_id)
	var was_dragging: bool = _loose_dragging
	_drag_loose_id = ""
	_loose_dragging = false
	set_process_input(false)
	_clear_drag_hover()
	if node == null:
		return
	if not was_dragging:
		card_tapped.emit(card_id, "loose")
		return
	var resolution: Dictionary = _resolve_loose_drop(node.position)
	loose_drag_resolved.emit(card_id, node.position.x, node.position.y, resolution)


## Reading-Model.md's resolution, generalized, with one deliberate priority
## reversal (2026-08-16 feedback): when both cards are already occupied, a
## modify hit always wins over a place hit — checked first below, matching
## the live hover highlight's own "amber sits above green" precedence there,
## and Horizontal is checked first for a modify hit since it draws on top
## (SlotVisual's default stack, "closer to the user"). But when Vertical is
## filled and Horizontal is still open, that priority flips: Horizontal's own
## footprint (wider than Vertical's, from the crossing rotation — it reads as
## "the whole middle") takes priority to fill it, and amber modify only
## applies to whatever's left of Vertical's rect outside that middle band
## (its top/bottom strips) — dragging to the middle to fill Horizontal is the
## more intuitive default gesture there, not the exception. Horizontal is
## excluded from ever being a place target when the slot's own
## horizontal_enabled is off — a filled Vertical then reads as the whole slot
## being full, per the Layout editor's "Horizontal on" checkbox. No hit at
## all (dropped clear of every slot, or in the dead zone of a slot whose
## Horizontal is off) means "just repositioned" - the drag never fails, per
## the doc, it just falls back to the plainest outcome.
func _resolve_loose_drop(drag_pos: Vector2) -> Dictionary:
	var world_point: Vector2 = get_global_transform() * (drag_pos + CardNode.CARD_SIZE / 2.0)
	for slot_id in _slot_geometry.keys():
		var visual: SlotVisual = _slot_visuals.get(slot_id)
		if visual == null:
			continue
		var v_node: CardNode = visual.get_layer_node("vertical")
		var h_node: CardNode = visual.get_layer_node("horizontal")
		if v_node == null:
			continue
		var h_enabled: bool = _slot_geometry[slot_id].get("horizontal_enabled", true)
		var v_filled: bool = v_node.visible
		var h_filled: bool = h_node != null and h_node.visible

		if not v_filled:
			if _node_hit(v_node, world_point):
				return {"kind": "place", "slot_id": slot_id, "layer": "vertical"}
			continue

		if h_filled:
			if _node_hit(h_node, world_point):
				return {"kind": "modify", "target_card_id": h_node.deck_card_id}
			if _node_hit(v_node, world_point):
				return {"kind": "modify", "target_card_id": v_node.deck_card_id}
			continue

		if h_enabled and h_node != null and _node_hit(h_node, world_point):
			return {"kind": "place", "slot_id": slot_id, "layer": "horizontal"}
		if _node_hit(v_node, world_point):
			return {"kind": "modify", "target_card_id": v_node.deck_card_id}
	return {"kind": "reposition"}


## drag_pos/world_point plumbing note: a dragged loose card's position is
## CardWorld-local (it comes straight from _world.get_local_mouse_position(),
## and _world sits at CardWorld's own local origin with no transform of its
## own). node.get_global_transform() is true viewport-space though -
## CardWorld itself is offset within Main's layout (PANEL_W), so comparing a
## local point directly against a node's inverse global transform is off by
## that whole offset. Routing through CardWorld's own global transform first
## (done once by the caller, not per-node) puts both sides in the same
## space, same technique _rebuild_modify_links() uses for its endpoints.
func _node_hit(node: CardNode, world_point: Vector2) -> bool:
	var local: Vector2 = node.get_global_transform().affine_inverse() * world_point
	return Rect2(Vector2.ZERO, CardNode.CARD_SIZE).has_point(local)


## Shared by both the loose-card drag and the edge drag — resolves to at most
## one highlighted node (a modify target amber, or a place target green) and
## swaps it in/out as the hover changes, restoring an empty layer's node back
## to invisible when the green hint leaves it (see CardNode.drop_hint's doc).
func _set_drag_hover(node: CardNode, kind: String) -> void:
	if node == _drag_hover_node and kind == _drag_hover_kind:
		return
	_clear_drag_hover()
	_drag_hover_node = node
	_drag_hover_kind = kind
	if node == null:
		return
	if kind == "modify":
		node.set_highlighted(true)
	elif kind == "place":
		node.drop_hint = true
		node.visible = true
		node.queue_redraw()


func _clear_drag_hover() -> void:
	if _drag_hover_node == null:
		return
	if _drag_hover_kind == "modify":
		_drag_hover_node.set_highlighted(false)
	elif _drag_hover_kind == "place":
		_drag_hover_node.drop_hint = false
		_drag_hover_node.visible = false
		_drag_hover_node.queue_redraw()
	_drag_hover_node = null
	_drag_hover_kind = ""


func _update_loose_drag_highlight(dragged_node: CardNode) -> void:
	var resolution: Dictionary = _resolve_loose_drop(dragged_node.position)
	match resolution.get("kind", ""):
		"modify":
			_set_drag_hover(_find_card_node(resolution.get("target_card_id", "")), "modify")
		"place":
			var visual: SlotVisual = _slot_visuals.get(resolution.get("slot_id", ""))
			var node: CardNode = visual.get_layer_node(resolution.get("layer", "")) if visual != null else null
			_set_drag_hover(node, "place")
		_:
			_set_drag_hover(null, "")


# ── Edge dragging (Reading-Model.md's path 1, "Modify Card") ────────────────
# Started from ControllerPanel/Main's right-click menu, not a canvas press —
# there's nothing to grab yet, so this can't use the press-then-track pattern
# the drags above do. Instead the pending edge just tracks the live mouse
# position from the moment it starts (drawn in _draw() below) until the next
# click resolves it against whatever's highlighted, or a right-click/Escape
# cancels it outright.

func begin_edge_drag(source_id: String) -> void:
	if not _loose_nodes.has(source_id):
		return
	_edge_drag_source_id = source_id
	set_process_input(true)
	queue_redraw()


func _input_edge_drag(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_edge_drag_hover()
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_end_edge_drag()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_edge_drag()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_edge_drag()
		get_viewport().set_input_as_handled()


func _update_edge_drag_hover() -> void:
	var world_point: Vector2 = get_global_mouse_position()
	var node: CardNode = _hit_test_any_card(world_point, _edge_drag_source_id)
	_set_drag_hover(node, "modify" if node != null else "")


## Every loose card except the source itself, and every occupied slotted
## layer — a modify target can be "any other card already on the table" per
## Reading-Model.md, not just loose ones. Excludes anything already
## modifying the source (no two-cycles), same rule _modify_targets() used to
## enforce for the old text-list picker this replaces.
func _hit_test_any_card(world_point: Vector2, exclude_id: String) -> CardNode:
	for card_id in _loose_nodes.keys():
		if card_id == exclude_id:
			continue
		if _last_loose.get(card_id, {}).get("modifies_target", "") == exclude_id:
			continue
		var node: CardNode = _loose_nodes[card_id]
		if _node_hit(node, world_point):
			return node
	for visual in _slot_visuals.values():
		for layer in ["horizontal", "vertical"]:
			var node: CardNode = visual.get_layer_node(layer)
			if node != null and node.visible and _node_hit(node, world_point):
				return node
	return null


func _end_edge_drag() -> void:
	var source_id: String = _edge_drag_source_id
	var target_node: CardNode = _drag_hover_node if _drag_hover_kind == "modify" else null
	var target_id: String = target_node.deck_card_id if target_node != null else ""
	_reset_edge_drag_state()
	loose_edge_resolved.emit(source_id, target_id)


func _cancel_edge_drag() -> void:
	var source_id: String = _edge_drag_source_id
	_reset_edge_drag_state()
	loose_edge_resolved.emit(source_id, "")


func _reset_edge_drag_state() -> void:
	_edge_drag_source_id = ""
	set_process_input(false)
	_clear_drag_hover()
	queue_redraw()


# ── The deck marker (Nodes/DeckVisual.gd) ────────────────────────────────────

func _on_deck_drag_started() -> void:
	_dragging_deck = true
	_deck_visual.get_parent().move_child(_deck_visual, _deck_visual.get_parent().get_child_count() - 1)
	_deck_drag_grab_offset = _deck_visual.position - _world.get_local_mouse_position()
	set_process_input(true)


func _input_deck_drag(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_deck_visual.position = _world.get_local_mouse_position() + _deck_drag_grab_offset
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging_deck = false
		set_process_input(false)
		get_viewport().set_input_as_handled()


func _on_deck_draw_started() -> void:
	deck_draw_requested.emit()


## Programmatic start of a loose-card drag for the deck's draw gesture — same
## end state as _on_loose_drag_pressed() (an actual press on the card
## itself), but grabbed at the card's center under the current mouse
## position, since there was no click on this specific node to compute a
## grab offset from. _loose_dragging starts true, skipping the usual
## distance threshold — the deck's own hover/hold already disambiguated this
## as a real drag, there's no "was this just a tap" question left to ask.
func begin_loose_drag(card_id: String) -> void:
	var node: CardNode = _loose_nodes.get(card_id)
	if node == null:
		return
	var cur: Vector2 = _world.get_local_mouse_position()
	node.position = cur - CardNode.CARD_SIZE / 2.0
	node.get_parent().move_child(node, node.get_parent().get_child_count() - 1)
	_drag_loose_id = card_id
	_loose_dragging = true
	_loose_press_start_local = cur
	_loose_drag_grab_offset = node.position - cur
	set_process_input(true)


## cards: {slot_id: {"vertical": {deck_card_id, name, face_up, orientation}|null,
##                    "horizontal": {...}|null}}
## acl: {} to show everything with no interaction (controller's own view of
## its authoritative state), or
## {slot_id: {"vertical": {"visible": bool, "actions": [...]}, "horizontal": {...}}}
## to both filter and mark which layers are currently tappable — layers are
## controlled independently, per Meta/Reading-Model.md.
func apply_state(cards: Dictionary, acl: Dictionary = {}) -> void:
	for slot_id in _slot_visuals.keys():
		var visual: SlotVisual = _slot_visuals[slot_id]
		var slot_info: Dictionary = cards.get(slot_id, {})
		var slot_acl: Dictionary = acl.get(slot_id, {})
		for layer in LAYERS:
			var info = slot_info.get(layer)
			var layer_acl: Dictionary = slot_acl.get(layer, {})
			var visible_to_viewer: bool = acl.is_empty() or layer_acl.get("visible", false)
			if info == null or not visible_to_viewer:
				visual.set_layer(layer, null, false)
				continue
			var can_act: Array = layer_acl.get("actions", [])
			var interactive: bool = acl.is_empty() or can_act.size() > 0
			visual.set_layer(layer, info, interactive)


## loose: {deck_card_id: {"name","face_up","orientation","x","y",
## "modifies_target": deck_card_id|""}}. Untethered cards dealt via Deal
## Loose — controller-only for now (no client ACL modeled yet, see
## grant-api's _filter_state_for_client, which drops "loose" from what a
## client ever receives). Always interactive: no ACL to gate against.
func set_loose(loose: Dictionary) -> void:
	var seen: Dictionary = {}
	for card_id in loose.keys():
		var info: Dictionary = loose[card_id]
		seen[card_id] = true
		var node: CardNode = _loose_nodes.get(card_id)
		if node == null:
			node = CardNode.new()
			node.slot_id = card_id  # sentinel: loose id travels in slot_id, layer == "loose"
			node.layer = "loose"
			# No tapped connection here — a loose CardNode only ever emits
			# drag_pressed (see CardNode._gui_input), never tapped directly;
			# _end_loose_drag() re-emits card_tapped itself for a non-drag click.
			node.context_requested.connect(_on_card_context_requested)
			node.drag_pressed.connect(_on_loose_drag_pressed)
			_world.add_child(node)
			_loose_nodes[card_id] = node
		node.deck_card_id = card_id
		node.card_name = info.get("name", "")
		if card_id != _drag_loose_id:  # don't fight the position of whatever's actively being dragged
			node.position = Vector2(info.get("x", 0.0), info.get("y", 0.0))
		node.set_face_up(info.get("face_up", false))
		node.set_orientation(info.get("orientation", "upright"))
		node.set_image(info.get("image", ""))
		node.set_interactive(true)

	for card_id in _loose_nodes.keys().duplicate():
		if not seen.has(card_id):
			_loose_nodes[card_id].queue_free()
			_loose_nodes.erase(card_id)

	_last_loose = loose
	_rebuild_modify_links(loose)
	queue_redraw()


## Any card, slotted or loose, keyed by deck_card_id — the modifier
## mechanic's target isn't restricted to loose cards (Reading-Model.md:
## "modify any other card already on the table"). A slotted card's CardNode
## is now a grandchild (via its SlotVisual), so this delegates to each
## visual's own lookup rather than scanning a flat dict directly.
func _find_card_node(deck_card_id: String) -> CardNode:
	if _loose_nodes.has(deck_card_id):
		return _loose_nodes[deck_card_id]
	for visual in _slot_visuals.values():
		var node: CardNode = visual.get_card_node_for(deck_card_id)
		if node != null:
			return node
	return null


## Connecting-line endpoints for _draw(), recomputed from current node
## positions each time loose state changes. Not re-derived when a slotted
## target card is later repositioned by unrelated churn — acceptable
## first-pass staleness, not a correctness issue (the link itself is still
## correct at checkpoint time, only the drawn line could lag briefly).
##
## Uses each node's own get_layer_transform() rather than plain
## get_global_transform() — a slotted card is now a grandchild (CardWorld ->
## _world -> SlotVisual -> CardNode), so its `.position` alone is relative to
## its SlotVisual, not to `_world`; get_layer_transform() still composes
## correctly regardless of nesting depth, same as get_global_transform()
## would, but additionally drops the 180° `orientation == "reversed"` flip —
## these anchors are about the physical edge of where a card structurally
## sits in its slot, not which way up it happens to be drawn.
##
## Endpoints are the modifying card's own physical bottom edge and the
## modified card's own physical top edge (or, for a Horizontal target, the
## physical LEFT edge — a Horizontal is a Vertical rotated 90° to cross it,
## so its structural "near" edge is what the 90° crossing rotation turns
## a plain top-center point into), not each card's center — a line into the
## middle of a slot's crossing pair can't tell you which of the two occupied
## cards it actually targets (they share the same center point), while an
## edge-to-edge line visibly terminates at one specific card.
func _rebuild_modify_links(loose: Dictionary) -> void:
	_modify_links.clear()
	var to_local: Transform2D = get_global_transform().affine_inverse()
	for card_id in loose.keys():
		var target_id: String = loose[card_id].get("modifies_target", "")
		if target_id == "":
			continue
		var from_node: CardNode = _loose_nodes.get(card_id)
		var to_node: CardNode = _find_card_node(target_id)
		if from_node == null or to_node == null:
			continue
		_modify_links.append([
			to_local * (from_node.get_layer_transform() * _link_anchor_point(from_node, false)),
			to_local * (to_node.get_layer_transform() * _link_anchor_point(to_node, true)),
		])


## Pre-rotation (local, unrotated-card-space) point that get_layer_transform()
## then carries to the correct physical edge. A loose modifying card is
## always effectively layer_angle 0 (loose cards never crossing-rotate), so
## its own attach point is simply its physical bottom, pre-rotation
## bottom-center. A Vertical/loose target's physical top is trivially its own
## pre-rotation top-center (no rotation involved). A Horizontal target's
## physical LEFT is, per the 90°-clockwise crossing rotation's actual effect
## (verified directly: local top-center rotates to the physical right, local
## bottom-center to the physical left), pre-rotation bottom-center — the same
## point as the attach side, just for a different reason.
func _link_anchor_point(node: CardNode, is_target: bool) -> Vector2:
	var top_center := Vector2(CardNode.CARD_SIZE.x / 2.0, 0.0)
	var bottom_center := Vector2(CardNode.CARD_SIZE.x / 2.0, CardNode.CARD_SIZE.y)
	if is_target and node.layer != "horizontal":
		return top_center
	return bottom_center


func _draw() -> void:
	for link in _modify_links:
		draw_line(link[0], link[1], Color(0.7, 0.55, 0.85, 0.8), 2.0)
	if _edge_drag_source_id != "":
		var source_node: CardNode = _loose_nodes.get(_edge_drag_source_id)
		if source_node != null:
			var to_local: Transform2D = get_global_transform().affine_inverse()
			var from_pt: Vector2 = to_local * (source_node.get_layer_transform() * _link_anchor_point(source_node, false))
			var to_pt: Vector2 = to_local * get_global_mouse_position()
			draw_line(from_pt, to_pt, Color(0.7, 0.55, 0.85, 0.5), 2.0, true)


func _on_card_tapped(slot_id: String, layer: String) -> void:
	card_tapped.emit(slot_id, layer)


func _on_card_context_requested(slot_id: String, layer: String) -> void:
	card_context_requested.emit(slot_id, layer)


func actions_for(slot_id: String, layer: String, acl: Dictionary) -> Array:
	return acl.get(slot_id, {}).get(layer, {}).get("actions", [])
