extends SceneTree
## Diagnostic: quelles bones bougent sous Grip vs Trigger ?

const SCENE_R := "res://addons/godot-xr-tools/hands/scenes/lowpoly/right_hand_low.tscn"

func _initialize() -> void:
	var packed: PackedScene = load(SCENE_R)
	var inst := packed.instantiate()
	inst.set_script(null)
	root.add_child(inst)
	await process_frame
	await process_frame
	var tree: AnimationTree = inst.get_node("AnimationTree")
	var skel: Skeleton3D = _find_skeleton(inst)

	# Pose rest (tree inactif)
	var rest: Array = []
	for i in skel.get_bone_count():
		rest.append(skel.get_bone_pose(i))

	# GRIP = 1
	tree.active = true
	tree.set("parameters/Grip/blend_amount", 1.0)
	tree.set("parameters/Trigger/blend_amount", 0.0)
	for i in 10: await process_frame
	print("=== GRIP=1 : bones déplacées (vs rest) ===")
	for i in skel.get_bone_count():
		var p := skel.get_bone_pose(i)
		var d := _basis_angle_diff(rest[i].basis, p.basis)
		if d > 0.02:
			print("  %-24s %.3f rad" % [skel.get_bone_name(i), d])

	# TRIGGER = 1
	tree.set("parameters/Grip/blend_amount", 0.0)
	tree.set("parameters/Trigger/blend_amount", 1.0)
	for i in 10: await process_frame
	print("=== TRIGGER=1 : bones déplacées (vs rest) ===")
	for i in skel.get_bone_count():
		var p := skel.get_bone_pose(i)
		var d := _basis_angle_diff(rest[i].basis, p.basis)
		if d > 0.02:
			print("  %-24s %.3f rad" % [skel.get_bone_name(i), d])

	# AUCUN (retour repos)
	tree.set("parameters/Grip/blend_amount", 0.0)
	tree.set("parameters/Trigger/blend_amount", 0.0)
	for i in 10: await process_frame
	var maxres := 0.0
	for i in skel.get_bone_count():
		maxres = maxf(maxres, _basis_angle_diff(rest[i].basis, skel.get_bone_pose(i).basis))
	print("=== AUCUN : max écart vs rest = %.4f rad (devrait être ~0) ===" % maxres)
	inst.free()
	quit(0)


func _basis_angle_diff(a: Basis, b: Basis) -> float:
	return (a.get_rotation_quaternion().inverse() * b.get_rotation_quaternion()).get_angle()


func _find_skeleton(node: Node) -> Skeleton3D:
	for c in node.get_children():
		if c is Skeleton3D:
			return c
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null
