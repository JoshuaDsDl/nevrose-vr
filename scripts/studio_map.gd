class_name StudioMap
extends MapBase
## Le studio d'enregistrement : une pièce à part, pensée pour filmer des réels.
## Ambiance sombre et rouge : mur du fond bordeaux avec une enseigne néon, console
## centrale, tapis rond sous la croix de tournage, canapé et bibliothèque hors champ,
## bandes LED rouges qui respirent. Les décorations achetées à la boutique s'accrochent au mur du fond :
## c'est le décor que la caméra du trépied filme.
##
## Repère : la pièce occupe x ∈ [-3.5, 3.5], z ∈ [-3.0, 3.5] ; le mur du fond est au nord
## (z = -3), la caméra filme vers le nord depuis le sud.

const X_MIN := -3.5
const X_MAX := 3.5
const Z_MIN := -3.0
const Z_MAX := 3.5
const HEIGHT := 3.3
const CUSTOM := "res://assets/customizgeg/"
const KENNEY := "res://assets/kenney/furniture/"

## Décorations de la boutique, repositionnées pour le studio.
## "glb" : modèle du dossier customizgeg ; "frame" : cadre procédural ; "kenney" : meuble.
const DECOR := {
	"tableau_royal": {"kind": "custom", "glb": "tableau_royesque_framed.glb", "pos": Vector3(0.8, 2.15, -2.97), "rot": 0.0, "scale": Vector3(1.1, 1.1, 1.0)},
	"tableau_mayo": {"kind": "custom", "glb": "mayozedong_framed.glb", "pos": Vector3(-0.95, 2.0, -2.97), "rot": 0.0, "scale": Vector3(1.0, 1.0, 1.0)},
	"tableau_swap": {"kind": "custom", "glb": "faceswapinggggggggg_framed.glb", "pos": Vector3(-3.47, 1.45, -0.4), "rot": 90.0, "scale": Vector3(2.0, 1.75, 1.0)},
	"cadre_paysage": {"kind": "frame", "pos": Vector3(3.47, 1.65, -1.7), "rot": -90.0},
	"cadre_portrait": {"kind": "frame", "pos": Vector3(0.0, 1.7, 3.47), "rot": 180.0},
	"plante_angle": {"kind": "kenney", "glb": "plantSmall2.glb", "pos": Vector3(-1.75, 0.0, -2.55), "scale": 2.5},
	"lampadaire": {"kind": "kenney", "glb": "lampRoundFloor.glb", "pos": Vector3(1.9, 0.0, -2.55), "scale": 2.5},
	"lampe_table": {"kind": "kenney", "glb": "lampRoundTable.glb", "on": "Console", "offset": Vector3(0.65, 0.0, 0.0), "scale": 2.5},
	"livres": {"kind": "kenney", "glb": "books.glb", "on": "Console", "offset": Vector3(-0.65, 0.0, 0.0), "scale": 2.5},
	"radio": {"kind": "kenney", "glb": "radio.glb", "on": "Console", "offset": Vector3(0.0, 0.0, 0.0), "scale": 2.5},
	"nounours": {"kind": "kenney", "glb": "bear.glb", "pos": Vector3(1.8, 0.42, 2.95), "scale": 1.3},
}

var _shell: Node3D
var _leds: Array[Dictionary] = [] # {mat, light, phase}
var _clock := 0.0


func build() -> void:
	room_w = X_MAX - X_MIN
	room_d = Z_MAX - Z_MIN
	room_h = HEIGHT
	_shell = Node3D.new()
	_shell.name = "Shell"
	add_child(_shell)
	_build_shell()
	_build_furniture()
	_build_lighting()
	_build_sign()


func _process(delta: float) -> void:
	_clock += delta
	for led in _leds:
		# Rouge unique : seule l'intensité respire, doucement.
		var pulse := 0.8 + 0.2 * sin(_clock * 1.3 + float(led["phase"]) * TAU)
		var c := Color(1.0, 0.1, 0.12) * pulse
		(led["mat"] as StandardMaterial3D).emission = c
		(led["mat"] as StandardMaterial3D).albedo_color = c
		if led["light"] != null:
			(led["light"] as OmniLight3D).light_energy = 0.4 * pulse


