extends SceneTree
## Dump des centres et tailles locales des meubles de l'extension (Shell/ExtensionEst),
## pour replacer chaque meuble par son centre réel.
## Usage : Godot --headless --path . --script res://tools/dump_extension.gd

func _init() -> void:
	var packed: PackedScene = load("res://scenes/map2_extended.tscn")
	var root := packed.instantiate()
	get_root().add_child(root)
	await process_frame
	var ext := root.get_node("ExtensionEst")
	for child in ext.get_children():
		_dump(child, "ExtensionEst")
	_dump(root.get_node("EntranceDoor"), "")
	quit()


func _dump(node: Node, prefix: String) -> void:
	var here := prefix + ("/" if prefix != "" else "") + String(node.name)
	if node is Node3D and not (node is Light3D):
		var n := node as Node3D
		var box := _local_bounds(n)
		if box.size != Vector3.ZERO:
			var t := n.transform
			var b := t.basis
			var o := t.origin
			var vals := [here, o.x, o.y, o.z,
				b.x.x, b.y.x, b.z.x, b.x.y, b.y.y, b.z.y, b.x.z, b.y.z, b.z.z,
				box.get_center().x, box.get_center().y, box.get_center().z,
				box.size.x, box.size.y, box.size.z,
				box.position.x, box.position.y, box.position.z]
			var parts := PackedStringArray()
			for v in vals:
				parts.append(str(v))
			print("EXT|" + "|".join(parts))
	for child in node.get_children():
		if child is Node3D:
			_dump(child, here)


func _local_bounds(n: Node3D) -> AABB:
	var minimum := Vector3(1e9, 1e9, 1e9)
	var maximum := Vector3(-1e9, -1e9, -1e9)
	var found := false
	var inv := n.global_transform.affine_inverse()
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D and (current as MeshInstance3D).mesh != null:
			var mi := current as MeshInstance3D
			var rel: Transform3D = inv * mi.global_transform
			var local := mi.mesh.get_aabb()
			for x in [local.position.x, local.end.x]:
				for y in [local.position.y, local.end.y]:
					for z in [local.position.z, local.end.z]:
						var pt: Vector3 = rel * Vector3(x, y, z)
						minimum = minimum.min(pt)
						maximum = maximum.max(pt)
						found = true
		for child in current.get_children():
			stack.append(child)
	return AABB(minimum, maximum - minimum) if found else AABB()
