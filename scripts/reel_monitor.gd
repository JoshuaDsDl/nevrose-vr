class_name ReelMonitor
extends SubViewport
## Écran de retour du studio : ce que voit la caméra du trépied (portrait 9:16),
## recouvert de l'interface de tournage (REC, chrono, jauge de voix, prompteur,
## spectateurs en direct, compte à rebours).

const W := 360
const H := 640

enum View { STANDBY, COUNTDOWN, RECORDING, UPLOADING }

var _tex: TextureRect
var _rec_dot: ColorRect
var _rec_label: Label
var _live_label: Label
var _countdown: Label
var _cue_box: PanelContainer
var _cue_label: RichTextLabel
var _status: Label
var _meter: Array[ColorRect] = []
var _meter_box: Control
var _top: Control
var _view: View = View.STANDBY
var _blink := 0.0


func _init() -> void:
	size = Vector2i(W, H)
	transparent_bg = false
	disable_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _ready() -> void:
	_build()
	show_standby("")


func _process(delta: float) -> void:
	_blink += delta
	if _view == View.RECORDING:
		_rec_dot.visible = fmod(_blink, 1.0) < 0.62


func _build() -> void:
	_tex = TextureRect.new()
	_tex.size = Vector2(W, H)
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_tex)

	_top = Control.new()
	_top.size = Vector2(W, 70)
	add_child(_top)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.size = Vector2(W, 56)
	_top.add_child(shade)
	_rec_dot = ColorRect.new()
	_rec_dot.color = Color(1.0, 0.15, 0.2)
	_rec_dot.size = Vector2(16, 16)
	_rec_dot.position = Vector2(14, 20)
	_top.add_child(_rec_dot)
	_rec_label = _label("", 24, Color.WHITE)
	_rec_label.position = Vector2(38, 12)
	_top.add_child(_rec_label)
	_live_label = _label("", 20, Color.WHITE)
	_live_label.position = Vector2(W - 140, 14)
	_live_label.size = Vector2(128, 30)
	_live_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_top.add_child(_live_label)

	_cue_box = PanelContainer.new()
	_cue_box.position = Vector2(12, 66)
	_cue_box.size = Vector2(W - 24, 300)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_cue_box.add_theme_stylebox_override("panel", sb)
	_cue_label = RichTextLabel.new()
	_cue_label.bbcode_enabled = true
	_cue_label.scroll_active = false
	_cue_label.fit_content = true
	_cue_label.add_theme_font_size_override("normal_font_size", 26)
	_cue_label.add_theme_font_size_override("bold_font_size", 26)
	_cue_label.add_theme_color_override("default_color", Color(1, 1, 1))
	_cue_label.custom_minimum_size = Vector2(W - 52, 0)
	_cue_box.add_child(_cue_label)
	add_child(_cue_box)

	_countdown = _label("", 200, Color.WHITE)
	_countdown.size = Vector2(W, 260)
	_countdown.position = Vector2(0, H / 2.0 - 150)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown.add_theme_color_override("font_outline_color", Color.BLACK)
	_countdown.add_theme_constant_override("outline_size", 12)
	add_child(_countdown)

	_status = _label("", 22, Color.WHITE)
	_status.position = Vector2(14, H - 168)
	_status.size = Vector2(W - 28, 90)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 6)
	add_child(_status)

	# Jauge de voix : 16 barres qui s'allument de gauche à droite.
	_meter_box = Control.new()
	_meter_box.position = Vector2(14, H - 60)
	add_child(_meter_box)
	for i in 16:
		var bar := ColorRect.new()
		bar.size = Vector2(16, 14 + i)
		bar.position = Vector2(i * 21.0, 22.0 - i)
		bar.color = Color(1, 1, 1, 0.18)
		_meter_box.add_child(bar)
		_meter.append(bar)


func set_camera_texture(tex: Texture2D) -> void:
	_tex.texture = tex


# ---------------------------------------------------------------------------
# États
# ---------------------------------------------------------------------------
func show_standby(text: String) -> void:
	_view = View.STANDBY
	_top.visible = false
	_cue_box.visible = false
	_countdown.text = ""
	_status.text = text
	_meter_box.visible = false


func show_countdown(n: int) -> void:
	_view = View.COUNTDOWN
	_top.visible = false
	_cue_box.visible = false
	_status.text = "Prêt ? Regarde l'objectif."
	_meter_box.visible = false
	_countdown.text = str(n) if n > 0 else "GO"
	_countdown.pivot_offset = _countdown.size * 0.5
	_countdown.scale = Vector2(1.5, 1.5)
	_countdown.modulate = Color.WHITE
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_countdown, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_countdown, "modulate:a", 0.25, 0.8)


func show_recording(elapsed: float, limit: float, level: float, viewers: int, cue: String, mic_ok: bool) -> void:
	if _view != View.RECORDING:
		_view = View.RECORDING
		_top.visible = true
		_countdown.text = ""
		_cue_box.visible = false # le texte est lu sur le prompteur au-dessus de l'objectif
		_meter_box.visible = true
	_rec_label.text = "REC %02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60]
	_live_label.text = "LIVE  %s" % ReelData.format_count(viewers)
	if _cue_label.text != cue:
		_cue_label.text = cue
	_status.text = "" if mic_ok else "Micro indisponible"
	var lit := int(round(clampf(level, 0.0, 1.0) * _meter.size()))
	for i in _meter.size():
		var base := Color(0.35, 1.0, 0.55) if i < 10 else (Color(1.0, 0.8, 0.3) if i < 13 else Color(1.0, 0.3, 0.3))
		_meter[i].color = base if i < lit else Color(1, 1, 1, 0.18)


func show_uploading() -> void:
	_view = View.UPLOADING
	_top.visible = false
	_cue_box.visible = false
	_meter_box.visible = false
	_countdown.text = ""
	_status.text = "Réel publié.\nL'Algorithme regarde…"


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
