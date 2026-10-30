class_name ReelPostView
extends SubViewport
## Fiche d'un réel, façon Instagram sombre, dessinée dans un SubViewport 2D puis
## plaquée sur le grand écran du studio. L'image est celle qu'a réellement filmée la
## caméra ; à droite les compteurs montent un par un, les commentaires tombent à la
## suite et le badge de tokens claque à la fin.

const W := 560
const H := 900
const BG := Color(0.04, 0.04, 0.055)
const GRAY := Color(0.62, 0.64, 0.7)
const PINK := Color(1.0, 0.27, 0.32) # accent rouge du studio
const IMG_POS := Vector2(16, 72)
const IMG_SIZE := Vector2(300, 533)
const COL_X := 334.0
const MAX_COMMENTS := 5

var _frame: TextureRect
var _placeholder: Label
var _name_label: Label
var _sub_label: Label
var _views: Label
var _likes: Label
var _comments_count: Label
var _shares: Label
var _gain: Label
var _score: Label
var _score_unit: Label
var _caption: RichTextLabel
var _verdict_box: PanelContainer
var _verdict_text: Label
var _verdict_tag: Label
var _comments: VBoxContainer
var _ribbon: Label
var _spinner: Control
var _badge: Control
var _badge_label: Label
var _spin := 0.0
var _tweens: Array[Tween] = []


func _init() -> void:
	size = Vector2i(W, H)
	transparent_bg = false
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	disable_3d = true


func _ready() -> void:
	_build()
	reset("nevrose.officiel", 0)


