class_name WeaponModel
extends RefCounted
## Armes du mode Chasse, dessinées avec des primitives (aucun modèle importé).
## L'origine est la poignée ; l'arme s'étend vers -Z (devant la manette).

const WOOD := Color(0.45, 0.3, 0.16)
const STEEL := Color(0.55, 0.57, 0.62)
const DARK := Color(0.12, 0.12, 0.14)


static func build(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Arme_" + id
	match id:
		"arme_marteau":
			_bar(root, 0.34, 0.02, WOOD, 0.0)
			_block(root, Vector3(0.16, 0.07, 0.07), Vector3(0, 0, -0.36), STEEL)
		"arme_batte":
			_bar(root, 0.78, 0.02, WOOD, 0.0, 0.045)
		"arme_pied":
			_bar(root, 0.55, 0.014, STEEL, 0.0)
			_block(root, Vector3(0.025, 0.1, 0.03), Vector3(0, -0.04, -0.56), STEEL)
			_block(root, Vector3(0.03, 0.03, 0.08), Vector3(0, 0.0, -0.01), DARK)
		"arme_masse":
			_bar(root, 0.8, 0.022, WOOD, 0.0)
			_block(root, Vector3(0.26, 0.15, 0.15), Vector3(0, 0, -0.84), STEEL)
		_:
			return root
	root.rotation_degrees.x = 32.0 # la manette pointe un peu vers le bas : on relève l'arme
	return root


static func _mat(color: Color, metal := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.45 if metal else 0.8
	m.metallic = 0.6 if metal else 0.0
	return m


## Manche : cylindre posé dans l'axe -Z, éventuellement plus épais au bout.
static func _bar(root: Node3D, length: float, radius: float, color: Color, _unused: float, tip_radius := -1.0) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.height = length
	cm.bottom_radius = radius
	cm.top_radius = tip_radius if tip_radius > 0.0 else radius
	mi.mesh = cm
	mi.material_override = _mat(color, color == STEEL)
	mi.rotation_degrees.x = -90.0 # le haut du cylindre (bout épais) part devant
	mi.position = Vector3(0, 0, -length * 0.5)
	root.add_child(mi)


static func _block(root: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color, color == STEEL)
	mi.position = pos
	root.add_child(mi)
