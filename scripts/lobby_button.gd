class_name LobbyButton
extends Area3D
## Carte cliquable (choix du mode, boutique, tableau des idées). Fonctionne avec le
## rayon de la main droite comme tout autre interactable : survol = la carte s'éclaire,
## gâchette = `pressed`.
##
## Rendu moderne : panneau à coins arrondis dessiné par un shader (dégradé sombre,
## liseré et halo de la couleur d'accent, remplissage quand la carte est choisie),
## titre en gras et étiquette en « pilule ». `make_panel` sert aussi aux fonds de tableau.

signal pressed

const PAD := 0.05 ## marge du quad pour laisser de la place au halo

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec2 box_size = vec2(0.8, 1.0);
uniform float pad = 0.05;
uniform float radius = 0.045;
uniform vec4 accent : source_color = vec4(1.0, 0.3, 0.3, 1.0);
uniform vec4 fill_top : source_color = vec4(0.3, 0.28, 0.37, 1.0);
uniform vec4 fill_bottom : source_color = vec4(0.12, 0.11, 0.17, 1.0);
uniform float hover = 0.0;
uniform float enabled = 1.0;
uniform float selected = 0.0;
uniform float border = 0.008;
uniform float glow_strength = 0.5;
uniform float opacity = 0.97;

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 full = box_size + vec2(pad * 2.0);
	vec2 p = (UV - vec2(0.5)) * full;
	float d = sd_round_box(p, box_size * 0.5, radius);
	float aa = 0.0022;
	float shape = 1.0 - smoothstep(-aa, aa, d);
	float ring = shape * smoothstep(-border - aa, -border + aa, d);

	vec3 acc = enabled > 0.5 ? accent.rgb : mix(vec3(0.35), accent.rgb, 0.25);
	vec3 col = mix(fill_top.rgb, fill_bottom.rgb, UV.y);
	col += acc * 0.16 * smoothstep(0.35, 0.0, UV.y);      // reflet doux en haut
	col = mix(col, acc * 0.55, selected * 0.55 + hover * 0.14);
	col = mix(col, acc, ring * (0.8 + 0.2 * max(hover, selected)));

	float outside = max(d, 0.0);
	float glow = exp(-outside * 38.0) * (1.0 - shape) * glow_strength * (0.3 + hover * 0.9 + selected * 0.8);
	vec3 rgb = col * shape + acc * glow;
	ALBEDO = rgb;
	ALPHA = clamp(shape * opacity + glow * 0.85, 0.0, 1.0);
}
"""

static var _shader: Shader = null
static var _bold: FontVariation = null

var accent := Color(0.4, 0.9, 0.85)
var enabled := true
var selected := false
var title_label: Label3D
var body_label: Label3D
var tag_label: Label3D

var _panel: MeshInstance3D
var _pill: MeshInstance3D
var _hover := false
var _hover_amount := 0.0
var _hover_tween: Tween = null
var _size := Vector2(0.6, 0.5)
var _tag_px := 0.0018


## Panneau à coins arrondis, sans interaction (fond de tableau, bandeau, pastille).
static func make_panel(box: Vector2, p_accent: Color, radius := 0.045, glow := 0.4,
		top := Color(0.3, 0.28, 0.37), bottom := Color(0.12, 0.11, 0.17),
		border := 0.008, opacity := 0.97, priority := -2) -> MeshInstance3D:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = box + Vector2(PAD, PAD) * 2.0
	mi.mesh = qm
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("box_size", box)
	mat.set_shader_parameter("pad", PAD)
	mat.set_shader_parameter("radius", minf(radius, minf(box.x, box.y) * 0.5))
	mat.set_shader_parameter("accent", p_accent)
	mat.set_shader_parameter("fill_top", top)
	mat.set_shader_parameter("fill_bottom", bottom)
	mat.set_shader_parameter("glow_strength", glow)
	mat.set_shader_parameter("border", border)
	mat.set_shader_parameter("opacity", opacity)
	mat.render_priority = priority # dessiné avant les textes (et les cartes) posés dessus
	mi.material_override = mat
	return mi


static func bold_font() -> Font:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.55
	return _bold


## `size` en mètres ; la carte regarde vers +Z (le parent la tourne vers le joueur).
func setup(size: Vector2, title: String, body: String, p_accent: Color, title_px := 0.0028, body_px := 0.0017) -> void:
	_size = size
	accent = p_accent
	_tag_px = body_px * 1.2

	_panel = make_panel(size, accent, minf(0.05, size.y * 0.22), 0.55)
	_panel.name = "Panneau"
	add_child(_panel)

	# Pilule derrière l'étiquette du bas (prix, « CHOISIE »…).
	_pill = make_panel(Vector2(0.2, 0.07), accent, 0.035, 0.0, Color(1, 1, 1, 1), Color(1, 1, 1, 1), 0.0, 0.22)
	_pill.name = "Pilule"
	(_pill.material_override as ShaderMaterial).render_priority = -1
	_pill.position = Vector3(0.0, -size.y * 0.38, 0.003)
	_pill.visible = false
	add_child(_pill)

	title_label = Label3D.new()
	title_label.name = "Titre"
	title_label.text = title
	title_label.font = bold_font()
	title_label.pixel_size = title_px
	title_label.font_size = 48
	title_label.render_priority = 2
	title_label.outline_size = 4
	title_label.outline_modulate = Color(0, 0, 0, 0.55)
	title_label.position = Vector3(0.0, size.y * 0.28, 0.01)
	title_label.width = size.x / title_px * 0.9
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(title_label)

	body_label = Label3D.new()
	body_label.name = "Texte"
	body_label.text = body
	body_label.pixel_size = body_px
	body_label.font_size = 36
	body_label.render_priority = 2
	body_label.outline_size = 3
	body_label.outline_modulate = Color(0, 0, 0, 0.5)
	body_label.position = Vector3(0.0, -size.y * 0.08, 0.01)
	body_label.width = size.x / body_px * 0.88
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(body_label)

	tag_label = Label3D.new()
	tag_label.name = "Etiquette"
	tag_label.font = bold_font()
	tag_label.pixel_size = _tag_px
	tag_label.font_size = 34
	tag_label.render_priority = 2
	tag_label.outline_size = 3
	tag_label.outline_modulate = Color(0, 0, 0, 0.5)
	tag_label.position = Vector3(0.0, -size.y * 0.38, 0.012)
	tag_label.visible = false
	add_child(tag_label)

	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x + 0.08, size.y + 0.08, 0.3)
	cs.shape = shape
	cs.position.z = 0.1
	add_child(cs)
	_refresh()


## Étiquette du bas (prix, « POSSÉDÉ »…), accessibilité et état « choisie » de la carte.
func set_state(tag: String, p_accent: Color, p_enabled: bool, p_selected := false) -> void:
	accent = p_accent
	enabled = p_enabled
	selected = p_selected
	tag_label.text = tag
	tag_label.visible = tag != ""
	_pill.visible = tag != ""
	if tag != "":
		var width := clampf(tag.length() * 34.0 * _tag_px * 0.62 + 0.09, 0.14, _size.x - 0.06)
		_set_panel_size(_pill, Vector2(width, 34.0 * _tag_px * 1.9))
	_refresh()


func _set_panel_size(mi: MeshInstance3D, box: Vector2) -> void:
	(mi.mesh as QuadMesh).size = box + Vector2(PAD, PAD) * 2.0
	var mat := mi.material_override as ShaderMaterial
	mat.set_shader_parameter("box_size", box)
	mat.set_shader_parameter("radius", box.y * 0.5)


func _refresh() -> void:
	var mat := _panel.material_override as ShaderMaterial
	mat.set_shader_parameter("accent", accent)
	mat.set_shader_parameter("enabled", 1.0 if enabled else 0.0)
	mat.set_shader_parameter("selected", 1.0 if selected else 0.0)
	mat.set_shader_parameter("hover", _hover_amount)
	var pill_mat := _pill.material_override as ShaderMaterial
	pill_mat.set_shader_parameter("accent", accent)
	pill_mat.set_shader_parameter("opacity", 0.9 if selected else 0.26)
	var bright := Color(0.96, 0.96, 0.98) if enabled else Color(0.58, 0.58, 0.62)
	title_label.modulate = bright
	body_label.modulate = bright.darkened(0.1)
	var tag_color := accent.lightened(0.5) if enabled else Color(0.6, 0.6, 0.64)
	if selected:
		tag_color = Color(0.08, 0.05, 0.02)
	tag_label.modulate = tag_color
	tag_label.outline_modulate = Color(1, 1, 1, 0.0) if selected else Color(0, 0, 0, 0.5)


func _animate_hover(target: float) -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_method(func(v: float) -> void:
		_hover_amount = v
		_refresh(), _hover_amount, target, 0.14)


func on_pointed() -> void:
	_hover = true
	_animate_hover(1.0 if enabled else 0.4)


func on_unpointed() -> void:
	_hover = false
	_animate_hover(0.0)


func interact(_holding: Node3D = null) -> void:
	if not enabled:
		return
	pressed.emit()
