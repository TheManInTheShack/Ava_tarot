extends Camera2D

const ZOOM_MIN  := Vector2(0.25, 0.25)
const ZOOM_MAX  := Vector2(2.5, 2.5)
const ZOOM_STEP := 0.1

var _pan_active:       bool    = false
var _pan_start_screen: Vector2 = Vector2.ZERO
var _pan_start_cam:    Vector2 = Vector2.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom = (zoom + Vector2(ZOOM_STEP, ZOOM_STEP)).clamp(ZOOM_MIN, ZOOM_MAX)
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom = (zoom - Vector2(ZOOM_STEP, ZOOM_STEP)).clamp(ZOOM_MIN, ZOOM_MAX)
			MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				_pan_active       = event.pressed
				_pan_start_screen = event.position
				_pan_start_cam    = global_position
	elif event is InputEventMouseMotion and _pan_active:
		var delta: Vector2 = (event.position - _pan_start_screen) / zoom.x
		global_position = _pan_start_cam - delta

func _input(event: InputEvent) -> void:
	if event is InputEventMagnifyGesture:
		zoom = (zoom * event.factor).clamp(ZOOM_MIN, ZOOM_MAX)
	elif event is InputEventPanGesture:
		global_position -= event.delta / zoom.x
