extends SceneTree
## Toutes les pilules doivent pouvoir se prendre : chaque emplacement (au sol, sur une surface,
## dans un tiroir ou un placard) doit être à portée d'une case où le joueur peut se tenir.
## Usage : Godot --headless --path . --script res://tests/test_pills.gd

const REACH := 0.75 ## distance horizontale max entre une case où l'on se tient et la pilule (main tendue, penché)

var _failures := 0


func _assert(cond: bool, label: String) -> void:
	if cond:
		print("  [OK] ", label)
	else:
		_failures += 1
		printerr("  [ECHEC] ", label)


func _initialize() -> void:
	print("=== TEST PILLES ET ACHATS ===")
	LlmClient.force_offline = true
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.profile.persist = false
	main.start_game(Main.Mode.RESIST)
	var waited := 0
	while waited < 600 and not (main.nav != null and main.nav.is_ready()):
		await physics_frame
		waited += 1
	var apt: MapBase = main.apartment
	var nav: NavGrid = main.nav
	_assert(nav != null and nav.is_ready(), "carte de déplacement prête (%d cases)" % nav.reachable.size())
	var bad: Array[String] = []
	var worst := 0.0
	for sp in apt._spawn_spots:
		var pos: Vector3 = sp["pos"]
		var best := 1e9
		for cell in nav.reachable:
			var center: Vector3 = nav.cell_center(cell)
			best = minf(best, Vector2(center.x - pos.x, center.z - pos.z).length())
		worst = maxf(worst, best)
		if best > REACH:
			var kind := "tiroir/placard" if sp["container"] != null else ("sol" if sp.get("floor", false) else "surface")
			bad.append("%s en %s (%.2f m)" % [kind, str(pos), best])
	print("  emplacements : %d, pire distance %.2f m" % [apt._spawn_spots.size(), worst])
	for b in bad:
		printerr("  [ECHEC] pas atteignable : ", b)
	_assert(bad.is_empty(), "toutes les pilules sont à portée d'une case de déplacement (%d hors portée)" % bad.size())
	# Rien au-dessus d'une pilule posée au sol ou sur une surface (sinon elle est cachée sous un meuble).
	var covered: Array[String] = []
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	for sp in apt._spawn_spots:
		if sp["container"] != null:
			continue
		var base: Vector3 = sp["pos"]
		var q := PhysicsRayQueryParameters3D.create(base + Vector3(0, 0.15, 0), base + Vector3(0, 1.3, 0))
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			covered.append("%s sous %s" % [str(base), (hit["collider"] as Node).name])
	for cv in covered:
		printerr("  [ECHEC] pilule cachée : ", cv)
	_assert(covered.is_empty(), "aucune pilule n'est cachée sous un meuble")
	# --- Prise au contact (sans viser), dans la main qui la prend ---
	var rh: XRController3D = main.right_hand
	var lh: XRController3D = main.left_hand
	var dose: Dose = _spawn_open_air(apt)
	await process_frame
	lh.global_position = dose.global_position + Vector3(0.1, 0.05, 0.0)
	main._pointed = null
	main.interact(lh)
	_assert(main._held_pill == dose and dose.get_parent() == lh, "prise : la pilule va dans la main qui l'a prise (gauche)")
	await process_frame
	_assert(not dose.get_node("Halo").visible and not dose.get_node("Faisceau").visible, "prise : en main, ni halo ni faisceau devant les yeux")
	# Portée à la bouche : avalée sans gâchette.
	var taken: int = main.dose_count
	lh.global_position += dose._get_mouth_position() - dose.global_position
	main._tick_pill_feedback()
	await process_frame
	_assert(main.dose_count == taken + 1 and main._held_pill == null, "bouche : la pilule est avalée dès qu'elle touche la bouche")
	await create_timer(2.3).timeout # la suivante apparaît
	# --- Halo : visible de loin, effacé de près ---
	dose = _spawn_open_air(apt)
	await process_frame
	var cam: Node3D = main.xr_camera
	var far_pos := dose.global_position + Vector3(0.0, 1.5, 5.0)
	main.xr_origin.global_position += far_pos - cam.global_position
	dose._fade_halo()
	var far_alpha: float = dose._halo_mat.albedo_color.a
	main.xr_origin.global_position += (dose.global_position + Vector3(0.0, 0.3, 0.5)) - cam.global_position
	dose._fade_halo()
	_assert(far_alpha > 0.9 and not dose.get_node("Halo").visible, "halo : visible de loin (%.2f), effacé de près pour voir la gélule" % far_alpha)
	# --- Pilule rangée : tiroir/porte d'abord, puis la pilule, puis on referme sans la perdre ---
	var c: InteractiveContainer = null
	for i in 60:
		apt.spawn_dose(Vector3(1e9, 0.0, 1e9), 0.0)
		await process_frame
		for cont in apt.containers:
			if cont.dose == apt.get_dose() and cont.dose != null:
				c = cont
		if c != null:
			break
	_assert(c != null, "rangement : une pilule finit bien dans un tiroir ou un placard")
	if c != null:
		dose = apt.get_dose()
		rh.global_position = c.global_position
		main._pointed = null
		main.interact(rh)
		_assert(main._held_pill == null and c.is_open, "rangement fermé : la gâchette ouvre le rangement, la pilule cachée ne se prend pas à travers")
		await create_timer(0.5).timeout
		_assert(dose.is_visible_in_tree(), "rangement ouvert : la pilule se voit")
		rh.global_position = dose.global_position + Vector3(0.0, 0.1, 0.0)
		main._pointed = null
		main.interact(rh)
		_assert(main._held_pill == dose and c.dose == null and not is_instance_valid(apt._dose_marker), "rangement ouvert : la pilule se prend et quitte le rangement")
		rh.global_position = c.global_position
		main._pointed = null
		main.interact(rh)
		await create_timer(0.5).timeout
		_assert(not c.is_open and dose.is_visible_in_tree(), "on referme le rangement : la pilule tenue reste visible en main")
		main._consume_pill()
	# --- Easter egg : tolère une sortie brève de la zone (suivi perdu dans le dos) ---
	var egg: EasterEgg = main.easter
	for i in 20:
		egg.tick_hand(rh, true, true, 0.1)
	egg.tick_hand(rh, false, true, 0.3)
	for i in 21:
		egg.tick_hand(rh, true, true, 0.1)
	_assert(egg.state == EasterEgg.State.EGG, "easter egg : un court décrochage du suivi ne remet pas le compteur à zéro")
	egg._close_diploma()

	# Achats : on peut mettre de côté un article acheté, et le reprendre.
	var prof: PlayerProfile = main.profile
	prof.add_tokens(5000)
	var item_id := String(DecorCatalog.ITEMS[0]["id"])
	_assert(prof.buy(item_id) and prof.is_active(item_id), "achat : l'article acheté est activé")
	prof.toggle_active(item_id)
	_assert(not prof.is_active(item_id) and not (item_id in prof.active_items()), "achat : mis de côté, il n'est plus posé ni utilisable")
	prof.toggle_active(item_id)
	_assert(prof.is_active(item_id), "achat : on peut le réactiver")
	quit(0 if _failures == 0 else 1)


## Fait apparaître la pilule hors rangement (au sol ou sur une surface).
func _spawn_open_air(apt: MapBase) -> Dose:
	for i in 80:
		apt.spawn_dose(Vector3(1e9, 0.0, 1e9), 0.0)
		var d := apt.get_dose()
		if d != null and d.visible and not is_instance_valid(apt._dose_marker):
			return d
	return apt.get_dose()
