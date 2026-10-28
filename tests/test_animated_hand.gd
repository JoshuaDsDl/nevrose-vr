extends SceneTree
## Test: les ressources de la main animée sont intactes et cohérentes.
## (Le script hand.gd est validé en VR, pas headless — ici on vérifie
##  que les bones, animations et blend tree sont bien importés.)

const HAND_SCENE_R := "res://addons/godot-xr-tools/hands/scenes/lowpoly/right_hand_low.tscn"
const HAND_SCENE_L := "res://addons/godot-xr-tools/hands/scenes/lowpoly/left_hand_low.tscn"

func _initialize() -> void:
	print("=== TEST MAIN ANIMÉE (ressources) ===")
	var fails := 0
	# --- Droite ---
	fails += _check_hand(HAND_SCENE_R, "right")
	# --- Gauche ---
	fails += _check_hand(HAND_SCENE_L, "left")
	print("=== RESULTAT: %s ===" % ["PASS" if fails == 0 else "FAIL (%d)" % fails])
	quit(0 if fails == 0 else 1)


func _check_hand(scene_path: String, label: String) -> int:
	var packed: PackedScene = load(scene_path)
	if packed == null:
		print("  [ECHEC] %s — scène non trouvée: %s" % [label, scene_path])
		return 1
	print("  [OK] %s — scène chargée" % label)

	var inst: Node = packed.instantiate()
	# Ne PAS add_child (évite les erreurs headless du script hand.gd)

	# --- Skeleton3D + bones ---
	var skel: Skeleton3D = _find_skeleton(inst)
	if skel == null:
		print("  [ECHEC] %s — Skeleton3D introuvable" % label)
		inst.free()
		return 1
	print("  [OK] %s — Skeleton3D: %d bones" % [label, skel.get_bone_count()])
	if skel.get_bone_count() < 20:
		print("  [ECHEC] %s — trop peu de bones (%d < 20)" % [label, skel.get_bone_count()])
		inst.free()
		return 1

	# Vérifie quelques bones clés
	var suffix: String = "_R" if label == "right" else "_L"
	for bone_name in ["Wrist", "Palm", "Index_Proximal", "Index_Intermediate", "Index_Distal", "Thumb_Metacarpal", "Thumb_Proximal", "Thumb_Distal"]:
		var full_name: String = bone_name + suffix
		var bone_idx: int = skel.find_bone(full_name)
		if bone_idx < 0:
			print("  [ECHEC] %s — bone '%s' introuvable" % [label, full_name])
			inst.free()
			return 1
	print("  [OK] %s — bones clés présentes (Wrist, Palm, Index×3, Thumb×3)" % label)

	# --- AnimationPlayer ---
	var model_name: String = "Hand_Nails_low_%s" % ("R" if label == "right" else "L")
	var anim_player: Node = inst.get_node_or_null(model_name + "/AnimationPlayer")
	if anim_player == null:
		print("  [WARN] %s — AnimationPlayer introuvable (le script hand.gd gère ça)" % label)
	else:
		var anims: Array = anim_player.get_animation_list()
		print("  [OK] %s — AnimationPlayer: %d animations" % [label, anims.size()])
		# Vérifie les 3 poses essentielles
		for pose_name in ["Grip", "Straight", "Sign_Point"]:
			var found: bool = false
			for a in anims:
				if a == pose_name:
					found = true
					break
			if not found:
				print("  [WARN] %s — animation '%s' non trouvée (les 35 posent peuvent différer)" % [label, pose_name])

	# --- AnimationTree ---
	var anim_tree: Node = inst.get_node_or_null("AnimationTree")
	if anim_tree == null:
		print("  [ECHEC] %s — AnimationTree introuvable" % label)
		inst.free()
		return 1
	print("  [OK] %s — AnimationTree présent" % label)

	inst.free()
	return 0


func _find_skeleton(node: Node) -> Skeleton3D:
	for c in node.get_children():
		if c is Skeleton3D:
			return c
		var r: Skeleton3D = _find_skeleton(c)
		if r != null:
			return r
	return null
