class_name PanZoomCanvas
extends Control

## A pannable/zoomable canvas — the interactive plane content sits on, with
## a docked control strip along the top (zoom slider + Fit button). Named
## for the pattern generically, not "Board" — this same file is meant to
## become Paradotz's own canvas eventually too (a knowledge-graph canvas,
## not a card table), so the class name stays domain-neutral even though a
## subclass like Paratarot's `CardWorld` can keep calling it "the table" in
## its own prose.
##
## Owns `_world` (children of this are what gets panned/zoomed — add
## anything meant to live on the canvas there, never directly to `self`),
## `top_bar_hbox` (append more buttons into the same row a host app wants
## alongside the zoom controls — same idea as Paradotz's own TopBar
## `LeftGroup`, built-in controls first, more appended later from code),
## and all the pan/zoom/fit mechanics themselves. A subclass gets all of
## this for free via `extends PanZoomCanvas` + calling `super._ready()`
## first — see `CardWorld.gd`.
##
## Mechanics ported from Paradotz's own `Editor.gd` (`_zoom_at()`/
## `_apply_world_transform()`/`canvas_to_world()`), same math, fixed zoom
## range here rather than Paradotz's dynamic content-based floor (the
## explicit Fit button is what actually answers "see everything" in this
## version). Fit-to-content itself is genuinely new UI — Paradotz has the
## underlying computation (`_fit_all_nodes_to_canvas()`) but never actually
## exposes it as a button or shortcut anywhere.

const MIN_ZOOM := 0.1
const MAX_ZOOM := 5.0
const ZOOM_WHEEL_FACTOR := 1.1
const TOP_BAR_HEIGHT := 40.0
const PAN_DRAG_THRESHOLD := 6.0
const FIT_MARGIN := 60.0

var _world: Control
var top_bar_hbox: HBoxContainer

var _canvas_area: Control
var _top_bar: PanelContainer
var _zoom_label: Label
var _zoom_slider: HSlider

var _pan: Vector2 = Vector2.ZERO
var _zoom: float = 1.0
var _pan_pending: bool = false
var _panning: bool = false
var _pan_press_start: Vector2 = Vector2.ZERO  # _canvas_area-local (zoom-independent), captured at press
var _pan_start_value: Vector2 = Vector2.ZERO  # _pan at press time


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	_top_bar = PanelContainer.new()
	_top_bar.anchor_left = 0.0
	_top_bar.anchor_right = 1.0
	_top_bar.anchor_top = 0.0
	_top_bar.anchor_bottom = 0.0
	_top_bar.offset_bottom = TOP_BAR_HEIGHT
	add_child(_top_bar)

	top_bar_hbox = HBoxContainer.new()
	_top_bar.add_child(top_bar_hbox)

	_zoom_label = Label.new()
	_zoom_label.custom_minimum_size = Vector2(42.0, 0.0)
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_zoom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_bar_hbox.add_child(_zoom_label)

	_zoom_slider = HSlider.new()
	_zoom_slider.min_value = MIN_ZOOM * 100.0
	_zoom_slider.max_value = MAX_ZOOM * 100.0
	_zoom_slider.step = 5.0
	_zoom_slider.custom_minimum_size = Vector2(120.0, 0.0)
	_zoom_slider.value_changed.connect(_on_zoom_slider_changed)
	top_bar_hbox.add_child(_zoom_slider)

	var fit_btn := Button.new()
	fit_btn.text = "Fit"
	fit_btn.pressed.connect(fit_to_content)
	top_bar_hbox.add_child(fit_btn)

	_canvas_area = Control.new()
	_canvas_area.name = "CanvasArea"
	_canvas_area.clip_contents = true
	_canvas_area.anchor_left = 0.0
	_canvas_area.anchor_right = 1.0
	_canvas_area.anchor_top = 0.0
	_canvas_area.anchor_bottom = 1.0
	_canvas_area.offset_top = TOP_BAR_HEIGHT
	_canvas_area.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas_area.gui_input.connect(_on_canvas_gui_input)
	add_child(_canvas_area)

	_world = Control.new()
	_world.name = "World"
	_world.set_anchors_preset(Control.PRESET_FULL_RECT)
	_world.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas_area.add_child(_world)

	_apply_world_transform()


