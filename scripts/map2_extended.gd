class_name Map2Extended
extends MapBase
## Map unique : salon, cuisine, couloir, garage, chambre, SDB et dressing.
##
## scenes/map2_extended.tscn est la SEULE source de géométrie et de mobilier.
## Ce script ajoute uniquement le gameplay : conteneurs alignés sur les meubles,
## clés, mimics et spawns de dose calculés depuis leurs enveloppes réelles.

const SCENE_SHELL := "res://scenes/map2_extended.tscn"
const FURN := "res://assets/kenney/furniture/"
const FOOD := "res://assets/kenney/food/"
const QUAT := "res://assets/quaternius/"

## Facteur d'échelle global pour les modèles Quaternius (décimètres → mètres).
const QUATERNIUS_SCALE := 0.5

## Échelles par meuble pour atteindre la taille RÉELLE (mesurées sur les AABB
## natives, cf. tools/measure_glb.gd). Les GLB Kenney sont natifs ~0,4× la
## réalité, MAIS les grands modèles (lit, bibliothèque, douche, baignoire…)
## sont déjà larges nativement et prennent un facteur plus faible — exactement
## comme le salon dans le .tscn (canapé ×2, tapis rond ×1,75, poubelle ×2,25).
const FURN_SCALE := {
	"tableCross.glb": 2.5, "washer.glb": 1.8, "bookcaseOpen.glb": 2.2,
	"bookcaseClosed.glb": 2.2, "cardboardBoxClosed.glb": 1.7,
	"cardboardBoxOpen.glb": 1.7, "trashcan.glb": 1.3,
	"coatRackStanding.glb": 2.3, "rugDoormat.glb": 1.5,
	"bedDouble.glb": 1.6, "cabinetBedDrawerTable.glb": 1.9,
	"cabinetBedDrawer.glb": 1.9, "desk.glb": 1.9, "chairDesk.glb": 1.5,
	"lampRoundTable.glb": 1.5, "rugRectangle.glb": 1.2, "pottedPlant.glb": 1.5,
	"pillow.glb": 1.7, "pillowLong.glb": 1.7, "toilet.glb": 1.7,
	"bathroomSinkSquare.glb": 1.4, "bathroomCabinet.glb": 1.6,
	"bathroomMirror.glb": 1.6, "shower.glb": 0.9,
	"bathroomCabinetDrawer.glb": 1.5, "bathtub.glb": 1.45, "coatRack.glb": 1.2,
}

# Matériaux existants (repris de l'ancienne map 2 living)
var _mat_bois: StandardMaterial3D
var _mat_meuble: StandardMaterial3D
var _mat_metal: StandardMaterial3D
var _mat_tissu: StandardMaterial3D
var _mat_cadre: StandardMaterial3D
var _mat_nourriture: StandardMaterial3D

# Nouveaux matériaux pour l'extension
var _mat_beton: StandardMaterial3D
var _mat_carrelage_blanc: StandardMaterial3D
var _mat_moquette: StandardMaterial3D
var _mat_mur_garage: StandardMaterial3D
var _mat_mur_sdb: StandardMaterial3D
var _mat_porte: StandardMaterial3D

const COUNTER_Y := 0.48

# Dimensions de la map étendue (pour le clamp joueur dans main.gd)
const EXT_W := 16.4  # -4.075 → 12.300 (SDB agrandie)
const EXT_D := 13.6  # -3.6 → +6.6

# Origines des nouvelles pièces (centre de chaque pièce)
const CORRIDOR_X := 4.675   # x = 4.075 → 5.275
const CORRIDOR_Z := 0.0     # z = -3 → +3
const GARAGE_X := 7.275     # x = 5.275 → 9.275
const GARAGE_Z := -0.5      # z = -3 → +2
const CHAMBRE_X := 6.775    # x = 5.275 → 8.275
const CHAMBRE_Z := 4.0      # z = +2 → +6
const DRESSING_X := 9.275   # x = 8.275 → 10.275
const DRESSING_Z := 3.5     # z = +2 → +5
const SDB_X := 6.525        # x = 5.275 → 7.775
const SDB_Z := 3.5          # z = +2 → +5


func _init() -> void:
	room_w = EXT_W
	room_d = EXT_D
	room_h = 2.7


func build() -> void:
	_make_materials()
	_instance_shell()
	_build_collision_geometry()
	# Nœuds de compatibilité pour le smoke test (décor déjà dans le .tscn)
	var kitchen := Node3D.new()
	kitchen.name = "Kitchen"
	add_child(kitchen)
	var living := Node3D.new()
	living.name = "LivingRoom"
	add_child(living)
	_build_extension()
	_build_existing_gameplay()
	_register_spawn_spots()
	_build_keys(_key_spots())
	_place_mimics()


