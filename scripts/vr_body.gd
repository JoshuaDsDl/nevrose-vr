class_name VRBody
extends Node3D
## Corps joueur visible en FPV quand on baisse les yeux : cuisses/genoux/jambes
## sous la caméra. Suit le yaw de la caméra mais pas son pitch — sinon les
## jambes remonteraient quand on regarde ses pieds. Zéro mesh importé.

const SHIRT := Color(0.30, 0.34, 0.42)
const PANTS := Color(0.22, 0.22, 0.26)
const SHOES := Color(0.12, 0.10, 0.10)

var _camera: XRCamera3D
var _yaw_only := 0.0


func setup(camera: XRCamera3D) -> void:
	_camera = camera


func _process(_delta: float) -> void:
	if _camera == null:
		return
	# Yaw uniquement : on ignore le pitch/roll de la tête pour le corps.
	var fwd := -_camera.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.0001:
		fwd = fwd.normalized()
		_yaw_only = atan2(-fwd.x, -fwd.z)
	global_rotation.y = _yaw_only


func _init() -> void:
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE

	var m_shirt := StandardMaterial3D.new()
	m_shirt.albedo_color = SHIRT
	m_shirt.roughness = 0.85
	var m_pants := StandardMaterial3D.new()
	m_pants.albedo_color = PANTS
	m_pants.roughness = 0.9
	var m_shoes := StandardMaterial3D.new()
	m_shoes.albedo_color = SHOES
	m_shoes.roughness = 0.7

	# Torse (visible si on baisse vraiment la tête)
	_box(unit, "Chest", Vector3(0.34, 0.30, 0.20), Vector3(0, 1.25, 0.05), m_shirt)
	# Bassin
	_box(unit, "Hips", Vector3(0.32, 0.16, 0.20), Vector3(0, 1.02, 0.02), m_pants)

	# Cuisses + mollets + chaussures, légèrement écartés
	for side in [-1.0, 1.0]:
		var x: float = 0.09 * side
		_box(unit, "Thigh%s" % side, Vector3(0.13, 0.36, 0.14), Vector3(x, 0.78, 0.0), m_pants)
		_box(unit, "Shin%s" % side, Vector3(0.11, 0.36, 0.12), Vector3(x, 0.38, -0.01), m_pants)
		_box(unit, "Shoe%s" % side, Vector3(0.12, 0.09, 0.26), Vector3(x, 0.045, -0.06), m_shoes)


func _box(unit: BoxMesh, name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = unit
	mi.scale = size
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi
