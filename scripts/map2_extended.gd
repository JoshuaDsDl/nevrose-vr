class_name Map2Extended
extends MapBase
## Appartement : salon, cuisine, couloir, chambre, SDB, dressing, garage et garage à voiture.
##
## scenes/map2_extended.tscn est la SEULE source de géométrie et de mobilier.
## Ce script ajoute uniquement le gameplay : conteneurs alignés sur les meubles,
## clés, mimics et points d'apparition de la dose, calculés depuis les enveloppes réelles.

const SCENE_SHELL := "res://scenes/map2_extended.tscn"
const FOOD := "res://assets/kenney/food/"

# Dimensions de l'appartement (clamp de déplacement dans main.gd)
const EXT_W := 16.4
const EXT_D := 13.6

# Meubles dont le volume bloque le joueur (collisions dérivées de la scène)
const FURNITURE_COLLISIONS := [
	"Shell/table", "Shell/chair", "Shell/chair2", "Shell/chair3", "Shell/chair4",
	"Shell/kitchenFridge", "Shell/sideTableDrawers", "Shell/loungeSofa",
	"Shell/kitchenStove", "Shell/kitchenCabinetDrawer",
	"Shell/kitchenCabinetCornerInner", "Shell/kitchenSink", "Shell/trashcan",
	"Shell/ExtensionEst/Couloir/PorteManteau",
	"Shell/ExtensionEst/Garage/LaveLinge", "Shell/ExtensionEst/Garage/Etabli",
	"Shell/ExtensionEst/Garage/Tabouret", "Shell/ExtensionEst/Garage/EtagereGarage",
	"Shell/ExtensionEst/Garage/Carton1", "Shell/ExtensionEst/Garage/Carton2",
	"Shell/ExtensionEst/Garage/Carton3", "Shell/ExtensionEst/Garage/Poubelle",
	"Shell/ExtensionEst/Garage/CartonStockage",
	"Shell/ExtensionEst/Chambre/LitDouble", "Shell/ExtensionEst/Chambre/TableNuit",
	"Shell/ExtensionEst/Chambre/Bureau", "Shell/ExtensionEst/Chambre/ChaiseBureau",
	"Shell/ExtensionEst/Chambre/EtagereChambre", "Shell/ExtensionEst/SDB/Baignoire",
	"Shell/ExtensionEst/WC", "Shell/ExtensionEst/SDB/Lavabo",
	"Shell/ExtensionEst/SDB/MeubleSDB",
	"Shell/ExtensionEst/Dressing/Armoire1", "Shell/ExtensionEst/Dressing/Armoire2",
	"Shell/ExtensionEst/Dressing/PorteManteauDressing",
	"Shell/ExtensionEst/Dressing/CartonDressing",
	"Shell/ExtensionEst/Voiture",
]

# Surfaces où la dose peut apparaître, et où une clé peut se trouver
# Surfaces où l'on peut poser une pilule à portée de main (pas le milieu d'un lit, ni un lavabo
# collé au mur : la pilule y serait hors d'atteinte, vérifié par tests/test_pills.gd).
const SURFACES := [
	"Shell/kitchenCabinetDrawer", "Shell/table",
	"Shell/sideTableDrawers",
]

# Points au sol libres (hors meubles, rien au-dessus : vérifié par tests/test_pills.gd).
# Le centre du salon n'en fait plus partie : il tombe sous la table.
const FLOOR_SPOTS := [
	Vector3(-2.2, 0.0, -0.8), Vector3(2.4, 0.0, 0.4),
	Vector3(8.0, 0.0, 2.2), Vector3(7.7, 0.0, 6.2), Vector3(6.3, 0.0, -0.6),
]


func _init() -> void:
	room_w = EXT_W
	room_d = EXT_D
	room_h = 2.7


func build() -> void:
	_instance_shell()
	_build_collision_geometry()
	# Nœuds de compatibilité pour le smoke test (le décor est dans le .tscn)
	var kitchen := Node3D.new()
	kitchen.name = "Kitchen"
	add_child(kitchen)
	var living := Node3D.new()
	living.name = "LivingRoom"
	add_child(living)
	_build_extension()
	_add_threshold_floor()
	_paint_car()
	_build_existing_gameplay()
	_register_spawn_spots()
	_place_mimics()
	_register_ambience()
	_hide_decorations()


## Les murs respirent et les lumières grésillent avec la folie (GDD §5.2).
func _register_ambience() -> void:
	var wall := get_node_or_null("Shell/ExtensionEst/MurChambreOuest") as MeshInstance3D
	if wall != null and wall.material_override is StandardMaterial3D:
		var mat := wall.material_override as StandardMaterial3D
		_reg_breather(mat, mat.albedo_color, Color(0.42, 0.34, 0.33))
	_register_lights(get_node("Shell"))
	_strip_shadows(get_node("Shell"))


## Quest 2 (mode Compatibilité) : une lumière à ombres redessine toute la scène ; trois ombres
## suffisaient à faire chuter les images par seconde. L'ambiance reste, les ombres portées partent.
func _strip_shadows(node: Node) -> void:
	if node is Light3D:
		(node as Light3D).shadow_enabled = false
	for child in node.get_children():
		_strip_shadows(child)


func _register_lights(node: Node) -> void:
	if node is OmniLight3D:
		_reg_flicker(node as OmniLight3D, (node as OmniLight3D).light_energy)
	for child in node.get_children():
		_register_lights(child)


# ---------------------------------------------------------------------------
# Coquille et collisions
# ---------------------------------------------------------------------------
func _instance_shell() -> void:
	var packed: PackedScene = load(SCENE_SHELL)
	if packed == null:
		push_error("Map2Extended: coquille introuvable %s" % SCENE_SHELL)
		return
	var shell: Node3D = packed.instantiate()
	shell.name = "Shell"
	add_child(shell)


## Collisions invisibles dérivées de la scène : murs, linteaux, meubles.
func _build_collision_geometry() -> void:
	for path in ["Shell/ExtensionEst", "Shell/Jardin"]:
		var root := get_node_or_null(path)
		if root != null:
			_add_wall_collisions(root)
	for path in FURNITURE_COLLISIONS:
		var node := get_node_or_null(path) as Node3D
		if node != null:
			_add_world_collision(node)


func _add_wall_collisions(node: Node) -> void:
	if node is MeshInstance3D:
		var label := String(node.name).to_lower()
		if label.begins_with("mur") or label.begins_with("linteau") or label.begins_with("cloture"):
			_add_world_collision(node as Node3D)
	for child in node.get_children():
		_add_wall_collisions(child)


func _add_world_collision(node: Node3D) -> void:
	var bounds := _world_bounds(node)
	var body := StaticBody3D.new()
	body.name = "PlayerCollision"
	body.collision_layer = 1
	body.collision_mask = 1
	body.position = bounds.get_center()
	add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = bounds.size
	collision.shape = shape
	body.add_child(collision)


## Enveloppe monde d'un meuble édité, à partir de ses maillages.
func _world_bounds(node: Node3D) -> AABB:
	var minimum := Vector3(1e9, 1e9, 1e9)
	var maximum := Vector3(-1e9, -1e9, -1e9)
	var found := false
	for mi in _collect_meshes(node):
		var local_box := mi.mesh.get_aabb()
		var world_transform := mi.global_transform
		for x in [local_box.position.x, local_box.end.x]:
			for y in [local_box.position.y, local_box.end.y]:
				for z in [local_box.position.z, local_box.end.z]:
					var point: Vector3 = world_transform * Vector3(x, y, z)
					minimum = minimum.min(point)
					maximum = maximum.max(point)
					found = true
	return AABB(minimum, maximum - minimum) if found else AABB()


func _surface_point(support_path: String, height := 0.0) -> Vector3:
	var support := get_node_or_null(support_path) as Node3D
	if support == null:
		push_warning("Map2Extended: support introuvable " + support_path)
		return Vector3.ZERO
	var bounds := _world_bounds(support)
	var center := bounds.get_center()
	return Vector3(center.x, bounds.end.y + height, center.z)