# ---------------------------------------------------------------------------
# Matériaux
# ---------------------------------------------------------------------------
func _make_materials() -> void:
	_mat_bois = _new_mat(Color(0.28, 0.19, 0.13))
	_mat_meuble = _new_mat(Color(0.55, 0.52, 0.47))
	_mat_metal = _new_mat(Color(0.52, 0.53, 0.55))
	_mat_tissu = _new_mat(Color(0.42, 0.26, 0.22))
	_mat_cadre = _new_mat(Color(0.82, 0.78, 0.72))
	_mat_nourriture = _new_mat(Color(0.72, 0.55, 0.35))
	# Nouveaux matériaux extension
	_mat_beton = _new_mat(Color(0.5, 0.5, 0.5))
	_mat_carrelage_blanc = _new_mat(Color(0.9, 0.9, 0.88))
	_mat_moquette = _new_mat(Color(0.8, 0.7, 0.65))
	_mat_mur_garage = _new_mat(Color(0.6, 0.6, 0.6))
	_mat_mur_sdb = _new_mat(Color(0.7, 0.8, 0.85))
	_mat_porte = _new_mat(Color(0.4, 0.28, 0.18))
	_reg_breather(_mat_meuble, Color(0.55, 0.52, 0.47), Color(0.42, 0.5, 0.4))
	_reg_breather(_mat_tissu, Color(0.42, 0.26, 0.22), Color(0.35, 0.18, 0.15))
	_reg_breather(_mat_bois, Color(0.28, 0.19, 0.13), Color(0.22, 0.16, 0.11))


func _new_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


# ---------------------------------------------------------------------------
# Coquille
# ---------------------------------------------------------------------------
func _instance_shell() -> void:
	var packed: PackedScene = load(SCENE_SHELL)
	if packed == null:
		push_error("Map2Extended: coquille introuvable %s" % SCENE_SHELL)
		return
	var shell: Node3D = packed.instantiate()
	shell.name = "Shell"
	add_child(shell)


# ---------------------------------------------------------------------------
# Helpers Quaternius : charge un FBX, applique l'échelle, le pose.
# ---------------------------------------------------------------------------

## Instancie un FBX Quaternius, applique QUATERNIUS_SCALE, l'ajoute sous
## `parent`, le pose à `pos` (pieds au sol), l'oriente de `rot_y` degrés,
## et lui donne une collision box ajustée. Retourne la racine instanciée.
func _place_quaternius(parent: Node, fbx_name: String, pos: Vector3, rot_y := 0.0) -> Node3D:
	var packed: PackedScene = load(QUAT + fbx_name)
	if packed == null:
		push_warning("Map2Extended: FBX Quaternius introuvable %s" % fbx_name)
		return null
	var n: Node3D = packed.instantiate()
	n.name = fbx_name.get_basename()
	n.scale = Vector3.ONE * QUATERNIUS_SCALE
	parent.add_child(n)
	n.position = pos
	n.rotation.y = deg_to_rad(rot_y)
	_add_box_collision(n)
	return n


# ---------------------------------------------------------------------------
# EXTENSION : couloir + 4 nouvelles pièces
# ---------------------------------------------------------------------------
## Collisions invisibles dérivées de la scène éditée, sans dupliquer de visuel.
func _build_collision_geometry() -> void:
	for path in ["Shell/ExtensionEst", "Shell/Jardin"]:
		var root := get_node_or_null(path)
		if root != null:
			_add_wall_collisions(root)

	var furniture := [
		"Shell/table", "Shell/chair", "Shell/chair2", "Shell/chair3", "Shell/chair4",
		"Shell/kitchenFridge", "Shell/sideTableDrawers", "Shell/loungeSofa",
		"Shell/kitchenStove", "Shell/kitchenCabinetDrawer",
		"Shell/kitchenCabinetCornerInner", "Shell/kitchenSink", "Shell/trashcan",
		"Shell/ExtensionEst/Couloir/PorteManteau",
		"Shell/ExtensionEst/Garage/LaveLinge", "Shell/ExtensionEst/Garage/Etabli",
		"Shell/ExtensionEst/Garage/Tabouret", "Shell/ExtensionEst/Garage/EtagereGarage",
		"Shell/ExtensionEst/Garage/Carton1", "Shell/ExtensionEst/Garage/Carton2",
		"Shell/ExtensionEst/Garage/Carton3", "Shell/ExtensionEst/Garage/Poubelle",
		"Shell/ExtensionEst/Garage/TableStockage", "Shell/ExtensionEst/Garage/CartonStockage",
		"Shell/ExtensionEst/Chambre/LitDouble", "Shell/ExtensionEst/Chambre/TableNuit",
		"Shell/ExtensionEst/Chambre/Bureau", "Shell/ExtensionEst/Chambre/ChaiseBureau",
		"Shell/ExtensionEst/Chambre/EtagereChambre", "Shell/ExtensionEst/SDB/Baignoire",
		"Shell/ExtensionEst/SDB/WC", "Shell/ExtensionEst/SDB/Lavabo",
		"Shell/ExtensionEst/SDB/MeubleSDB",
		"Shell/ExtensionEst/Dressing/Armoire1", "Shell/ExtensionEst/Dressing/Armoire2",
		"Shell/ExtensionEst/Dressing/PorteManteauDressing",
		"Shell/ExtensionEst/Dressing/CartonDressing",
	]
	for path in furniture:
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


