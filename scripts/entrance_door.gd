class_name EntranceDoor
extends Node3D
## Porte d'entrée de la maison : vantail réel, pivot sur charnière et collision mobile.

## Porte d'entrée de l'appartement : verrouillée, elle ne s'ouvre pas et reste infranchissable.
@export var verrouillee := true

var _closed_rot_y := 0.0
var _is_open := false
var _tween: Tween = null


func _ready() -> void:
	_closed_rot_y = rotation.y
	var leaf := get_node_or_null("Door_1") as MeshInstance3D
	if leaf == null or leaf.mesh == null:
		push_error("EntranceDoor: vantail Door_1 introuvable")
		return
	# Boîte du vantail en coordonnées monde : le parent est mis à l'échelle 0,5,
	# une boîte en repère local serait deux fois trop petite.
	var world := leaf.global_transform * leaf.mesh.get_aabb()
	_add_world_box("Collision", world, true)
	_add_world_box("area", world.grow(0.025), false)


func _add_world_box(node_name: String, box: AABB, solid: bool) -> void:
	var shape := BoxShape3D.new()
	shape.size = box.size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	var body: Node3D = StaticBody3D.new() if solid else Area3D.new()
	body.name = node_name
	body.add_child(collision)
	add_child(body)
	body.global_transform = Transform3D(Basis(), box.get_center())


func on_pointed() -> void:
	pass


func on_unpointed() -> void:
	pass


func interact(_holding_key: Node3D = null) -> void:
	if verrouillee or (_tween and _tween.is_valid()):
		return
	_is_open = not _is_open
	var target_y := _closed_rot_y + deg_to_rad(-100.0 if _is_open else 0.0)
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "rotation:y", target_y, 0.35)