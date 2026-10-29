class_name DecorCatalog
extends RefCounted
## Décorations achetables dans la boutique du lobby. Invisibles tant qu'elles ne
## sont pas achetées : `apply()` les montre ou les crée dans l'appartement.
##
## kind "node"  : nœud déjà présent dans la scène, masqué par défaut.
## kind "frame" : cadre procédural accroché au mur.
## kind "glb"   : objet Kenney posé au sol ou sur une surface (`on` = nœud support).

const KENNEY := "res://assets/kenney/furniture/"

const ITEMS: Array[Dictionary] = [
	{"id": "tableau_royal", "name": "Tableau royal", "price": 12, "kind": "node", "node": "tableau_royesque_framed"},
	{"id": "tableau_swap", "name": "Face swap", "price": 12, "kind": "node", "node": "faceswapinggggggggg_framed"},
	{"id": "tableau_mayo", "name": "Mayo Zedong", "price": 18, "kind": "node", "node": "mayozedong_framed"},
	{"id": "cadre_paysage", "name": "Cadre paysage", "price": 8, "kind": "frame",
		"pos": Vector3(3.15, 1.65, -2.99), "rot": 0.0, "size": Vector2(0.9, 0.6),
		"colors": [Color(0.45, 0.62, 0.8), Color(0.25, 0.5, 0.22)]},
	{"id": "cadre_portrait", "name": "Cadre portrait", "price": 8, "kind": "frame",
		"pos": Vector3(-0.5, 1.6, 2.99), "rot": 180.0, "size": Vector2(0.55, 0.75),
		"colors": [Color(0.6, 0.45, 0.3), Color(0.2, 0.15, 0.12)]},
	{"id": "plante_angle", "name": "Plante d'angle", "price": 6, "kind": "glb",
		"glb": "plantSmall2.glb", "pos": Vector3(3.6, 0.0, 2.6), "scale": 2.5},
	{"id": "lampadaire", "name": "Lampadaire", "price": 10, "kind": "glb",
		"glb": "lampRoundFloor.glb", "pos": Vector3(3.65, 0.0, 1.0), "scale": 2.5},
	{"id": "lampe_table", "name": "Lampe de table", "price": 8, "kind": "glb",
		"glb": "lampRoundTable.glb", "on": "table", "offset": Vector3(0.0, 0.0, 0.25), "scale": 2.5},
	{"id": "livres", "name": "Pile de livres", "price": 5, "kind": "glb",
		"glb": "books.glb", "on": "table", "offset": Vector3(0.0, 0.0, -0.3), "scale": 2.5},
	{"id": "radio", "name": "Vieille radio", "price": 7, "kind": "glb",
		"glb": "radio.glb", "on": "kitchenCabinetDrawer", "offset": Vector3.ZERO, "scale": 2.5},
	{"id": "nounours", "name": "Nounours", "price": 15, "kind": "glb",
		"glb": "bear.glb", "on": "ExtensionEst/Chambre/LitDouble", "offset": Vector3.ZERO, "scale": 2.5},
]


static func get_item(id: String) -> Dictionary:
	for item in ITEMS:
		if item["id"] == id:
			return item
	return {}


## Prépare la map : tout est masqué, puis seules les décorations possédées apparaissent.
static func apply(map: Node3D, owned: Array) -> void:
	var shell := map.get_node_or_null("Shell") as Node3D
	if shell == null:
		return
	for item in ITEMS:
		var existing := shell.get_node_or_null("Deco_" + String(item["id"]))
		if existing != null:
			existing.queue_free()
		if item["kind"] == "node":
			var node := shell.get_node_or_null(String(item["node"])) as Node3D
			if node != null:
				node.visible = item["id"] in owned
		elif item["id"] in owned:
			var built: Node3D = _build(item)
			if built != null:
				built.name = "Deco_" + String(item["id"])
				shell.add_child(built)
				_place(shell, built, item)


static func _build(item: Dictionary) -> Node3D:
	match item["kind"]:
		"frame":
			return _build_frame(item)
		"glb":
			var packed: PackedScene = load(KENNEY + String(item["glb"]))
			if packed == null:
				return null
			var n: Node3D = packed.instantiate()
			n.scale = Vector3.ONE * float(item.get("scale", 2.5))
			return n
	return null


static func _place(shell: Node3D, built: Node3D, item: Dictionary) -> void:
	if item["kind"] == "frame":
		built.position = item["pos"]
		built.rotation.y = deg_to_rad(float(item["rot"]))
		return
	if item.has("on"):
		var support := shell.get_node_or_null(String(item["on"])) as Node3D
		if support == null:
			return
		built.position = _top_of(shell, support) + (item["offset"] as Vector3)
	else:
		built.position = item["pos"]


## Centre du dessus d'un meuble, dans le repère de la coquille.
static func _top_of(shell: Node3D, support: Node3D) -> Vector3:
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	var stack: Array[Node] = [support]
	var inv := shell.global_transform.affine_inverse()
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D and (cur as MeshInstance3D).mesh != null and (cur as MeshInstance3D).visible:
			var box: AABB = (cur as MeshInstance3D).mesh.get_aabb()
			var xf: Transform3D = inv * (cur as MeshInstance3D).global_transform
			for x in [box.position.x, box.end.x]:
				for y in [box.position.y, box.end.y]:
					for z in [box.position.z, box.end.z]:
						var p: Vector3 = xf * Vector3(x, y, z)
						mn = mn.min(p)
						mx = mx.max(p)
		for c in cur.get_children():
			stack.append(c)
	return Vector3((mn.x + mx.x) * 0.5, mx.y, (mn.z + mx.z) * 0.5)


## Cadre en bois sombre autour d'une toile à deux tons (ciel/terre, etc.).
static func _build_frame(item: Dictionary) -> Node3D:
	var size: Vector2 = item["size"]
	var colors: Array = item["colors"]
	var root := Node3D.new()
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.22, 0.13, 0.07)
	wood.roughness = 0.7
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(size.x + 0.1, size.y + 0.1, 0.04)
	frame.mesh = fm
	frame.material_override = wood
	root.add_child(frame)
	for i in 2:
		var canvas := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(size.x, size.y * 0.5)
		canvas.mesh = qm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[i]
		mat.roughness = 0.9
		canvas.material_override = mat
		canvas.position = Vector3(0.0, size.y * (0.25 if i == 0 else -0.25), 0.022)
		root.add_child(canvas)
	var sun := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	sun.mesh = sm
	var sun_mat := StandardMaterial3D.new()
	sun_mat.albedo_color = Color(1.0, 0.9, 0.5)
	sun_mat.emission_enabled = true
	sun_mat.emission = Color(1.0, 0.8, 0.3)
	sun.material_override = sun_mat
	sun.scale = Vector3(1, 1, 0.1)
	sun.position = Vector3(size.x * 0.25, size.y * 0.2, 0.03)
	root.add_child(sun)
	return root