## Enveloppe monde d'un meuble édité. Sert à aligner le gameplay sur la scène,
## même si ses assets sont déplacés ou redimensionnés plus tard dans l'éditeur.
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
					minimum = Vector3(minf(minimum.x, point.x), minf(minimum.y, point.y), minf(minimum.z, point.z))
					maximum = Vector3(maxf(maximum.x, point.x), maxf(maximum.y, point.y), maxf(maximum.z, point.z))
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


## Utilise une vraie partie mobile GLB : pivot, matériaux et zone d'interaction.
func _container_part(support_path: String, part_name: String, cname: String,
		mode: InteractiveContainer.Mode, lock_type: InteractiveContainer.LockType,
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
	var axis := normal if mode == InteractiveContainer.Mode.SLIDE else Vector3.ZERO
	var c := InteractiveContainer.new(mode, axis, distance, signed_angle, lock_type)
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
	if mode == InteractiveContainer.Mode.SLIDE:
		# Ne jamais extraire complètement le tiroir de sa carcasse.
		c.open_distance = minf(distance, local_bounds.size.z * c.scale.z * 0.75)
	c.content_offset = local_bounds.get_center() + (
		Vector3(0.0, 0.08, 0.0) if mode == InteractiveContainer.Mode.SLIDE
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
						minimum = Vector3(minf(minimum.x, point.x), minf(minimum.y, point.y), minf(minimum.z, point.z))
						maximum = Vector3(maxf(maximum.x, point.x), maxf(maximum.y, point.y), maxf(maximum.z, point.z))
		for child in current.get_children():
			stack.append(child)
	return AABB(minimum, maximum - minimum)


## Place la façade interactive sur la face avant réelle du meuble Kenney.
## Le +Z local des assets correspond à leur face avant, y compris après rotation.
func _container_front(support_path: String, cname: String,
		mode: InteractiveContainer.Mode, lock_type: InteractiveContainer.LockType,
		front_size: Vector3, mat: Material, height_ratio := 0.5,
		slide_distance := 0.35) -> InteractiveContainer:
	var support := get_node_or_null(support_path) as Node3D
	if support == null:
		push_error("Map2Extended: conteneur sans support " + support_path)
		return null
	var bounds := _world_bounds(support)
	var normal: Vector3 = support.global_transform.basis.z
	normal.y = 0.0
	normal = normal.normalized()
	var depth := absf(normal.x) * bounds.size.x + absf(normal.z) * bounds.size.z
	var pos := bounds.get_center() + normal * (depth * 0.5 + 0.02)
	pos.y = bounds.position.y + bounds.size.y * height_ratio
	var axis := normal if mode == InteractiveContainer.Mode.SLIDE else Vector3.ZERO
	var c := _make_container(self, cname, mode, pos, axis, slide_distance, 115.0,
		lock_type, front_size, mat)
	c.rotation.y = atan2(normal.x, normal.z)
	c._closed_rot_y = c.rotation.y
	return c


## La géométrie des nouvelles pièces vit uniquement dans map2_extended.tscn.
## Cette fonction ne rajoute que le gameplay, jamais une seconde extension.
func _build_extension() -> void:
	_container_part("Shell/ExtensionEst/Garage/Etabli", "drawer", "GarageDrawer",
		InteractiveContainer.Mode.SLIDE, InteractiveContainer.LockType.NONE, 0.42)
	_container_part("Shell/ExtensionEst/Chambre/TableNuit", "drawer", "NightstandDrawer",
		InteractiveContainer.Mode.SLIDE, InteractiveContainer.LockType.KEY, 0.35)
	_container_part("Shell/ExtensionEst/Chambre/EtagereChambre", "doorLeft", "BookcaseDoor",
		InteractiveContainer.Mode.ROTATE, InteractiveContainer.LockType.NONE, 0.0, -105.0)
	_container_part("Shell/ExtensionEst/SDB/MeubleSDB", "drawerTop", "SDBCabinet",
		InteractiveContainer.Mode.SLIDE, InteractiveContainer.LockType.KEY, 0.30)
	_container_part("Shell/ExtensionEst/Dressing/Armoire1", "doorLeft", "DresserDrawer",
		InteractiveContainer.Mode.ROTATE, InteractiveContainer.LockType.FORCEABLE, 0.0, -105.0)


# ---------------------------------------------------------------------------
# COULOIR (x = 4.075 → 5.275, z = -3 → +3, 1.2 × 6 m)
# ---------------------------------------------------------------------------
func _build_corridor(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Corridor"
	parent.add_child(root)

	# Mur Ouest du couloir (x = 4.075, prolongation du mur Est existant)
	_wall(root, "CorrWallW", Vector3(4.075, 1.35, 0), Vector3(0.15, 2.7, 6.0), _mat_meuble)

	# Mur Est du couloir (x = 5.275) avec 4 ouvertures de porte
	# Porte garage : z = -2, Porte chambre : z = +0.5, Porte sdb : z = +2.5, Porte dressing : z = +1.5
	_wall(root, "CorrWallE_N", Vector3(5.275, 1.35, -2.5), Vector3(0.15, 2.7, 1.0), _mat_meuble)
	_wall(root, "CorrWallE_M1", Vector3(5.275, 1.35, -0.5), Vector3(0.15, 2.7, 1.0), _mat_meuble)
	_wall(root, "CorrWallE_M2", Vector3(5.275, 1.35, 1.5), Vector3(0.15, 2.7, 1.0), _mat_meuble)
	_wall(root, "CorrWallE_S", Vector3(5.275, 1.35, 2.9), Vector3(0.15, 2.7, 0.2), _mat_meuble)
	# Lintaux au-dessus des portes
	_wall(root, "CorrLintel1", Vector3(5.275, 2.4, -1.5), Vector3(0.15, 0.6, 1.0), _mat_meuble)
	_wall(root, "CorrLintel2", Vector3(5.275, 2.4, 0.5), Vector3(0.15, 0.6, 1.0), _mat_meuble)
	_wall(root, "CorrLintel3", Vector3(5.275, 2.4, 2.5), Vector3(0.15, 0.6, 1.0), _mat_meuble)

	# Murs de jonction N/S
	_wall(root, "CorrWallN", Vector3(4.675, 1.35, -3.0), Vector3(1.2, 2.7, 0.15), _mat_meuble)
	_wall(root, "CorrWallS", Vector3(4.675, 1.35, 3.0), Vector3(1.2, 2.7, 0.15), _mat_meuble)

	# Sol
	_floor(root, "CorrFloor", Vector3(4.675, -0.05, 0), Vector3(1.2, 0.1, 6.0), _mat_bois)

	# Plafond
	_ceiling(root, "CorrCeiling", Vector3(4.675, 2.75, 0), Vector3(1.2, 0.1, 6.0), _mat_meuble)

	# Plinthes
	_plinthe(root, "CorrPlintheW", Vector3(4.08, 0.04, 0), Vector3(0.02, 0.08, 5.9))
	_plinthe(root, "CorrPlintheE", Vector3(5.27, 0.04, 0), Vector3(0.02, 0.08, 5.9))

	# Décor couloir (échelles réelles : décalés pour ne pas traverser les murs)
	_mob(root, "coatRackStanding.glb", Vector3(4.45, 0, -2.5), 90.0)
	_mob(root, "rugDoormat.glb", Vector3(4.675, 0, 0), 0.0)

	# Cadres photo
	_box(root, "CorrFrame1", Vector3(0.44, 0.56, 0.03), Vector3(4.15, 1.6, -1.0), _mat_cadre)
	_box(root, "CorrPhoto1", Vector3(0.36, 0.48, 0.035), Vector3(4.15, 1.6, -1.0), _new_mat(Color(0.3, 0.35, 0.42)))

	# Lumière couloir
	var clight := OmniLight3D.new()
	clight.name = "CorridorLight"
	clight.position = Vector3(4.675, 2.3, 0)
	clight.light_color = Color(0.95, 0.88, 0.75)
	clight.light_energy = 0.9
	clight.omni_range = 4.0
	clight.shadow_enabled = false
	root.add_child(clight)
	_reg_flicker(clight, 0.9)

	# Plafonnier
	_place_quaternius(root, "Light_Ceiling1.fbx", Vector3(4.675, 2.7, 0), 0.0)


# ---------------------------------------------------------------------------
# GARAGE (x = 5.275 → 9.275, z = -3 → +2, 4 × 5 m)
# ---------------------------------------------------------------------------
func _build_garage(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Garage"
	parent.add_child(root)

	# Murs garage
	_wall(root, "GarageWallN", Vector3(7.275, 1.35, -3.0), Vector3(4.0, 2.7, 0.15), _mat_mur_garage)
	_wall(root, "GarageWallE", Vector3(9.275, 1.35, -0.5), Vector3(0.15, 2.7, 5.0), _mat_mur_garage)
	_wall(root, "GarageWallS_W", Vector3(6.275, 1.35, 2.0), Vector3(2.0, 2.7, 0.15), _mat_mur_garage)
	_wall(root, "GarageWallS_E", Vector3(8.775, 1.35, 2.0), Vector3(1.0, 2.7, 0.15), _mat_mur_garage)
	# Mur Ouest = mur Est du couloir (déjà construit)

	# Sol béton
	_floor(root, "GarageFloor", Vector3(7.275, -0.05, -0.5), Vector3(4.0, 0.1, 5.0), _mat_beton)

	# Plafond
	_ceiling(root, "GarageCeiling", Vector3(7.275, 2.75, -0.5), Vector3(4.0, 0.1, 5.0), _mat_mur_garage)

	# Porte garage (grande ouverture côté Nord)
	# Montants + linteau
	_box(root, "GarageDoorFrameL", Vector3(0.1, 2.14, 0.1), Vector3(6.275, 1.07, -2.9), _mat_porte)
	_box(root, "GarageDoorFrameR", Vector3(0.1, 2.14, 0.1), Vector3(8.275, 1.07, -2.9), _mat_porte)
	_box(root, "GarageDoorLintel", Vector3(2.2, 0.1, 0.1), Vector3(7.275, 2.2, -2.9), _mat_porte)

	# Meubles garage
	_mob(root, "tableCross.glb", Vector3(6.5, 0, -1.5), 0.0)
	_mob(root, "washer.glb", Vector3(8.8, 0, -2.5), 180.0)
	_mob(root, "bookcaseOpen.glb", Vector3(9.0, 0, -0.5), -90.0)

	# Cartons
	_mob(root, "cardboardBoxClosed.glb", Vector3(5.8, 0, -2.5), 15.0)
	_mob(root, "cardboardBoxClosed.glb", Vector3(6.2, 0, -2.2), -10.0)
	_mob(root, "cardboardBoxOpen.glb", Vector3(5.9, 0, -1.8), 30.0)
	_mob(root, "cardboardBoxClosed.glb", Vector3(8.5, 0, 1.5), 45.0)
	_mob(root, "cardboardBoxOpen.glb", Vector3(8.0, 0, 1.3), -20.0)

	# Poubelle
	_mob(root, "trashcan.glb", Vector3(9.0, 0, 1.5), 0.0)

	# Pneus (cylindres)
	_tire(root, "Tire1", Vector3(5.8, 0.15, 0.5))
	_tire(root, "Tire2", Vector3(5.8, 0.15, 0.9))
	_tire(root, "Tire3", Vector3(5.8, 0.45, 0.7))

	# Lumière garage
	var glight := OmniLight3D.new()
	glight.name = "GarageLight"
	glight.position = Vector3(7.275, 2.3, -0.5)
	glight.light_color = Color(0.85, 0.82, 0.78)
	glight.light_energy = 0.8
	glight.omni_range = 5.0
	glight.shadow_enabled = false
	root.add_child(glight)
	_reg_flicker(glight, 0.8)

	# Conteneur : tiroir de l'établi (NON verrouillé — seul tiroir libre de la
	# map, le smoke test s'y accroche pour vérifier l'ouverture coulissante).
	# y = 0,65 : tiroir réel de l'établi à l'échelle ×2,5.
	_make_container(root, "GarageDrawer",
		InteractiveContainer.Mode.SLIDE,
		Vector3(6.5, 0.65, -1.35), Vector3.BACK, 0.42, 115.0,
		InteractiveContainer.LockType.NONE,
		Vector3(0.45, 0.16, 0.03), _mat_metal)


# ---------------------------------------------------------------------------
# CHAMBRE (x = 5.275 → 8.275, z = +2 → +6, 3 × 4 m)
# ---------------------------------------------------------------------------
func _build_chambre(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Chambre"
	parent.add_child(root)

	# Murs chambre
	_wall(root, "ChambreWallS", Vector3(6.775, 1.35, 6.0), Vector3(3.0, 2.7, 0.15), _mat_meuble)
	_wall(root, "ChambreWallE", Vector3(8.275, 1.35, 4.0), Vector3(0.15, 2.7, 4.0), _mat_meuble)
	_wall(root, "ChambreWallN_W", Vector3(5.775, 1.35, 2.0), Vector3(1.0, 2.7, 0.15), _mat_meuble)
	_wall(root, "ChambreWallN_E", Vector3(7.775, 1.35, 2.0), Vector3(1.0, 2.7, 0.15), _mat_meuble)
	# Mur Ouest = mur Est du couloir (déjà construit)

	# Sol moquette
	_floor(root, "ChambreFloor", Vector3(6.775, -0.05, 4.0), Vector3(3.0, 0.1, 4.0), _mat_moquette)

	# Plafond
	_ceiling(root, "ChambreCeiling", Vector3(6.775, 2.75, 4.0), Vector3(3.0, 0.1, 4.0), _mat_meuble)

	# Meubles chambre
	# Lit décalé de 10 cm pour ne pas toucher le mur Est à l'échelle réelle
	_mob(root, "bedDouble.glb", Vector3(7.4, 0, 5.0), 180.0)
	_mob(root, "cabinetBedDrawerTable.glb", Vector3(5.7, 0, 5.5), 90.0)
	_mob(root, "bookcaseClosed.glb", Vector3(5.8, 0, 3.0), 90.0)
	_mob(root, "desk.glb", Vector3(7.5, 0, 2.8), 0.0)
	_mob(root, "chairDesk.glb", Vector3(7.5, 0, 3.3), 180.0)

	# Déco
	_mob(root, "lampRoundTable.glb", Vector3(5.7, 0.50, 5.5), 0.0)
	_mob(root, "rugRectangle.glb", Vector3(6.775, 0, 4.5), 0.0)
	_mob(root, "pottedPlant.glb", Vector3(8.0, 0, 2.5), 0.0)
	_mob(root, "pillow.glb", Vector3(7.3, 0.60, 5.0), 0.0)

	# Cadre photo
	_box(root, "ChambreFrame", Vector3(0.44, 0.56, 0.03), Vector3(6.5, 1.6, 5.92), _mat_cadre)

	# Lumière chambre
	var chlight := OmniLight3D.new()
	chlight.name = "ChambreLight"
	chlight.position = Vector3(6.775, 2.3, 4.0)
	chlight.light_color = Color(1.0, 0.88, 0.72)
	chlight.light_energy = 0.9
	chlight.omni_range = 4.5
	chlight.shadow_enabled = false
	root.add_child(chlight)
	_reg_flicker(chlight, 0.9)

	# Conteneur : tiroir table de nuit (KEY) — y calé sur le chevet ×1,9
	_make_container(root, "NightstandDrawer",
		InteractiveContainer.Mode.SLIDE,
		Vector3(5.7, 0.30, 5.4), Vector3.BACK, 0.35, 115.0,
		InteractiveContainer.LockType.KEY,
		Vector3(0.4, 0.14, 0.03), _mat_bois)

	# Conteneur : placard bibliothèque (NONE)
	_make_container(root, "BookcaseDoor",
		InteractiveContainer.Mode.ROTATE,
		Vector3(5.55, 0.9, 3.0), Vector3.ZERO, 0.0, 110.0,
		InteractiveContainer.LockType.NONE,
		Vector3(0.6, 1.2, 0.03), _mat_meuble)


# ---------------------------------------------------------------------------
# SALLE DE BAIN (x = 5.275 → 7.775, z = +2 → +5, 2.5 × 3 m)
# ---------------------------------------------------------------------------
func _build_sdb(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "SDB"
	parent.add_child(root)

	# Murs SDB
	_wall(root, "SDBWallS", Vector3(6.525, 1.35, 5.0), Vector3(2.5, 2.7, 0.15), _mat_mur_sdb)
	_wall(root, "SDBWallE", Vector3(7.775, 1.35, 3.5), Vector3(0.15, 2.7, 3.0), _mat_mur_sdb)
	_wall(root, "SDBWallN", Vector3(6.525, 1.35, 2.0), Vector3(2.5, 2.7, 0.15), _mat_mur_sdb)
	# Mur Ouest = mur Est du couloir (déjà construit)

	# Sol carrelage
	_floor(root, "SDBFloor", Vector3(6.525, -0.05, 3.5), Vector3(2.5, 0.1, 3.0), _mat_carrelage_blanc)

	# Plafond
	_ceiling(root, "SDBCeiling", Vector3(6.525, 2.75, 3.5), Vector3(2.5, 0.1, 3.0), _mat_mur_sdb)

	# Sanitaires (échelles réelles ; baignoire décalée pour ne pas dépasser
	# du mur Est de la SDB)
	_mob(root, "toilet.glb", Vector3(7.3, 0, 4.5), 180.0)
	_mob(root, "bathroomSinkSquare.glb", Vector3(5.8, 0, 4.5), 90.0)
	_mob(root, "bathroomCabinet.glb", Vector3(5.8, 0, 3.5), 90.0)
	_mob(root, "bathroomMirror.glb", Vector3(5.55, 1.0, 4.5), 90.0)
	_mob(root, "shower.glb", Vector3(6.8, 0, 2.5), 0.0)
	_mob(root, "bathroomCabinetDrawer.glb", Vector3(7.5, 0, 3.0), -90.0)

	# Tapis de bain
	_mob(root, "rugRectangle.glb", Vector3(6.5, 0, 3.5), 0.0)

	# Serviettes (boîtes colorées)
	_box(root, "Towel1", Vector3(0.4, 0.6, 0.05), Vector3(5.55, 1.2, 3.0), _new_mat(Color(0.6, 0.75, 0.8)))
	_box(root, "Towel2", Vector3(0.4, 0.5, 0.05), Vector3(5.55, 1.1, 3.5), _new_mat(Color(0.8, 0.6, 0.6)))

	# Lumière SDB
	var slight := OmniLight3D.new()
	slight.name = "SDBLight"
	slight.position = Vector3(6.525, 2.3, 3.5)
	slight.light_color = Color(0.95, 0.95, 1.0)
	slight.light_energy = 0.8
	slight.omni_range = 3.5
	slight.shadow_enabled = false
	root.add_child(slight)
	_reg_flicker(slight, 0.8)

	# Conteneur : armoire de toilette (KEY)
	_make_container(root, "SDBCabinet",
		InteractiveContainer.Mode.ROTATE,
		Vector3(5.55, 1.2, 3.0), Vector3.ZERO, 0.0, 110.0,
		InteractiveContainer.LockType.KEY,
		Vector3(0.5, 0.7, 0.03), _mat_meuble)


# ---------------------------------------------------------------------------
# DRESSING (x = 8.275 → 10.275, z = +2 → +5, 2 × 3 m)
# ---------------------------------------------------------------------------
func _build_dressing(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Dressing"
	parent.add_child(root)

	# Murs dressing
	_wall(root, "DressWallS", Vector3(9.275, 1.35, 5.0), Vector3(2.0, 2.7, 0.15), _mat_meuble)
	_wall(root, "DressWallE", Vector3(10.275, 1.35, 3.5), Vector3(0.15, 2.7, 3.0), _mat_meuble)
	_wall(root, "DressWallN", Vector3(9.275, 1.35, 2.0), Vector3(2.0, 2.7, 0.15), _mat_meuble)
	# Mur Ouest = mur Est de la chambre (déjà construit)

	# Sol moquette
	_floor(root, "DressFloor", Vector3(9.275, -0.05, 3.5), Vector3(2.0, 0.1, 3.0), _mat_moquette)

	# Plafond
	_ceiling(root, "DressCeiling", Vector3(9.275, 2.75, 3.5), Vector3(2.0, 0.1, 3.0), _mat_meuble)

	# Meubles dressing (coatRack = porte-manteau MURAL, monté au mur Est)
	_mob(root, "bookcaseOpen.glb", Vector3(9.8, 0, 2.5), 180.0)
	_mob(root, "bookcaseOpen.glb", Vector3(9.8, 0, 3.5), 180.0)
	_mob(root, "cabinetBedDrawer.glb", Vector3(8.6, 0, 4.5), 90.0)
	_mob(root, "coatRack.glb", Vector3(10.1, 1.4, 4.5), -90.0)
	_mob(root, "bathroomMirror.glb", Vector3(9.275, 1.4, 4.9), 180.0)
	_mob(root, "pillowLong.glb", Vector3(9.8, 0.66, 3.0), 0.0)
	_mob(root, "cardboardBoxClosed.glb", Vector3(8.6, 0, 2.5), 20.0)

	# Lumière dressing
	var dlight := OmniLight3D.new()
	dlight.name = "DressingLight"
	dlight.position = Vector3(9.275, 2.3, 3.5)
	dlight.light_color = Color(1.0, 0.9, 0.8)
	dlight.light_energy = 0.7
	dlight.omni_range = 3.0
	dlight.shadow_enabled = false
	root.add_child(dlight)
	_reg_flicker(dlight, 0.7)

	# Conteneur : tiroir commode (FORCEABLE) — y calé sur la commode ×1,9
	_make_container(root, "DresserDrawer",
		InteractiveContainer.Mode.SLIDE,
		Vector3(8.6, 0.30, 4.4), Vector3.BACK, 0.35, 115.0,
		InteractiveContainer.LockType.FORCEABLE,
		Vector3(0.4, 0.14, 0.03), _mat_bois)


# ---------------------------------------------------------------------------
# GAMEPLAY rétrofit (pièce existante)
# ---------------------------------------------------------------------------
func _build_existing_gameplay() -> void:
	_container_part("Shell/kitchenCabinetDrawer", "drawer", "KitchenDrawerKey",
		InteractiveContainer.Mode.SLIDE, InteractiveContainer.LockType.KEY, 0.42)
	_container_part("Shell/kitchenFridge", "doorFridge", "FridgeDoor",
		InteractiveContainer.Mode.ROTATE, InteractiveContainer.LockType.KEY, 0.0, -105.0)
	_container_part("Shell/sideTableDrawers", "drawerLeft", "ClosetDoor",
		InteractiveContainer.Mode.SLIDE, InteractiveContainer.LockType.FORCEABLE, 0.35)


# ---------------------------------------------------------------------------
# Mimics (GDD §5.3) — 2 mimics statiques.
# ---------------------------------------------------------------------------
func _place_mimics() -> void:
	# Mimic 1 : tasse sur la table basse (à côté d'une vraie tasse)
	var fake1 := Mimic.new()
	fake1.name = "MugMimic"
	add_child(fake1)
	fake1.position = _surface_point("Shell/table", 0.02) + Vector3(0.15, 0.0, -0.15)
	_place_furniture(fake1, FOOD + "cup-tea.glb", Vector3.ZERO, 0.0, 1.0)
	var cs1 := CollisionShape3D.new()
	var bs1 := BoxShape3D.new()
	bs1.size = Vector3(0.16, 0.16, 0.16)
	cs1.shape = bs1
	cs1.position = Vector3(0, 0.06, 0)
	fake1.add_child(cs1)
	mimics.append(fake1)

	# Mimic 2 : tasse sur la table d'appoint du coin lecture
	var fake2 := Mimic.new()
	fake2.name = "SideTableMimic"
	add_child(fake2)
	fake2.position = _surface_point("Shell/sideTableDrawers", 0.02) + Vector3(-0.2, 0.0, 0.0)
	_place_furniture(fake2, FOOD + "cup-tea.glb", Vector3.ZERO, 30.0, 1.0)
	var cs2 := CollisionShape3D.new()
	var bs2 := BoxShape3D.new()
	bs2.size = Vector3(0.16, 0.16, 0.16)
	cs2.shape = bs2
	cs2.position = Vector3(0, 0.06, 0)
	fake2.add_child(cs2)
	mimics.append(fake2)


# ---------------------------------------------------------------------------
# Spawns de dose (GDD §5.1)
# ---------------------------------------------------------------------------
func _register_spawn_spots() -> void:
	# Chaque conteneur reste un spawn valide ; les portes utilisent un point
	# légèrement derrière leur façade, les tiroirs utilisent leur repère local.
	for c in containers:
		_spawn_spots.append({"pos": c.to_global(c.content_offset), "container": c})

	var surfaces := [
		"Shell/kitchenCabinetDrawer", "Shell/table", "Shell/loungeSofa",
		"Shell/sideTableDrawers", "Shell/ExtensionEst/Garage/Etabli",
		"Shell/ExtensionEst/Chambre/LitDouble", "Shell/ExtensionEst/Chambre/Bureau",
		"Shell/ExtensionEst/SDB/Lavabo", "Shell/ExtensionEst/Dressing/Armoire2",
	]
	for path in surfaces:
		_spawn_spots.append({"pos": _surface_point(path, 0.09), "container": null})

	for pos in [Vector3.ZERO, Vector3(7.3, 0.0, 2.0),
			Vector3(7.3, 0.0, 4.6), Vector3(6.3, 0.0, -0.6)]:
		_spawn_spots.append({"pos": pos, "container": null, "floor": true})


func _key_spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for path in [
		"Shell/table", "Shell/kitchenCabinetDrawer", "Shell/sideTableDrawers",
		"Shell/loungeSofa", "Shell/ExtensionEst/Garage/Etabli",
		"Shell/ExtensionEst/Chambre/LitDouble", "Shell/ExtensionEst/Chambre/Bureau",
		"Shell/ExtensionEst/SDB/Lavabo", "Shell/ExtensionEst/Dressing/Armoire2",
	]:
		spots.append(_surface_point(path))
	spots.append(Vector3(7.3, 0.0, 2.0)) # sol du couloir
	return spots


# ---------------------------------------------------------------------------
# Helpers de construction (murs, sols, plafonds, plinthes, pneus)
# ---------------------------------------------------------------------------
func _wall(parent: Node, name: String, pos: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.position = pos
	parent.add_child(body)

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	col.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	return body


func _floor(parent: Node, name: String, pos: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	return _wall(parent, name, pos, size, mat)


func _ceiling(parent: Node, name: String, pos: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	return _wall(parent, name, pos, size, mat)


func _plinthe(parent: Node, name: String, pos: Vector3, size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = _new_mat(Color(0.24, 0.16, 0.11))
	mi.position = pos
	parent.add_child(mi)
	return mi


func _tire(parent: Node, name: String, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.3
	cyl.height = 0.15
	mi.mesh = cyl
	mi.material_override = _new_mat(Color(0.08, 0.08, 0.08))
	mi.position = pos
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
## Pose un meuble Kenney à son échelle réelle (FURN_SCALE, défaut ×2,5).
func _mob(parent: Node, glb_name: String, pos: Vector3, rot_y := 0.0) -> Node3D:
	return _place_furniture(parent, FURN + glb_name, pos, rot_y,
		FURN_SCALE.get(glb_name, 2.5))


func _place_food(parent: Node, glb_name: String, pos: Vector3, rot_y := 0.0) -> Node3D:
	return _place_furniture(parent, FOOD + glb_name, pos, rot_y)