func _process(delta: float) -> void:
	if _spinner != null and _spinner.visible:
		_spin += delta * 5.0
		_spinner.queue_redraw()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.size = Vector2(W, H)
	add_child(bg)

	# En-tête : avatar à anneau rose, nom du compte, abonnés.
	_add_panel(Vector2(16, 10), Vector2(48, 48), _round_box(PINK, 24))
	_add_panel(Vector2(19, 13), Vector2(42, 42), _round_box(Color(0.12, 0.1, 0.18), 21))
	var initial := _label("N", 22, Color.WHITE)
	initial.position = Vector2(32, 16)
	add_child(initial)
	_name_label = _label("", 22, Color.WHITE)
	_name_label.position = Vector2(76, 8)
	add_child(_name_label)
	_sub_label = _label("", 15, GRAY)
	_sub_label.position = Vector2(76, 38)
	add_child(_sub_label)

	# Image du réel, au format vertical réellement filmé.
	var frame_bg := ColorRect.new()
	frame_bg.color = Color(0.1, 0.1, 0.13)
	frame_bg.position = IMG_POS
	frame_bg.size = IMG_SIZE
	add_child(frame_bg)
	_frame = TextureRect.new()
	_frame.position = IMG_POS
	_frame.size = IMG_SIZE
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_frame)
	_placeholder = _label("Aucune image", 18, GRAY)
	_placeholder.position = IMG_POS + Vector2(80, IMG_SIZE.y / 2.0 - 12)
	add_child(_placeholder)
	var reel_chip := _chip("RÉEL", Color(0.0, 0.0, 0.0, 0.55), Color.WHITE, 14)
	reel_chip.position = IMG_POS + Vector2(10, 10)
	add_child(reel_chip)

	_spinner = Control.new()
	_spinner.position = IMG_POS + IMG_SIZE * 0.5 - Vector2(0, 30)
	_spinner.draw.connect(_draw_spinner)
	add_child(_spinner)
	_ribbon = _label("", 16, Color.WHITE)
	_ribbon.position = IMG_POS + Vector2(0, IMG_SIZE.y - 56)
	_ribbon.size = Vector2(IMG_SIZE.x, 56)
	_ribbon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ribbon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ribbon.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var rb := StyleBoxFlat.new()
	rb.bg_color = Color(0.0, 0.0, 0.0, 0.66)
	_ribbon.add_theme_stylebox_override("normal", rb)
	add_child(_ribbon)

	# Colonne de droite : vues, likes, commentaires, partages, abonnés, note.
	var views_tag := _label("VUES", 14, GRAY)
	views_tag.position = Vector2(COL_X, 74)
	add_child(views_tag)
	_views = _label("—", 40, Color.WHITE)
	_views.position = Vector2(COL_X, 88)
	add_child(_views)
	_likes = _stat_row(0, ReelIcons.heart(), 168)
	_comments_count = _stat_row(1, ReelIcons.bubble(), 224)
	_shares = _stat_row(2, ReelIcons.plane(), 280)
	var gain_tag := _label("ABONNÉS GAGNÉS", 14, GRAY)
	gain_tag.position = Vector2(COL_X, 346)
	add_child(gain_tag)
	_gain = _label("—", 30, Color(0.55, 0.9, 0.6))
	_gain.position = Vector2(COL_X, 362)
	add_child(_gain)
	var score_tag := _label("NOTE DU JURY", 14, GRAY)
	score_tag.position = Vector2(COL_X, 416)
	add_child(score_tag)
	_score = _label("—", 52, Color.WHITE)
	_score.position = Vector2(COL_X, 430)
	add_child(_score)
	_score_unit = _label("", 18, GRAY)
	_score_unit.position = Vector2(COL_X + 112, 458)
	add_child(_score_unit)

	# Légende, verdict, commentaires.
	_caption = RichTextLabel.new()
	_caption.bbcode_enabled = true
	_caption.scroll_active = false
	_caption.position = Vector2(16, 614)
	_caption.size = Vector2(W - 32, 34)
	_caption.add_theme_font_size_override("normal_font_size", 17)
	_caption.add_theme_font_size_override("bold_font_size", 17)
	add_child(_caption)

	_verdict_box = PanelContainer.new()
	_verdict_box.position = Vector2(16, 652)
	_verdict_box.size = Vector2(W - 32, 76)
	var vb := StyleBoxFlat.new()
	vb.bg_color = Color(0.13, 0.08, 0.18)
	vb.border_color = PINK
	vb.border_width_left = 4
	vb.set_corner_radius_all(8)
	vb.content_margin_left = 14
	vb.content_margin_right = 10
	vb.content_margin_top = 5
	vb.content_margin_bottom = 5
	_verdict_box.add_theme_stylebox_override("panel", vb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	_verdict_box.add_child(col)
	_verdict_tag = _label("L'ALGORITHME", 12, PINK)
	col.add_child(_verdict_tag)
	_verdict_text = _label("", 17, Color(0.93, 0.92, 0.96))
	_verdict_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_verdict_text.custom_minimum_size = Vector2(W - 70, 0)
	col.add_child(_verdict_text)
	add_child(_verdict_box)

	_comments = VBoxContainer.new()
	_comments.position = Vector2(16, 740)
	_comments.size = Vector2(W - 32, 150)
	_comments.add_theme_constant_override("separation", 2)
	add_child(_comments)

	# Badge de tokens : claque à la toute fin sur la colonne de droite.
	_badge = Control.new()
	_badge.position = Vector2(COL_X + 100, 556)
	_badge.visible = false
	var disc := Panel.new()
	disc.position = Vector2(-52, -52)
	disc.size = Vector2(104, 104)
	var db := _round_box(Color(1.0, 0.8, 0.2), 52)
	db.border_color = Color(1.0, 0.95, 0.6)
	db.set_border_width_all(5)
	disc.add_theme_stylebox_override("panel", db)
	_badge.add_child(disc)
	_badge_label = _label("+0", 38, Color(0.25, 0.14, 0.0))
	_badge_label.position = Vector2(-52, -34)
	_badge_label.size = Vector2(104, 44)
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.add_child(_badge_label)
	var unit := _label("TOKENS", 14, Color(0.25, 0.14, 0.0))
	unit.position = Vector2(-52, 8)
	unit.size = Vector2(104, 20)
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.add_child(unit)
	add_child(_badge)


func _stat_row(index: int, icon: Texture2D, y: float) -> Label:
	var tex := TextureRect.new()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE # avant la taille : sinon l'icône garde ses 64 px
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.custom_minimum_size = Vector2(34, 34)
	tex.texture = icon
	tex.position = Vector2(COL_X, y)
	tex.size = Vector2(34, 34)
	add_child(tex)
	var l := _label("—", 28, Color.WHITE)
	l.position = Vector2(COL_X + 46, y - 2)
	add_child(l)
	return l


func _draw_spinner() -> void:
	_spinner.draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 48, Color(1, 1, 1, 0.14), 6.0, true)
	_spinner.draw_arc(Vector2.ZERO, 34.0, _spin, _spin + 1.6, 24, PINK, 6.0, true)


# ---------------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------------
func reset(account: String, followers: int) -> void:
	_kill_tweens()
	_name_label.text = account
	set_followers(followers)
	_frame.texture = null
	_placeholder.visible = true
	for l in [_views, _likes, _comments_count, _shares, _gain]:
		(l as Label).text = "—"
	_score.text = "—"
	_score.remove_theme_color_override("font_color")
	_score_unit.text = ""
	_caption.text = ""
	_verdict_text.text = ""
	_verdict_tag.text = "L'ALGORITHME"
	_verdict_box.modulate.a = 0.0
	_badge.visible = false
	set_analyzing("", false)
	for c in _comments.get_children():
		c.free()