# ---------------------------------------------------------------------------
# Coquille : sol, murs, plafond (avec collisions)
# ---------------------------------------------------------------------------
func _solid(node_name: String, size: Vector3, pos: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	body.add_child(mesh)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	_shell.add_child(body)
	return body


func _plaster_mat(color: Color, uv := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = ProceduralTextures.plaster(Color.WHITE)
	m.uv1_scale = Vector3(uv, uv, 1.0)
	m.roughness = 0.95
	return m


func _build_shell() -> void:
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.42, 0.3, 0.26)
	floor_mat.albedo_texture = ProceduralTextures.wood(Color.WHITE)
	floor_mat.uv1_scale = Vector3(3, 3, 1)
	floor_mat.roughness = 0.45
	var w := X_MAX - X_MIN
	var d := Z_MAX - Z_MIN
	var cx := (X_MAX + X_MIN) * 0.5
	var cz := (Z_MAX + Z_MIN) * 0.5
	_solid("Floor", Vector3(w, 0.1, d), Vector3(cx, -0.05, cz), floor_mat)
	_solid("Ceiling", Vector3(w, 0.1, d), Vector3(cx, HEIGHT + 0.05, cz), _plaster_mat(Color(0.2, 0.15, 0.16)))
	var back := _plaster_mat(Color(0.5, 0.09, 0.12)) # le décor : bordeaux
	var side := _plaster_mat(Color(0.22, 0.17, 0.18))
	_solid("WallN", Vector3(w + 0.2, HEIGHT, 0.1), Vector3(cx, HEIGHT * 0.5, Z_MIN - 0.05), back)
	_solid("WallS", Vector3(w + 0.2, HEIGHT, 0.1), Vector3(cx, HEIGHT * 0.5, Z_MAX + 0.05), side)
	_solid("WallW", Vector3(0.1, HEIGHT, d), Vector3(X_MIN - 0.05, HEIGHT * 0.5, cz), side)
	_solid("WallE", Vector3(0.1, HEIGHT, d), Vector3(X_MAX + 0.05, HEIGHT * 0.5, cz), side)
	# Plinthes sombres pour que les murs ne « flottent » pas.
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.08, 0.08, 0.1)
	for spec in [
		[Vector3(w, 0.12, 0.03), Vector3(cx, 0.06, Z_MIN + 0.015)],
		[Vector3(w, 0.12, 0.03), Vector3(cx, 0.06, Z_MAX - 0.015)],
		[Vector3(0.03, 0.12, d), Vector3(X_MIN + 0.015, 0.06, cz)],
		[Vector3(0.03, 0.12, d), Vector3(X_MAX - 0.015, 0.06, cz)],
	]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[0]
		mi.mesh = bm
		mi.material_override = base_mat
		mi.position = spec[1]
		_shell.add_child(mi)


# ---------------------------------------------------------------------------
# Mobilier : hors du champ de la caméra, sauf la console et le tapis
# ---------------------------------------------------------------------------
func _build_furniture() -> void:
	var rug := _place_centered(KENNEY + "rugRound.glb", Vector2(0.0, -1.5), 0.0, 3.2, 0.0, false)
	if rug != null:
		rug.name = "Tapis"
	var console := _place_centered(KENNEY + "cabinetTelevision.glb", Vector2(0.0, -2.65), 0.0, 2.5)
	if console != null:
		console.name = "Console"
	var sofa := _place_centered(KENNEY + "loungeSofa.glb", Vector2(2.2, 2.95), 180.0, 2.5)
	if sofa != null:
		sofa.name = "Canape"
	_place_centered(KENNEY + "bookcaseClosedWide.glb", Vector2(-3.15, 2.4), 90.0, 2.5)
	_place_centered(KENNEY + "pottedPlant.glb", Vector2(-3.0, -2.6), 0.0, 2.5)
	_place_centered(KENNEY + "pottedPlant.glb", Vector2(3.0, -2.6), 0.0, 2.5)
	_place_centered(KENNEY + "speaker.glb", Vector2(-2.5, -2.75), 0.0, 2.5)
	_place_centered(KENNEY + "speaker.glb", Vector2(2.6, -2.75), 0.0, 2.5)
	var desk := _place_centered(KENNEY + "desk.glb", Vector2(-1.9, 3.0), 180.0, 2.5)
	if desk != null:
		_place_centered(KENNEY + "computerScreen.glb", Vector2(-1.9, 3.1), 180.0, 2.5, 0.96)
	_place_centered(KENNEY + "chairDesk.glb", Vector2(-1.9, 2.2), 0.0, 2.5)


## Les modèles Kenney ont leur pivot dans un coin : on centre leur emprise sur
## (centre.x, centre.y) du plan, et on pose le bas à la hauteur `y`.
func _place_centered(glb_path: String, center: Vector2, rot_y: float, p_scale: float, y := 0.0, collide := true) -> Node3D:
	var packed: PackedScene = load(glb_path)
	if packed == null:
		push_warning("StudioMap: GLB introuvable %s" % glb_path)
		return null
	var n: Node3D = packed.instantiate()
	n.name = glb_path.get_file().get_basename()
	n.rotation.y = deg_to_rad(rot_y)
	n.scale = Vector3.ONE * p_scale
	_center_on(n, center, y)
	_shell.add_child(n)
	if collide:
		_add_box_collision(n)
	return n


func _center_on(n: Node3D, center: Vector2, y: float) -> void:
	var box := _bounds(n, Transform3D(n.basis, Vector3.ZERO))
	var middle := box.get_center()
	n.position = Vector3(center.x - middle.x, y - box.position.y, center.y - middle.z)


## Emprise d'un nœud (et de ses enfants) dans le repère de son parent, hors position.
func _bounds(n: Node3D, acc: Transform3D) -> AABB:
	var box := AABB()
	var has := false
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		box = acc * (n as MeshInstance3D).mesh.get_aabb()
		has = true
	for c in n.get_children():
		if c is Node3D:
			var sub := _bounds(c as Node3D, acc * (c as Node3D).transform)
			if sub.size != Vector3.ZERO:
				box = sub if not has else box.merge(sub)
				has = true
	return box


