class_name DeckVisual
extends Control

## Visual stand-in for "the deck" — always present on the table (not tied to
## _state the way dealt cards are; CardWorld owns exactly one of these).
## Starts in the upper-right with a small margin, draggable to reposition.
##
## Gesture design (agreed 2026-08-16, matches genre convention): hovering
## with no button down, or pressing and holding still, both "prime" it after
## HOLD_SECONDS — a highlight plus a gentle top-card lift, the "about to
## draw" cue. From primed, ANY further motion or a release peels a card off
## and hands control to CardWorld's existing loose-card drag machinery,
## already following the cursor — one continuous press-hold-move-release
## motion, no separate confirm click. Pressing and moving BEFORE priming
## instead just repositions this marker (the same press-then-track
## distance-threshold technique CardWorld already uses for slot markers),
## resolved entirely locally since neither pre-priming state ever needs the
## mouse to leave this control's own small bounds — only once real dragging
## starts does CardWorld's global _input() need to take over.

signal drag_started()  # press + moved before priming -> CardWorld repositions this marker
signal draw_started()  # primed, then moved or released -> CardWorld peels a loose card off

const DECK_SIZE := Vector2(80.0, 140.0)  # half CardNode.CARD_SIZE, per the ask
const DEFAULT_POSITION := Vector2(1480.0, 40.0)  # upper-right, ~40px margin (CardWorld is ~1600x1080 after PANEL_W)
const HOLD_SECONDS := 1.0
const DRAG_THRESHOLD := 6.0  # matches CardWorld's own, so the two gestures feel identical
const PEEK_STEP := Vector2(3.0, -3.0)  # how far each "card" behind the top one peeks out

var _pressed: bool = false
var _press_start: Vector2 = Vector2.ZERO
var _primed: bool = false
var _hold_timer: Timer
var _lift_tween: Tween
var _top_lift: float = 0.0:
	set(value):
		_top_lift = value
		queue_redraw()


func _ready() -> void:
	position = DEFAULT_POSITION
	custom_minimum_size = DECK_SIZE
	size = DECK_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_hold_timer = Timer.new()
	_hold_timer.one_shot = true
	_hold_timer.wait_time = HOLD_SECONDS
	_hold_timer.timeout.connect(func() -> void: _set_primed(true))
	add_child(_hold_timer)


func _on_mouse_entered() -> void:
	if not _primed:
		_hold_timer.start()


func _on_mouse_exited() -> void:
	if not _pressed:
		_hold_timer.stop()
		_set_primed(false)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_press_start = get_local_mouse_position()
			if _primed:
				_trigger_draw()
			else:
				_hold_timer.start()
		elif _pressed:
			_pressed = false
			if _primed:
				_trigger_draw()
	elif event is InputEventMouseMotion and _pressed and not _primed:
		if get_local_mouse_position().distance_to(_press_start) > DRAG_THRESHOLD:
			_pressed = false
			_hold_timer.stop()
			drag_started.emit()


func _trigger_draw() -> void:
	_pressed = false
	_set_primed(false)
	draw_started.emit()


func _set_primed(value: bool) -> void:
	if _primed == value:
		return
	_primed = value
	queue_redraw()
	if value:
		_play_lift_animation()
	else:
		_stop_lift_animation()


## Gentle up-and-back loop, not a one-shot — it should read as "this card is
## restless, waiting to be pulled" for as long as priming holds, not just
## flash once. Stopped (and _top_lift snapped back to 0) the instant priming
## ends, whether that's from drawing, releasing early, or the mouse leaving.
func _play_lift_animation() -> void:
	if _lift_tween != null and _lift_tween.is_valid():
		_lift_tween.kill()
	_lift_tween = create_tween()
	_lift_tween.set_loops()
	_lift_tween.tween_property(self, "_top_lift", -8.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_lift_tween.tween_property(self, "_top_lift", 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_lift_animation() -> void:
	if _lift_tween != null and _lift_tween.is_valid():
		_lift_tween.kill()
	_lift_tween = null
	_top_lift = 0.0


## Peeking "cards" are just offset rects sharing the top card's own back
## styling, not separate art — enough to read as "there's a stack here"
## without needing new assets.
func _draw() -> void:
	for i in [2, 1]:
		_draw_card_back(Rect2(PEEK_STEP * i, DECK_SIZE))
	var top_rect := Rect2(Vector2(0.0, _top_lift), DECK_SIZE)
	_draw_card_back(top_rect)
	if _primed:
		draw_rect(top_rect, Color(0.85, 0.65, 0.15), false, 3.0)


func _draw_card_back(rect: Rect2) -> void:
	if CardNode.back_texture != null:
		draw_texture_rect(CardNode.back_texture, rect, false)
	else:
		draw_rect(rect, Color(0.15, 0.1, 0.25), true)
	draw_rect(rect, Color(0.3, 0.3, 0.3), false, 1.5)
