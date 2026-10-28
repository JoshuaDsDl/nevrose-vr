extends SceneTree
## Test: l'AnimationTree de la main déforme les bones quand on change
## les paramètres Grip/Trigger (validation du système d'animation).

const SCENE_R := "res://addons/godot-xr-tools/hands/scenes/lowpoly/right_hand_low.tscn"

func _initialize() -> void:
	print("=== TEST BLEND TREE MAIN DROITE ===")
	var packed: PackedScene = load(SCENE_R)
	if packed == null:
		print("  [ECHEC] scène non trouvée")
		quit(1)
		return

	var inst := packed.instantiate()
	# Détacher le script pour éviter le crash headless (hand.gd cherche XRController3D)
	inst.set_script(null)
	root.add_child(inst)
	await process_frame
	await process_frame

	# Trouve l'AnimationTree
	var tree: AnimationTree = inst.get_node_or_null("AnimationTree")
	if tree == null:
		print("  [ECHEC] AnimationTree introuvable")
		quit(1)
		return

	# Trouve le Skeleton3D
	var skel: Skeleton3D = _find_skeleton(inst)
	if skel == null:
		print("  [ECHEC] Skeleton3D introuvable")
		quit(1)
		return

	# Bone de référence : Index_Proximal_R (la plus sensible au grip)
	var bone_idx: int = skel.find_bone("Index_Proximal_R")
	if bone_idx < 0:
		print("  [ECHEC] bone Index_Proximal_R introuvable")
		quit(1)
		return

	# Pose de départ (rest = main ouverte)
	var rest_pose: Transform3D = skel.get_bone_pose(bone_idx)

	# --- Test 1 : Grip = 1.0 (main fermée) ---
	print("  [i] Setting Grip/blend_amount = 1.0 (main fermée)...")
	tree.set("parameters/Grip/blend_amount", 1.0)
	tree.active = true
	# Forcer un tick
	for i in 10:
		await process_frame

	var grip_pose: Transform3D = skel.get_bone_pose(bone_idx)
	var grip_changed: bool = not rest_pose.basis.is_equal_approx(grip_pose.basis)
	print("  [%s] Grip → Index_Proximal a bougé : %s" % ["OK" if grip_changed else "ECHEC", grip_changed])

	# --- Test 2 : Grip = 0, Trigger = 1.0 (pointer) ---
	print("  [i] Setting Grip=0, Trigger/blend_amount = 1.0 (pointer)...")
	tree.set("parameters/Grip/blend_amount", 0.0)
	tree.set("parameters/Trigger/blend_amount", 1.0)
	for i in 10:
		await process_frame

	var trigger_pose: Transform3D = skel.get_bone_pose(bone_idx)
	var trigger_diff: bool = not grip_pose.basis.is_equal_approx(trigger_pose.basis)
	print("  [%s] Trigger → Index_Proximal a changé par rapport au grip : %s" % ["OK" if trigger_diff else "ECHEC", trigger_diff])

	# --- Test 3 : Reset (main ouverte) ---
	tree.set("parameters/Grip/blend_amount", 0.0)
	tree.set("parameters/Trigger/blend_amount", 0.0)
	for i in 10:
		await process_frame

	var reset_pose: Transform3D = skel.get_bone_pose(bone_idx)
	var reset_ok: bool = reset_pose.basis.is_equal_approx(rest_pose.basis)
	print("  [%s] Reset → Index_Proximal retourne à la pose rest : %s" % ["OK" if reset_ok else "ECHEC", reset_ok])

	var fails := 0
	if not grip_changed: fails += 1
	if not trigger_diff: fails += 1
	if not reset_ok: fails += 1

	print("=== RESULTAT: %s ===" % ["PASS" if fails == 0 else "FAIL (%d)" % fails])
	quit(0 if fails == 0 else 1)


func _find_skeleton(node: Node) -> Skeleton3D:
	for c in node.get_children():
		if c is Skeleton3D:
			return c
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null
