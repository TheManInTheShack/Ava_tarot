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

const LAYERS := ["vertical", "horizontal"]
const DRAG_THRESHOLD := 6.0

var _slot_geometry: Dictionary = {}  # slot_id -> {"name", "x", "y"} — set via set_slots()
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


func _ready() -> void:
	_world = Control.new()
	_world.name = "World"
	_world.set_anchors_preset(Control.PRESET_FULL_RECT)
	_world.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_world)


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


func _input(event: InputEvent) -> void:
	if _drag_slot_id == "":
		return
	if event is InputEventMouseMotion:
		var cur: Vector2 = _world.get_local_mouse_position()
		if not _dragging and cur.distance_to(_press_start_local) > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			var marker: Control = _slot_markers.get(_drag_slot_id)
			if marker != null:
				marker.position = cur + _drag_grab_offset
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
			node.tapped.connect(_on_card_tapped)
			node.context_requested.connect(_on_card_context_requested)
			_world.add_child(node)
			_loose_nodes[card_id] = node
		node.deck_card_id = card_id
		node.card_name = info.get("name", "")
		node.position = Vector2(info.get("x", 0.0), info.get("y", 0.0))
		node.set_face_up(info.get("face_up", false))
		node.set_orientation(info.get("orientation", "upright"))
		node.set_image(info.get("image", ""))
		node.set_interactive(true)

	for card_id in _loose_nodes.keys().duplicate():
		if not seen.has(card_id):
			_loose_nodes[card_id].queue_free()
			_loose_nodes.erase(card_id)

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
## Uses each node's own get_global_transform() rather than
## `_world.get_transform() * node.position` — a slotted card is now a
## grandchild (CardWorld -> _world -> SlotVisual -> CardNode), so its
## `.position` alone is relative to its SlotVisual, not to `_world`. Global
## transforms compose correctly regardless of nesting depth; a loose card
## (still a direct `_world` child) works the same way through this too.
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
		var center := CardNode.CARD_SIZE / 2.0
		_modify_links.append([
			to_local * (from_node.get_global_transform() * center),
			to_local * (to_node.get_global_transform() * center),
		])


func _draw() -> void:
	for link in _modify_links:
		draw_line(link[0], link[1], Color(0.7, 0.55, 0.85, 0.8), 2.0)


func _on_card_tapped(slot_id: String, layer: String) -> void:
	card_tapped.emit(slot_id, layer)


func _on_card_context_requested(slot_id: String, layer: String) -> void:
	card_context_requested.emit(slot_id, layer)


func actions_for(slot_id: String, layer: String, acl: Dictionary) -> Array:
	return acl.get(slot_id, {}).get(layer, {}).get("actions", [])