func set_frame(image: Image) -> void:
	if image == null or image.is_empty():
		return
	_frame.texture = ImageTexture.create_from_image(image)
	_placeholder.visible = false


## Roue qui tourne et message sur l'image pendant que le jury travaille.
func set_analyzing(text: String, on: bool = true) -> void:
	_spinner.visible = on
	_ribbon.text = text
	_ribbon.visible = text != ""


func set_followers(followers: int) -> void:
	_sub_label.text = "Audio original · %s abonnés" % ReelData.format_count(followers)


func set_title(title: String) -> void:
	_caption.text = "[b]%s[/b]  %s  [color=#7aa7ff]#complot #crypto[/color]" % [_name_label.text, title.replace("[", "(")]


func set_score(score: float) -> void:
	_score.text = ("%.1f" % score).replace(".", ",")
	_score_unit.text = "/ 10"
	var color := Color(0.45, 0.9, 0.5) if score >= 7.0 else (Color(1.0, 0.8, 0.3) if score >= 4.0 else Color(1.0, 0.4, 0.35))
	_score.add_theme_color_override("font_color", color)


## Qui a jugé : le LLM du serveur ou le juge local de secours.
func set_judge(judge: String) -> void:
	_verdict_tag.text = "L'ALGORITHME · %s" % judge.to_upper() if judge != "" else "L'ALGORITHME"


func set_verdict(text: String) -> void:
	_verdict_text.text = text
	var tw := _new_tween()
	tw.tween_property(_verdict_box, "modulate:a", 1.0, 0.4)


## Fait grimper un compteur. `key` : views, likes, comments, shares, followers.
func count_up(key: String, value: int, instant := false) -> void:
	var target: Label = null
	var prefix := ""
	match key:
		"views":
			target = _views
		"likes":
			target = _likes
		"comments":
			target = _comments_count
		"shares":
			target = _shares
		"followers":
			target = _gain
			prefix = "+"
	if target == null:
		return
	if instant or value <= 0:
		target.text = prefix + ReelData.format_count(maxi(value, 0))
		return
	var tw := _new_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(v: float) -> void:
		target.text = prefix + ReelData.format_count(int(v)), 0.0, float(value), 1.5)


func add_comment(user: String, text: String, instant := false) -> void:
	if _comments.get_child_count() >= MAX_COMMENTS:
		return
	var row := RichTextLabel.new()
	row.bbcode_enabled = true
	row.fit_content = true
	row.scroll_active = false
	row.custom_minimum_size = Vector2(W - 32, 26)
	row.add_theme_font_size_override("normal_font_size", 16)
	row.add_theme_font_size_override("bold_font_size", 16)
	row.text = "[b]%s[/b]  %s" % [user.replace("[", "("), text.replace("[", "(")]
	_comments.add_child(row)
	if instant:
		return
	row.modulate.a = 0.0
	var tw := _new_tween()
	tw.tween_property(row, "modulate:a", 1.0, 0.35)


func show_tokens(amount: int, instant := false) -> void:
	_badge_label.text = "+%d" % amount
	_badge.visible = true
	if instant:
		_badge.scale = Vector2.ONE
		return
	_badge.scale = Vector2.ZERO
	var tw := _new_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_badge, "scale", Vector2.ONE, 0.55)


## Affiche d'un coup un réel déjà jugé (onglet d'un ancien réel).
func render_final(result: Dictionary, tokens: int) -> void:
	count_up("views", int(result.get("views", 0)), true)
	count_up("likes", int(result.get("likes", 0)), true)
	count_up("comments", int(result.get("comments", 0)), true)
	count_up("shares", int(result.get("shares", 0)), true)
	count_up("followers", int(result.get("followers", 0)), true)
	set_score(float(result.get("score", 0.0)))
	set_title(String(result.get("title", "")))
	_verdict_text.text = String(result.get("verdict", ""))
	_verdict_box.modulate.a = 1.0
	for c in _comments.get_children():
		c.free()
	for c in result.get("comment_list", []):
		add_comment(c["user"], c["text"], true)
	if tokens > 0:
		show_tokens(tokens, true)


# ---------------------------------------------------------------------------
# Fabrique d'éléments
# ---------------------------------------------------------------------------
func _add_panel(pos: Vector2, panel_size: Vector2, style: StyleBoxFlat) -> void:
	var p := Panel.new()
	p.position = pos
	p.size = panel_size
	p.add_theme_stylebox_override("panel", style)
	add_child(p)


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _chip(text: String, bg: Color, fg: Color, font_size: int) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(_label(text, font_size, fg))
	return p


func _round_box(color: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	return sb


func _new_tween() -> Tween:
	var tw := create_tween()
	_tweens.append(tw)
	return tw


func _kill_tweens() -> void:
	for tw in _tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_tweens.clear()
