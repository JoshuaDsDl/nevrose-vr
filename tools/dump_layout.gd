extends SceneTree
## Dump des boîtes englobantes monde de la coquille map2_extended.tscn.
## Usage : Godot --headless --path . --script res://tools/dump_layout.gd

func _init() -> void:
	var packed: PackedScene = load("res://scenes/map2_extended.tscn")
	var root := packed.instantiate()
	get_root().add_child(root)
	await process_frame
	_dump(root, "")
	quit()


func _dump(node: Node, path: String) -> void:
	var here := path + "/" + String(node.name)
	if node is Node3D and not (node is Camera3D):
		var box := _bounds(node as Node3D)
		if box.size != Vector3.ZERO:
			var p := box.position
			var e := box.end
			print("LAYOUT|%s|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f" % [here, p.x, p.y, p.z, e.x, e.y, e.z])
	for child in node.get_children():
		_dump(child, here)


func _bounds(node: Node3D) -> AABB:
	var minimum := Vector3(1e9, 1e9, 1e9)
	var maximum := Vector3(-1e9, -1e9, -1e9)
	var found := false
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D and (current as MeshInstance3D).mesh != null:
			var mi := current as MeshInstance3D
			var local := mi.mesh.get_aabb()
			for x in [local.position.x, local.end.x]:
				for y in [local.position.y, local.end.y]:
					for z in [local.position.z, local.end.z]:
						var pt: Vector3 = mi.global_transform * Vector3(x, y, z)
						minimum = minimum.min(pt)
						maximum = maximum.max(pt)
						found = true
		for child in current.get_children():
			stack.append(child)
	return AABB(minimum, maximum - minimum) if found else AABB()