# ---------------------------------------------------------------------------
# Conteneurs : une partie mobile réelle du GLB (tiroir, porte) devient interactive
# ---------------------------------------------------------------------------
func _container_part(support_path: String, part_name: String, cname: String,
		cmode: InteractiveContainer.Mode, lock_type: InteractiveContainer.LockType,
		distance := 0.35, signed_angle := -105.0) -> InteractiveContainer:
	var support := get_node_or_null(support_path) as Node3D
	if support == null:
		push_error("Map2Extended: support introuvable " + support_path)
		return null
	var part := _find_named_mesh(support, part_name)
	if part == null:
		push_error("Map2Extended: partie mobile introuvable %s dans %s" % [part_name, support_path])
		return null

	var normal: Vector3 = part.global_transform.basis.z
	normal.y = 0.0
	normal = normal.normalized()
	var axis := normal if cmode == InteractiveContainer.Mode.SLIDE else Vector3.ZERO
	var c := InteractiveContainer.new(cmode, axis, distance, signed_angle, lock_type)
	c.name = cname
	c.position = part.global_position
	c.rotation = part.global_rotation
	c.scale = part.global_transform.basis.get_scale()
	add_child(c)
	part.reparent(c, true)
	c.front_mesh = part

	var hover := StandardMaterial3D.new()
	hover.albedo_color = Color(0.45, 0.75, 0.7, 0.25)
	hover.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hover.emission_enabled = true
	hover.emission = Color(0.2, 0.6, 0.55)
	hover.emission_energy_multiplier = 0.35
	c._mat_hover = hover

	var local_bounds := _bounds_in_container(part, c)
	if cmode == InteractiveContainer.Mode.SLIDE:
		# Ne jamais extraire complètement le tiroir de sa carcasse.
		c.open_distance = minf(distance, local_bounds.size.z * c.scale.z * 0.75)
	c.content_offset = local_bounds.get_center() + (
		Vector3(0.0, 0.08, 0.0) if cmode == InteractiveContainer.Mode.SLIDE
		else Vector3(0.0, 0.0, -0.15)
	)
	c.area = Area3D.new()
	c.area.name = "area"
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = local_bounds.size + Vector3(0.06, 0.06, 0.12)
	collision.shape = shape
	collision.position = local_bounds.get_center()
	c.area.add_child(collision)
	c.add_child(c.area)
	containers.append(c)
	return c


func _find_named_mesh(node: Node, part_name: String) -> MeshInstance3D:
	if node is MeshInstance3D and String(node.name) == part_name:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_named_mesh(child, part_name)
		if found != null:
			return found
	return null


func _bounds_in_container(part: Node3D, container: Node3D) -> AABB:
	var minimum := Vector3(1e9, 1e9, 1e9)
	var maximum := Vector3(-1e9, -1e9, -1e9)
	var stack: Array[Node] = [part]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D and current.mesh != null:
			var relative: Transform3D = container.global_transform.affine_inverse() * (current as MeshInstance3D).global_transform
			var local_box: AABB = current.mesh.get_aabb()
			for x in [local_box.position.x, local_box.end.x]:
				for y in [local_box.position.y, local_box.end.y]:
					for z in [local_box.position.z, local_box.end.z]:
						var point: Vector3 = relative * Vector3(x, y, z)
						minimum = minimum.min(point)
						maximum = maximum.max(point)
		for child in current.get_children():
			stack.append(child)
	return AABB(minimum, maximum - minimum)


## Conteneurs de la pièce étendue (chambre, dressing, garage, SDB) et de la cuisine.
func _build_extension() -> void:
	_container_part("Shell/ExtensionEst/Garage/Etabli", "drawer", "GarageDrawer",
		InteractiveContainer.Mode.SLIDE, InteractiveContainer.LockType.NONE, 0.42)
	_container_part("Shell/ExtensionEst/Chambre/TableNuit", "drawer", "NightstandDrawer",
		InteractiveContainer.Mode.SLIDE, InteractiveContainer.LockType.NONE, 0.35)
	_container_part("Shell/ExtensionEst/Chambre/EtagereChambre", "doorLeft", "BookcaseDoor",
		InteractiveContainer.Mode.ROTATE, InteractiveContainer.LockType.NONE, 0.0, -105.0)
	_container_part("Shell/ExtensionEst/SDB/MeubleSDB", "drawerTop", "SDBCabinet",
		InteractiveContainer.Mode.SLIDE, InteractiveContainer.LockType.NONE, 0.30)
	_container_part("Shell/ExtensionEst/Dressing/Armoire1", "doorLeft", "DresserDrawer",
		InteractiveContainer.Mode.ROTATE, InteractiveContainer.LockType.NONE, 0.0, -105.0)


## Sol continu sous tout l'appartement : les seuils entre deux pièces n'en avaient pas,
## le joueur avait l'impression de marcher dans le vide. Posé sous les sols existants.
func _add_threshold_floor() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "SolSeuils"
	var box := BoxMesh.new()
	box.size = Vector3(19.0, 0.1, 13.0)
	mi.mesh = box
	mi.position = Vector3(5.15, -0.07, 1.45)
	var source := get_node_or_null("Floor/Mesh") as MeshInstance3D
	if source != null:
		mi.material_override = source.get_active_material(0)
	add_child(mi)


## Couleurs de la voiture du garage : carrosserie rouge, pneus noirs.
func _paint_car() -> void:
	var car := get_node_or_null("Shell/ExtensionEst/Voiture")
	if car == null:
		return
	var paint := _solid_material(Color(0.62, 0.07, 0.06))
	var tyre := _solid_material(Color(0.05, 0.05, 0.05))
	for mi in _collect_meshes(car):
		if mi.name.begins_with("body") or mi.name.begins_with("spoiler"):
			mi.material_override = paint
		elif mi.name.begins_with("wheel"):
			mi.material_override = tyre


