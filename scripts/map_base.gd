class_name MapBase
extends Node3D
## Classe de base de toutes les maps (fragment 1 studio, fragment 2 salon+cuisine).
## Factorise ce qu'attend main.gd :
##   - containers (tiroirs / placards interactifs, verrous inclus)
##   - spawn / clear / reveal de la Dose (pilule)
##   - clés cachées (GDD §5.6)
##   - mimics (fausses tasses — GDD §5.3)
##   - dérive "folie" des matériaux (teinte calm → sick, GDD §5.2)
##   - helper de placement des assets GLB Kenney (meuble statique + collision)
##
## Une sous-classe concrète (Map2Extended…) surcharge build() et
## appelle _register_spawn_spots() quand la géométrie est prête.

# Dimensions de la pièce — la sous-classe les surchargent AVANT build().
var room_w := 6.0
var room_d := 4.5
var room_h := 2.7

var containers: Array[InteractiveContainer] = []
var mimics: Array[Mimic] = []
var _dose: Dose = null
var _spawn_spots: Array[Dictionary] = [] # {pos, container, floor}
var _insanity := 0.0

# Matériaux "qui respirent" (dérive calm→sick). Les sous-classes les remplissent
# via _reg_breather() quand elles créent leurs matériaux.
var _breathers: Array[Dictionary] = [] # {mat, calm, sick}
var _flicker_lights: Array[Dictionary] = [] # {light, base}

# Primitives partagées pour les conteneurs (petites boîtes, coût nul).
var _unit_box: BoxMesh


func _ready() -> void:
	_unit_box = BoxMesh.new()
	_unit_box.size = Vector3.ONE


## À surcharger : construire la coquille + les meubles + les conteneurs,
## puis appeler _register_spawn_spots().
func build() -> void:
	pass


# ---------------------------------------------------------------------------
# Assets Kenney : meuble statique posé au sol, avec sa collision
# ---------------------------------------------------------------------------

## Instancie un GLB Kenney, l'ajoute sous `parent`, le pose à `pos` (pieds au
## sol), l'oriente de `rot_y` degrés, et lui donne une collision凸e (boîte
## ajustée sur le mesh). Retourne la racine instanciée.
func _place_furniture(parent: Node, glb_path: String, pos: Vector3, rot_y := 0.0,
		p_scale := 1.0) -> Node3D:
	var packed: PackedScene = load(glb_path)
	if packed == null:
		push_warning("MapBase: GLB introuvable %s" % glb_path)
		return null
	var n: Node3D = packed.instantiate()
	n.name = glb_path.get_file().get_basename()
	parent.add_child(n)
	n.position = pos
	n.rotation.y = deg_to_rad(rot_y)
	n.scale = Vector3.ONE * p_scale
	_add_box_collision(n)
	return n


## Ajoute un StaticBody3D + CollisionShape3D (boîte) ajustés sur l'enveloppe
## des MeshInstance3D descendants de `n`. Collision simple = rapide sur Quest 2.
## Calcule UNIQUEMENT avec transform() et mesh.get_aabb() — pas d'accès à
## global_transform() (le nœud n'est pas encore dans l'arbre quand build() tourne).
func _add_box_collision(n: Node3D) -> void:
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	var found := false
	for mi in _collect_meshes(n):
		if mi.mesh == null:
			continue
		# AABB du mesh dans l'espace local du mesh
		var aabb: AABB = mi.mesh.get_aabb()
		var local: Transform3D = mi.transform
		for cx in [aabb.position.x, aabb.position.x + aabb.size.x]:
			for cy in [aabb.position.y, aabb.position.y + aabb.size.y]:
				for cz in [aabb.position.z, aabb.position.z + aabb.size.z]:
					var corner_local := Vector3(cx, cy, cz)
					# Applique la transform locale du mesh (scale/rotation/position
					# par rapport à n), sans toucher à global_transform.
					var p := local * corner_local
					mn = Vector3(minf(mn.x, p.x), minf(mn.y, p.y), minf(mn.z, p.z))
					mx = Vector3(maxf(mx.x, p.x), maxf(mx.y, p.y), maxf(mx.z, p.z))
					found = true
	if not found:
		return
	var body := StaticBody3D.new()
	body.name = "Collision"
	n.add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = mx - mn
	cs.shape = bs
	cs.position = (mn + mx) * 0.5
	body.add_child(cs)


func _collect_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		out.append_array(_collect_meshes(c))
	return out


# ---------------------------------------------------------------------------
# Conteneurs interactifs (tiroir / placard) — boîtes primitives, pas de GLB
# ---------------------------------------------------------------------------

