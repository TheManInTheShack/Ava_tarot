extends Node2D
class_name CardBase

signal card_clicked(card: CardBase)
signal card_drag_started(card: CardBase)
signal card_dropped(card: CardBase, drop_position: Vector2)
signal card_flipped(card: CardBase, is_face_up: bool)
signal card_orientation_changed(card: CardBase)

@export var card_id:      String    = ""
@export var card_name:    String    = ""
@export var face_texture: Texture2D
@export var back_texture: Texture2D
@export var is_face_up:   bool      = false
@export var is_reversed:  bool      = false

const FLIP_HALF_DURATION  := 0.18
const DRAG_Z_INDEX        := 100
const DRAG_THRESHOLD      := 12.0
const LONG_PRESS_DURATION := 0.55
const CARD_WIDTH          := 140
const CARD_HEIGHT         := 240
const LABEL_GAP           := 10
const LABEL_FONT_SIZE     := 18

var _label_font: Font = null

var slot_rotation_degrees: float = 0.0
var base_z_index: int = 0
var in_slot: bool = false

var _input_down:           bool    = false
var _dragging:             bool    = false
var _drag_offset:          Vector2 = Vector2.ZERO
var _press_start_pos:      Vector2 = Vector2.ZERO
var _press_time:           float   = 0.0
var _long_press_triggered: bool    = false

@onready var card_back:           Sprite2D  = $CardBack
@onready var card_front:          Sprite2D  = $CardFront
@onready var selection_highlight: Polygon2D = $SelectionHighlight
@onready var drop_shadow:         Sprite2D  = $DropShadow
@onready var collision_area:      Area2D    = $CollisionArea

func _ready() -> void:
	_label_font = ThemeDB.fallback_font
	_setup_visuals()
	collision_area.input_event.connect(_on_collision_area_input_event)

const DEFAULT_BACK := "res://Assets/Images/card_back_default.png"

func _setup_visuals() -> void:
	if not back_texture:
		var tex := load(DEFAULT_BACK) as Texture2D
		back_texture = tex if tex else _make_color_texture(Color(0.15, 0.08, 0.35))
	if not face_texture:
		var h := float(abs(card_id.hash()) % 360) / 360.0
		face_texture = _make_color_texture(Color.from_hsv(h, 0.45, 0.75))
	card_back.texture  = back_texture
	card_front.texture = face_texture
	drop_shadow.texture = back_texture
	_fit_sprite(card_back, back_texture)
	_fit_sprite(card_front, face_texture)
	_fit_sprite(drop_shadow, back_texture)
	card_back.visible  = not is_face_up
	card_front.visible = is_face_up
	rotation_degrees = slot_rotation_degrees + (180.0 if (is_face_up and is_reversed) else 0.0)
	queue_redraw()

func _fit_sprite(sprite: Sprite2D, tex: Texture2D) -> void:
	if tex:
		sprite.scale = Vector2(float(CARD_WIDTH) / tex.get_width(), float(CARD_HEIGHT) / tex.get_height())

func _make_color_texture(color: Color) -> ImageTexture:
	var img := Image.create(CARD_WIDTH, CARD_HEIGHT, false, Image.FORMAT_RGB8)
	img.fill(color)
	return ImageTexture.create_from_image(img)

func flip() -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "scale:x", 0.0, FLIP_HALF_DURATION)
	tween.tween_callback(_swap_face)
	tween.tween_property(self, "scale:x", 1.0, FLIP_HALF_DURATION)

func _swap_face() -> void:
	is_face_up = !is_face_up
	card_front.visible = is_face_up
	card_back.visible  = !is_face_up
	rotation_degrees = slot_rotation_degrees + (180.0 if (is_face_up and is_reversed) else 0.0)
	queue_redraw()
	emit_signal("card_flipped", self, is_face_up)

func _higher_card_at_mouse() -> bool:
	var mouse_pos := get_global_mouse_position()
	for area in collision_area.get_overlapping_areas():
		var other := area.get_parent()
		if not (other is CardBase and other.z_index > z_index):
			continue
		var local: Vector2 = other.to_local(mouse_pos)
		if abs(local.x) <= CARD_WIDTH * 0.5 and abs(local.y) <= CARD_HEIGHT * 0.5:
			return true
	return false

func set_highlighted(value: bool) -> void:
	selection_highlight.visible = value

func _on_collision_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _higher_card_at_mouse():
		if event.pressed and not event.double_click:
			get_viewport().set_input_as_handled()
			emit_signal("card_clicked", self)
		return
	get_viewport().set_input_as_handled()
	if event.pressed and event.double_click and not is_face_up:
		flip()
		return
	if event.pressed:
		_input_down           = true
		_dragging             = false
		_press_time           = 0.0
		_long_press_triggered = false
		_press_start_pos      = get_global_mouse_position()
		_drag_offset          = global_position - _press_start_pos
	else:
		if _dragging:
			z_index = base_z_index
			drop_shadow.modulate.a = 0.25
			emit_signal("card_dropped", self, global_position)
		elif not _long_press_triggered:
			emit_signal("card_clicked", self)
		_input_down           = false
		_dragging             = false
		_press_time           = 0.0
		_long_press_triggered = false

func notify_orientation_changed() -> void:
	emit_signal("card_orientation_changed", self)

func _draw() -> void:
	if not is_face_up or not _label_font or in_slot:
		return
	var text := card_name if card_name else card_id
	var anchor_local := Vector2(0.0, CARD_HEIGHT * 0.5 + LABEL_GAP)
	var anchor_screen := anchor_local.rotated(rotation)
	draw_set_transform(anchor_screen, -rotation, Vector2.ONE)
	var text_size: Vector2 = _label_font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, LABEL_FONT_SIZE)
	var pos := Vector2(-text_size.x * 0.5, _label_font.get_ascent(LABEL_FONT_SIZE))
	draw_string(_label_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, LABEL_FONT_SIZE, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _process(delta: float) -> void:
	if not _input_down:
		return
	var current_pos := get_global_mouse_position()
	if not _dragging:
		if current_pos.distance_to(_press_start_pos) > DRAG_THRESHOLD:
			_dragging             = true
			_long_press_triggered = false
			_press_time           = 0.0
			in_slot               = false
			z_index               = DRAG_Z_INDEX
			drop_shadow.modulate.a = 0.6
			emit_signal("card_drag_started", self)
		else:
			_press_time += delta
			var threshold := LONG_PRESS_DURATION * (2.0 if is_face_up else 1.0)
			if _press_time >= threshold and not _long_press_triggered:
				_long_press_triggered = true
				flip()
	if _dragging:
		global_position = current_pos + _drag_offset
