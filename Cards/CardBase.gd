extends Node2D
class_name CardBase

signal card_clicked(card: CardBase)
signal card_dropped(card: CardBase, drop_position: Vector2)
signal card_flipped(card: CardBase, is_face_up: bool)

@export var card_id:      String    = ""
@export var card_name:    String    = ""
@export var face_texture: Texture2D
@export var back_texture: Texture2D
@export var is_face_up:   bool      = false
@export var is_reversed:  bool      = false

const FLIP_HALF_DURATION  := 0.18
const DRAG_Z_INDEX        := 100
const DRAG_THRESHOLD      := 12.0
const CARD_WIDTH          := 140
const CARD_HEIGHT         := 240

var slot_rotation_degrees: float = 0.0

var _input_down:      bool    = false
var _dragging:        bool    = false
var _drag_offset:     Vector2 = Vector2.ZERO
var _press_start_pos: Vector2 = Vector2.ZERO

@onready var card_back:           Sprite2D  = $CardBack
@onready var card_front:          Sprite2D  = $CardFront
@onready var card_name_label:     Label     = $CardNameLabel
@onready var selection_highlight: Polygon2D = $SelectionHighlight
@onready var drop_shadow:         Sprite2D  = $DropShadow
@onready var collision_area:      Area2D    = $CollisionArea

func _ready() -> void:
	_setup_visuals()
	collision_area.input_event.connect(_on_collision_area_input_event)

func _setup_visuals() -> void:
	if not back_texture:
		back_texture = _make_color_texture(Color(0.15, 0.08, 0.35))
	if not face_texture:
		var h := float(abs(card_id.hash()) % 360) / 360.0
		face_texture = _make_color_texture(Color.from_hsv(h, 0.45, 0.75))
	card_back.texture  = back_texture
	card_front.texture = face_texture
	drop_shadow.texture = back_texture
	card_back.visible  = not is_face_up
	card_front.visible = is_face_up
	card_name_label.text    = card_name if card_name else card_id
	card_name_label.visible = is_face_up
	rotation_degrees = slot_rotation_degrees + (180.0 if (is_face_up and is_reversed) else 0.0)

func _make_color_texture(color: Color) -> ImageTexture:
	var img := Image.create(CARD_WIDTH, CARD_HEIGHT, false, Image.FORMAT_RGB8)
	img.fill(color)
	return ImageTexture.create_from_image(img)

func flip() -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "scale:y", 0.0, FLIP_HALF_DURATION)
	tween.tween_callback(_swap_face)
	tween.tween_property(self, "scale:y", 1.0, FLIP_HALF_DURATION)

func _swap_face() -> void:
	is_face_up = !is_face_up
	card_front.visible      = is_face_up
	card_back.visible       = !is_face_up
	card_name_label.visible = is_face_up
	rotation_degrees = slot_rotation_degrees + (180.0 if (is_face_up and is_reversed) else 0.0)
	emit_signal("card_flipped", self, is_face_up)

func set_highlighted(value: bool) -> void:
	selection_highlight.visible = value

func _on_collision_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		_input_down      = true
		_dragging        = false
		_press_start_pos = get_global_mouse_position()
		_drag_offset     = global_position - _press_start_pos
	else:
		if _dragging:
			z_index = 0
			drop_shadow.modulate.a = 0.25
			emit_signal("card_dropped", self, global_position)
		else:
			emit_signal("card_clicked", self)
		_input_down = false
		_dragging   = false

func _process(_delta: float) -> void:
	if not _input_down:
		return
	var current_pos := get_global_mouse_position()
	if not _dragging:
		if current_pos.distance_to(_press_start_pos) > DRAG_THRESHOLD:
			_dragging = true
			z_index   = DRAG_Z_INDEX
			drop_shadow.modulate.a = 0.6
	if _dragging:
		global_position = current_pos + _drag_offset