func _solid_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.5
	return mat


## Conteneurs du salon et de la cuisine.
func _build_existing_gameplay() -> void:
	_container_part("Shell/kitchenCabinetDrawer", "drawer", "KitchenDrawerKey",
		InteractiveContainer.Mode.SLIDE, InteractiveContainer.LockType.NONE, 0.42)
	_container_part("Shell/kitchenFridge", "doorFridge", "FridgeDoor",
		InteractiveContainer.Mode.ROTATE, InteractiveContainer.LockType.NONE, 0.0, -105.0)
	_container_part("Shell/sideTableDrawers", "drawerLeft", "ClosetDoor",
		InteractiveContainer.Mode.SLIDE, InteractiveContainer.LockType.NONE, 0.35)


# ---------------------------------------------------------------------------
# Mimics : deux tasses qui ne sont pas des tasses (GDD §5.3)
# ---------------------------------------------------------------------------
func _place_mimics() -> void:
	_add_mimic("MugMimic", _surface_point("Shell/table", 0.02) + Vector3(0.15, 0.0, -0.15), 0.0)
	_add_mimic("SideTableMimic", _surface_point("Shell/sideTableDrawers", 0.02) + Vector3(-0.2, 0.0, 0.0), 30.0)


func _add_mimic(mimic_name: String, pos: Vector3, rot_y: float) -> void:
	var fake := Mimic.new()
	fake.name = mimic_name
	add_child(fake)
	fake.position = pos
	_place_furniture(fake, FOOD + "cup-tea.glb", Vector3.ZERO, rot_y, 1.0)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.16, 0.16, 0.16)
	collision.shape = shape
	collision.position = Vector3(0, 0.06, 0)
	fake.add_child(collision)
	mimics.append(fake)


# ---------------------------------------------------------------------------
# Apparition de la dose et des clés
# ---------------------------------------------------------------------------
func _register_spawn_spots() -> void:
	# Pilules toujours à vue (surface ou sol) : un faisceau lumineux les signale.
	# Plus de tiroirs verrouillés ni de clés cachées.
	for path in SURFACES:
		_spawn_spots.append({"pos": _surface_point(path, 0.09), "container": null})
	for pos in FLOOR_SPOTS:
		_spawn_spots.append({"pos": pos, "container": null, "floor": true})
	# Et dans les rangements : tiroir de cuisine, frigo, commode du salon (lueur à travers la porte).
	# Associés par nom : l'ordre de création des conteneurs ne correspond pas à cette liste.
	var holders := {"KitchenDrawerKey": "Shell/kitchenCabinetDrawer", "FridgeDoor": "Shell/kitchenFridge", "ClosetDoor": "Shell/sideTableDrawers"}
	for cname in holders:
		var c := _container_named(cname)
		var holder := get_node_or_null(holders[cname]) as Node3D
		if c == null or holder == null:
			continue
		_spawn_spots.append({"pos": _stored_spot(c, _world_bounds(holder)), "container": c})


func _container_named(cname: String) -> InteractiveContainer:
	for c in containers:
		if String(c.name) == cname:
			return c
	return null


## Où se trouve la pilule dans un rangement. Tiroir : dans le tiroir (il glisse avec lui).
## Porte : dans la carcasse, juste derrière la face avant, visible quand la porte s'ouvre.
func _stored_spot(c: InteractiveContainer, b: AABB) -> Vector3:
	if c.mode == InteractiveContainer.Mode.SLIDE:
		return c.transform * c.content_offset
	var center := b.get_center()
	var front := Vector3(c.basis.z.x, 0.0, c.basis.z.z).normalized()
	var toward_door := Vector3(c.global_position.x - center.x, 0.0, c.global_position.z - center.z)
	if front.dot(toward_door) < 0.0:
		front = -front
	var reach := absf(front.x) * b.size.x * 0.5 + absf(front.z) * b.size.z * 0.5
	return Vector3(center.x, b.position.y + b.size.y * 0.45, center.z) + front * maxf(reach - 0.25, 0.0)


func _key_spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for path in SURFACES:
		spots.append(_surface_point(path))
	spots.append(Vector3(8.0, 0.0, 2.2)) # sol du couloir, libre
	return spots


# ---------------------------------------------------------------------------
# Décorations de la boutique : masquées tant qu'elles ne sont pas achetées
# ---------------------------------------------------------------------------
func _hide_decorations() -> void:
	DecorCatalog.apply(self, [])


## Montre les décorations possédées (appelé par main.gd avec le profil).
func apply_decorations(owned: Array) -> void:
	DecorCatalog.apply(self, owned)