## Empty-background clicks only, by construction — anything already
## consumed by a card/slot/concept-node's own gui_input never reaches
## here, so pan and node-drag are naturally mutually exclusive through
## ordinary Godot event propagation, no manual coordination needed.
func _on_canvas_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pan_pending = true
				_panning = false
				_pan_press_start = _canvas_area.get_local_mouse_position()
				_pan_start_value = _pan
				set_process_input(true)
			else:
				_pan_pending = false
				_panning = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(_canvas_area.get_local_mouse_position(), ZOOM_WHEEL_FACTOR)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(_canvas_area.get_local_mouse_position(), 1.0 / ZOOM_WHEEL_FACTOR)


## Same press-then-track technique every drag in this repo already uses —
## gui_input alone stops firing the instant the cursor leaves the pressed
## control's own bounds mid-drag. Tracks via _canvas_area's own local mouse
## position (zoom-independent — only `_world`, its child, actually scales)
## rather than trusting InputEvent.position across the gui_input/_input()
## boundary, same reasoning CardWorld's own existing drags already use.
func _input(event: InputEvent) -> void:
	if not (_pan_pending or _panning):
		return
	if event is InputEventMouseMotion:
		var cur: Vector2 = _canvas_area.get_local_mouse_position()
		if not _panning and cur.distance_to(_pan_press_start) > PAN_DRAG_THRESHOLD:
			_panning = true
		if _panning:
			_pan = _pan_start_value + (cur - _pan_press_start)
			_apply_world_transform()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_pan_pending = false
		_panning = false
		set_process_input(false)
		get_viewport().set_input_as_handled()


func _on_zoom_slider_changed(value: float) -> void:
	var new_zoom: float = value / 100.0
	if is_equal_approx(new_zoom, _zoom):
		return
	_zoom_at(_canvas_area.size / 2.0, new_zoom / _zoom)


func canvas_to_world(p: Vector2) -> Vector2:
	return (p - _pan) / _zoom


func _zoom_at(canvas_pos: Vector2, factor: float) -> void:
	var world_pos: Vector2 = canvas_to_world(canvas_pos)
	_zoom = clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	_pan = canvas_pos - world_pos * _zoom
	_apply_world_transform()


func _apply_world_transform() -> void:
	_world.position = _pan
	_world.scale = Vector2(_zoom, _zoom)
	_zoom_label.text = "%d%%" % roundi(_zoom * 100.0)
	_zoom_slider.set_value_no_signal(_zoom * 100.0)
	_on_view_changed()


## Override in a subclass that draws anything computed from _world's
## current transform (e.g. connecting lines between two children, cached
## as absolute points rather than recomputed every _draw() call) — called
## every time pan/zoom actually changes, not just when the underlying data
## does. Cards/slots/etc. themselves need no such hook: their own
## rendering just follows the composed transform automatically, same as
## any Control. But a manual draw_line() in a DIFFERENT node's own _draw()
## (CardWorld's, not _world's — the camera moving doesn't by itself
## re-invoke a sibling/ancestor's _draw()) goes stale the instant the
## camera moves unless something explicitly recomputes and redraws it —
## exactly the bug Paradotz hit early on too. Base does nothing on its own.
func _on_view_changed() -> void:
	pass


## Fully generic — unions the bounding rects of `_world`'s direct Control
## children (accounting for each one's own .scale, e.g. a resized
## SlotVisual) and solves zoom/pan to frame that union with margin,
## centered. No card/slot-specific knowledge at all, so this works
## identically whatever `_world`'s children actually are.
func fit_to_content() -> void:
	var rect: Rect2
	var found := false
	for child in _world.get_children():
		if not (child is Control):
			continue
		var c: Control = child
		var child_rect := Rect2(c.position, c.size * c.scale)
		rect = child_rect if not found else rect.merge(child_rect)
		found = true
	if not found:
		return
	rect = rect.grow(FIT_MARGIN)
	var canvas_size: Vector2 = _canvas_area.size
	if rect.size.x <= 0.0 or rect.size.y <= 0.0 or canvas_size.x <= 0.0 or canvas_size.y <= 0.0:
		return
	_zoom = clampf(min(canvas_size.x / rect.size.x, canvas_size.y / rect.size.y), MIN_ZOOM, MAX_ZOOM)
	var world_center: Vector2 = rect.position + rect.size / 2.0
	_pan = canvas_size / 2.0 - world_center * _zoom
	_apply_world_transform()