# ---------------------------------------------------------------------------
# Lumière : plafonnier froid, bandes LED, ambiance du mur du fond
# ---------------------------------------------------------------------------
func _build_lighting() -> void:
	for pos in [Vector3(-1.5, HEIGHT - 0.15, -0.5), Vector3(1.5, HEIGHT - 0.15, -0.5), Vector3(-1.5, HEIGHT - 0.15, 2.0), Vector3(1.5, HEIGHT - 0.15, 2.0)]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.35, 0.3)
		l.light_energy = 0.45
		l.omni_range = 5.5
		l.position = pos
		_shell.add_child(l)
		var panel := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.6, 0.03, 0.6)
		panel.mesh = bm
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(1.0, 0.45, 0.4)
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		panel.material_override = pm
		panel.position = pos + Vector3(0, 0.1, 0)
		_shell.add_child(panel)
	# Bandes LED : plafond du fond, bas du mur du fond, murs latéraux.
	var specs := [
		[Vector3(6.8, 0.05, 0.05), Vector3(0.0, HEIGHT - 0.2, Z_MIN + 0.06), 0.0],
		[Vector3(6.8, 0.05, 0.05), Vector3(0.0, 0.32, Z_MIN + 0.06), 0.33],
		[Vector3(0.05, 0.05, 5.8), Vector3(X_MIN + 0.06, HEIGHT - 0.2, 0.2), 0.66],
		[Vector3(0.05, 0.05, 5.8), Vector3(X_MAX - 0.06, HEIGHT - 0.2, 0.2), 0.16],
	]
	for spec in specs:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[0]
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission_energy_multiplier = 1.5
		mi.material_override = m
		mi.position = spec[1]
		_shell.add_child(mi)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.12, 0.12)
		light.light_energy = 0.4
		light.omni_range = 3.5
		light.position = (spec[1] as Vector3) + Vector3(0, 0, 0.2) if absf((spec[0] as Vector3).x) > 1.0 else (spec[1] as Vector3) + Vector3(0.2 * signf(-(spec[1] as Vector3).x), 0, 0)
		_shell.add_child(light)
		_leds.append({"mat": m, "light": light, "phase": spec[2]})


## Enseigne néon au-dessus du décor.
func _build_sign() -> void:
	var sign_label := Label3D.new()
	sign_label.name = "Neon"
	sign_label.text = "NÉVROSE LIVE"
	sign_label.font_size = 96
	sign_label.pixel_size = 0.0045
	sign_label.outline_size = 14
	sign_label.outline_modulate = Color(0.45, 0.0, 0.03)
	sign_label.modulate = Color(1.0, 0.3, 0.32)
	sign_label.shaded = false
	sign_label.position = Vector3(0.0, 3.0, Z_MIN + 0.04)
	_shell.add_child(sign_label)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.1, 0.15)
	glow.light_energy = 0.8
	glow.omni_range = 3.0
	glow.position = Vector3(0.0, 2.9, Z_MIN + 0.5)
	_shell.add_child(glow)


# ---------------------------------------------------------------------------
# Décorations de la boutique
# ---------------------------------------------------------------------------
func apply_decorations(owned: Array) -> void:
	for child in _shell.get_children():
		if String(child.name).begins_with("Deco_"):
			child.queue_free()
	for id in DECOR:
		if not (id in owned):
			continue
		var spec: Dictionary = DECOR[id]
		var node := _build_decor(id, spec)
		if node == null:
			continue
		node.name = "Deco_" + String(id)
		_shell.add_child(node)
		_place_decor(node, spec)


func _build_decor(id: String, spec: Dictionary) -> Node3D:
	match spec["kind"]:
		"custom":
			var packed: PackedScene = load(CUSTOM + String(spec["glb"]))
			if packed == null:
				return null
			var n: Node3D = packed.instantiate()
			n.scale = spec["scale"]
			return n
		"frame":
			return DecorCatalog._build_frame(DecorCatalog.get_item(id))
		"kenney":
			var packed2: PackedScene = load(KENNEY + String(spec["glb"]))
			if packed2 == null:
				return null
			var n2: Node3D = packed2.instantiate()
			n2.scale = Vector3.ONE * float(spec.get("scale", 2.5))
			return n2
	return null


func _place_decor(node: Node3D, spec: Dictionary) -> void:
	if spec["kind"] == "kenney":
		# Pivot dans un coin : on centre l'emprise sur le point voulu.
		if spec.has("on"):
			var support := _shell.get_node_or_null(String(spec["on"])) as Node3D
			if support == null:
				return
			var top := DecorCatalog._top_of(_shell, support) + (spec["offset"] as Vector3)
			_center_on(node, Vector2(top.x, top.z), top.y)
		else:
			var at: Vector3 = spec["pos"]
			_center_on(node, Vector2(at.x, at.z), at.y)
		return
	node.position = spec["pos"]
	node.rotation.y = deg_to_rad(float(spec.get("rot", 0.0)))
