extends PanelContainer

@onready var aggregate_label: Label        = $MarginContainer/VBoxContainer/AggregateLabel
@onready var reading_list:    VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ReadingList
@onready var close_button:    Button        = $MarginContainer/VBoxContainer/HeaderRow/CloseButton

func _ready() -> void:
	hide()
	close_button.pressed.connect(hide)

func show_history() -> void:
	_populate()
	show()

# ── data ──────────────────────────────────────────────────────────────────────

func _load_readings() -> Array:
	var path := "user://readings.json"
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return []
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK:
		f.close()
		return []
	f.close()
	return j.data if j.data is Array else []

# ── population ────────────────────────────────────────────────────────────────

func _populate() -> void:
	for child in reading_list.get_children():
		child.queue_free()

	var readings := _load_readings()
	if readings.is_empty():
		aggregate_label.text = "No readings saved yet."
		return

	readings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.get("timestamp", "") > b.get("timestamp", ""))

	aggregate_label.text = _aggregate_text(readings)

	for reading in readings:
		reading_list.add_child(_build_entry(reading))

# ── aggregate header ──────────────────────────────────────────────────────────

func _aggregate_text(readings: Array) -> String:
	var total := readings.size()
	var timestamps: Array[String] = []
	for r in readings:
		timestamps.append(r.get("timestamp", ""))
	timestamps.sort()
	var oldest: String = (timestamps.front() as String).left(10)
	var newest: String = (timestamps.back()  as String).left(10)

	var layout_counts: Dictionary = {}
	var maj_sum := 0.0
	var inv_sum := 0.0
	var court_sum := 0.0
	for r in readings:
		var lid: String = r.get("layout_id", "unknown")
		layout_counts[lid] = layout_counts.get(lid, 0) + 1
		var m: Dictionary = r.get("metrics", {})
		maj_sum   += m.get("major_ratio",     0.0)
		inv_sum   += m.get("inversion_ratio",  0.0)
		court_sum += m.get("court_ratio",      0.0)

	var layout_parts: Array[String] = []
	for lid in layout_counts:
		layout_parts.append("%s: %d" % [_layout_display_name(lid), layout_counts[lid]])

	return "%d readings  ·  %s → %s\n%s\nAvg  Major %.0f%%  ·  Inv %.0f%%  ·  Courts %.0f%%" % [
		total, oldest, newest,
		"  ·  ".join(layout_parts),
		maj_sum   / total * 100.0,
		inv_sum   / total * 100.0,
		court_sum / total * 100.0,
	]

# ── entry builder ─────────────────────────────────────────────────────────────

func _build_entry(reading: Dictionary) -> Control:
	var metrics: Dictionary = reading.get("metrics", {})
	var color := _fingerprint_color(metrics)

	var outer := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color          = Color(color.r, color.g, color.b, 0.18)
	style.border_color      = color
	style.border_width_left = 6
	style.set_corner_radius_all(4)
	outer.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	outer.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	# ── row 1: date / layout name / color swatch
	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)

	var date_lbl := Label.new()
	var ts: String = reading.get("timestamp", "")
	date_lbl.text = "%s  ·  %s" % [ts.left(10), _layout_display_name(reading.get("layout_id", ""))]
	date_lbl.add_theme_font_size_override("font_size", 24)
	date_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(date_lbl)

	var swatch := ColorRect.new()
	swatch.color = color
	swatch.custom_minimum_size = Vector2(36, 36)
	hbox.add_child(swatch)

	# ── row 2: first four card names with reversal arrows
	var placements: Array = reading.get("placements", [])
	var name_parts: Array[String] = []
	for p in placements.slice(0, 4):
		var n: String = p.get("card_name", p.get("card_id", "?"))
		if (p.get("orientation", "") as String).ends_with("_reversed"):
			n += "↓"
		name_parts.append(n)
	if placements.size() > 4:
		name_parts.append("…")

	var cards_lbl := Label.new()
	cards_lbl.text = "  ".join(name_parts)
	cards_lbl.add_theme_font_size_override("font_size", 19)
	cards_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	cards_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(cards_lbl)

	# ── row 3: key metrics
	var metrics_lbl := Label.new()
	metrics_lbl.text = "Major %.0f%%  ·  Inv %.0f%%  ·  Courts %.0f%%  ·  %s" % [
		metrics.get("major_ratio",    0.0) * 100.0,
		metrics.get("inversion_ratio", 0.0) * 100.0,
		metrics.get("court_ratio",     0.0) * 100.0,
		_dominant_suit_label(metrics),
	]
	metrics_lbl.add_theme_font_size_override("font_size", 18)
	metrics_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(metrics_lbl)

	return outer

# ── color fingerprint ─────────────────────────────────────────────────────────
# H = dominant suit element, S = major arcana density, V = darkens with inversion

func _fingerprint_color(metrics: Dictionary) -> Color:
	var suit_hues := {
		"wands_frac":  0.08,   # orange-red  (fire)
		"cups_frac":   0.58,   # blue        (water)
		"swords_frac": 0.17,   # yellow      (air)
		"pents_frac":  0.35,   # green       (earth)
	}
	var dominant_key := "wands_frac"
	var dominant_val := 0.0
	for key in suit_hues:
		var val: float = metrics.get(key, 0.0)
		if val > dominant_val:
			dominant_val = val
			dominant_key = key
	var hue:        float = suit_hues[dominant_key]
	var sat:        float = lerpf(0.25, 0.85, metrics.get("major_ratio",    0.0))
	var brightness: float = lerpf(0.90, 0.60, metrics.get("inversion_ratio", 0.0))
	return Color.from_hsv(hue, sat, brightness)

func _dominant_suit_label(metrics: Dictionary) -> String:
	var suits := {
		"wands_frac": "Wands", "cups_frac": "Cups",
		"swords_frac": "Swords", "pents_frac": "Pents",
	}
	var best_key := "wands_frac"
	var best_val := 0.0
	for k in suits:
		var v: float = metrics.get(k, 0.0)
		if v > best_val:
			best_val = v
			best_key = k
	return suits[best_key] if best_val > 0.0 else "—"

func _layout_display_name(layout_id: String) -> String:
	match layout_id:
		"three-card":       return "3-Card"
		"ava-celtic-cross": return "Celtic Cross"
		"celtic-cross":     return "Celtic Cross (classic)"
		_:                  return layout_id