## Crée un conteneur à `slot_pos` (son origine = position fermée). `front_mat`
## teinte la face ; `lock_type` ajoute un verrou (clé / force). Retourne le
## conteneur prêt à recevoir un front_mesh décoré par l'appelant.
func _make_container(parent: Node, name: String, cmode: InteractiveContainer.Mode,
		slot_pos: Vector3, axis: Vector3, dist: float, angle := 115.0,
		lock_type: InteractiveContainer.LockType = InteractiveContainer.LockType.NONE,
		front_size := Vector3(0.8, 0.2, 0.04), front_mat: Material = null) -> InteractiveContainer:
	var c := InteractiveContainer.new(cmode, axis, dist, angle, lock_type)
	c.name = name
	c.position = slot_pos
	parent.add_child(c)
	c.front_mesh = _box(c, "Front", front_size, Vector3.ZERO, front_mat)
	c._mat_normal = front_mat
	var hover := StandardMaterial3D.new()
	hover.albedo_color = Color(0.45, 0.75, 0.7)
	hover.emission_enabled = true
	hover.emission = Color(0.2, 0.6, 0.55)
	hover.emission_energy_multiplier = 0.5
	c._mat_hover = hover
	# Zone d'interaction (Area3D) un peu plus grande que le front
	c.area = Area3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(maxf(front_size.x, 0.5) + 0.15, maxf(front_size.y, 0.3) + 0.2, 0.5)
	cs.shape = bs
	c.area.add_child(cs)
	c.add_child(c.area)
	containers.append(c)
	return c


func _box(parent: Node, name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = _unit_box
	mi.scale = size
	mi.position = pos
	if mat != null:
		mi.material_override = mat
	parent.add_child(mi)
	return mi


## GDD §5.6 : une clé cachée par conteneur verrouillé par clé.
func _build_keys(spots: Array[Vector3]) -> void:
	for c in containers:
		if c.lock_type == InteractiveContainer.LockType.KEY:
			var key := KeyObject.new()
			key.name = "Key_%s" % c.name
			key.target_container = c
			c.required_key = key
			add_child(key)
			key.position = spots.pick_random()
			key.position.y += 0.06


# ---------------------------------------------------------------------------
# Folie : dérive des matériaux + grésillement des lumières
# ---------------------------------------------------------------------------

## Enregistre un matériau qui glisse calm→sick avec la folie.
func _reg_breather(mat: StandardMaterial3D, calm: Color, sick: Color) -> void:
	_breathers.append({"mat": mat, "calm": calm, "sick": sick})


## Enregistre une lumière qui grésille quand ça va mal.
func _reg_flicker(light: OmniLight3D, base_energy: float) -> void:
	_flicker_lights.append({"light": light, "base": base_energy})


## Appelé chaque frame par main.gd avec t ∈ [0, 1].
func set_insanity(t: float) -> void:
	_insanity = t
	for b in _breathers:
		(b["mat"] as StandardMaterial3D).albedo_color = (b["calm"] as Color).lerp(b["sick"] as Color, t)


func _process(_delta: float) -> void:
	if _insanity <= 0.55:
		return
	var jitter := sin(Time.get_ticks_msec() / 37.0) * sin(Time.get_ticks_msec() / 91.0)
	for f in _flicker_lights:
		var l: OmniLight3D = f["light"]
		if is_instance_valid(l):
			l.light_energy = (f["base"] as float) * (1.0 + jitter * 0.35 * _insanity)


# ---------------------------------------------------------------------------
# Dose (pilule) — spawn / clear / reveal. Même logique qu'apartment.gd.
# ---------------------------------------------------------------------------

func get_dose() -> Dose:
	return _dose


## La sous-classe appelle ça APRÈS avoir rempli _spawn_spots.
func _register_spawn_spots() -> void:
	pass


func spawn_dose() -> void:
	clear_dose()
	if _spawn_spots.is_empty():
		push_warning("MapBase: aucun spot de dose enregistré")
		return
	var spot: Dictionary = _spawn_spots.pick_random()
	_dose = Dose.new()
	_dose.name = "Dose"
	if spot.get("floor", false):
		add_child(_dose)
		# Les spots au sol portent leur propre centre de pièce : ne pas tirer
		# une position autour de l'origine de la map (qui changeait de pièce).
		var center: Vector3 = spot["pos"]
		_dose.position = center + Vector3(randf_range(-0.35, 0.35),
			0.09, randf_range(-0.35, 0.35))
	elif spot["container"] != null:
		var c: InteractiveContainer = spot["container"]
		c.dose = _dose
		if c.mode == InteractiveContainer.Mode.SLIDE:
			c.add_child(_dose)
			_dose.position = c.content_offset
		else:
			add_child(_dose)
			_dose.position = spot["pos"]
		_dose.visible = false
		_dose.monitoring = false
		_dose.monitorable = false
	else:
		add_child(_dose)
		_dose.position = spot["pos"]


func clear_dose() -> void:
	if is_instance_valid(_dose):
		_dose.queue_free()
	_dose = null
	for c in containers:
		c.dose = null


func reset_containers() -> void:
	clear_dose()
	for c in containers:
		c.close_now()
