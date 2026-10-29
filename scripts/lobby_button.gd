class_name LobbyButton
extends Area3D
## Carte cliquable du lobby (choix du mode, objets de la boutique). Fonctionne avec
## le rayon de la main droite comme tout autre interactable : survol = la carte
## s'éclaire, gâchette = `pressed`.

signal pressed

var accent := Color(0.4, 0.9, 0.85)
var enabled := true
var title_label: Label3D
var body_label: Label3D
var tag_label: Label3D

var _frame_mat: StandardMaterial3D
var _panel_mat: StandardMaterial3D
var _hover := false
var _size := Vector2(0.6, 0.5)


## `size` en mètres ; la carte regarde vers +Z (le parent la tourne vers le joueur).
func setup(size: Vector2, title: String, body: String, p_accent: Color, title_px := 0.0028, body_px := 0.0017) -> void:
	_size = size
	accent = p_accent

	var frame := MeshInstance3D.new()
	frame.name = "Cadre"
	var fq := QuadMesh.new()
	fq.size = size + Vector2(0.05, 0.05)
	frame.mesh = fq
	_frame_mat = StandardMaterial3D.new()
	_frame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	frame.material_override = _frame_mat
	add_child(frame)

	var panel := MeshInstance3D.new()
	panel.name = "Panneau"
	var pq := QuadMesh.new()
	pq.size = size
	panel.mesh = pq
	_panel_mat = StandardMaterial3D.new()
	_panel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	panel.material_override = _panel_mat
	panel.position.z = 0.004
	add_child(panel)

	title_label = Label3D.new()
	title_label.name = "Titre"
	title_label.text = title
	title_label.pixel_size = title_px
	title_label.font_size = 48
	title_label.outline_size = 6
	title_label.position = Vector3(0.0, size.y * 0.28, 0.01)
	title_label.width = size.x / title_px * 0.92
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(title_label)

	body_label = Label3D.new()
	body_label.name = "Texte"
	body_label.text = body
	body_label.pixel_size = body_px
	body_label.font_size = 36
	body_label.outline_size = 4
	body_label.position = Vector3(0.0, -size.y * 0.08, 0.01)
	body_label.width = size.x / body_px * 0.9
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(body_label)

	tag_label = Label3D.new()
	tag_label.name = "Etiquette"
	tag_label.pixel_size = body_px * 1.2
	tag_label.font_size = 38
	tag_label.outline_size = 5
	tag_label.position = Vector3(0.0, -size.y * 0.38, 0.01)
	tag_label.visible = false
	add_child(tag_label)

	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x + 0.08, size.y + 0.08, 0.3)
	cs.shape = shape
	cs.position.z = 0.1
	add_child(cs)
	_refresh()


## Étiquette du bas (prix, « POSSÉDÉ »…) et accessibilité de la carte.
func set_state(tag: String, p_accent: Color, p_enabled: bool) -> void:
	accent = p_accent
	enabled = p_enabled
	tag_label.text = tag
	tag_label.visible = tag != ""
	_refresh()


func _refresh() -> void:
	var glow := 1.0 if _hover else 0.55
	var base := accent if enabled else accent.darkened(0.6)
	_frame_mat.albedo_color = base * glow
	_panel_mat.albedo_color = Color(0.07, 0.08, 0.1).lerp(base, 0.18 if _hover else 0.06)
	var text_color := Color(0.95, 0.95, 0.92) if enabled else Color(0.6, 0.6, 0.6)
	title_label.modulate = text_color
	body_label.modulate = text_color.darkened(0.15)
	tag_label.modulate = base.lightened(0.35)


func on_pointed() -> void:
	_hover = true
	_refresh()


func on_unpointed() -> void:
	_hover = false
	_refresh()


func interact(_holding: Node3D = null) -> void:
	if not enabled:
		return
	pressed.emit()
