extends SceneTree
## Tests du bac à sable de la Chasse : objets physiques, prise et lancer, casse, armes de la
## boutique, trous dans les murs, saut, GPS du téléphone, accessibilité des plaques.
##   Godot --headless --path . --script res://tests/test_sandbox.gd

var _failures := 0


func _assert(cond: bool, label: String) -> void:
	if cond:
		print("  [OK] ", label)
	else:
		_failures += 1
		printerr("  [ECHEC] ", label)


func _initialize() -> void:
	print("=== TEST BAC À SABLE (CHASSE) ===")
	LlmClient.force_offline = true
	_assert(DecorCatalog.weapons().size() == 4, "boutique : 4 armes")
	for w in DecorCatalog.weapons():
		_assert(WeaponModel.build(String(w["id"])).get_child_count() >= 1, "arme « %s » : modèle construit" % w["name"])

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.profile.persist = false
	main.profile.add_tokens(100)
	var lobby: LobbyWorld = main.lobby
	_assert(lobby.shop_cards.has("arme_batte") and lobby.shop_cards.has("arme_masse"), "lobby : les armes sont en vente")
	(lobby.shop_cards["arme_batte"] as LobbyButton).interact()
	_assert(main.profile.owns("arme_batte") and main.profile.tokens == 72, "lobby : la batte s'achète avec les tokens (28)")
	(lobby.shop_cards["arme_marteau"] as LobbyButton).interact()

	main.start_game(Main.Mode.HUNT)
	var waited := 0
	while waited < 600 and not (main.hunt != null and main.hunt.sandbox != null and main.hunt.started):
		await physics_frame
		waited += 1
	var hunt: HuntMode = main.hunt
	var box: HuntSandbox = hunt.sandbox
	_assert(hunt.started and box != null, "chasse : bac à sable prêt")
	for i in 20:
		await physics_frame
	_assert(box.props.size() > 20, "bac à sable : %d objets devenus physiques" % box.props.size())
	_assert(hunt.rejected.size() > 0, "accessibilité : des points inaccessibles écartés (%d)" % hunt.rejected.size())
	_assert(hunt._reachable.size() > 500, "accessibilité : carte du sol praticable (%d cases)" % hunt._reachable.size())
	var all_reachable := true
	for p in hunt.patches:
		var front: Vector3 = p.global_position + p.normal * 0.9
		if not hunt._reachable.has(hunt._cell_of(front)):
			all_reachable = false
	_assert(all_reachable, "accessibilité : la plaque active est toujours atteignable à pied")

	# --- Armes ---
	_assert(box.weapon_id == "arme_batte" and is_instance_valid(box.weapon_node), "armes : la meilleure arme possédée est équipée")
	_assert(box.weapon_node.get_parent() == main.right_hand, "armes : tenue dans la main droite")
	box.cycle_weapon()
	_assert(box.weapon_id == "" and box.weapon_node == null, "armes : après la dernière arme, retour aux poings")
	box.cycle_weapon()
	_assert(box.weapon_id == "arme_marteau" and is_instance_valid(box.weapon_node), "armes : puis le cycle repart sur la première arme possédée")
	box.equip("arme_batte")

	# --- Prise et lancer ---
	var prop: PropBody = null
	for p in box.props:
		if is_instance_valid(p) and not p.hanging and p.mass < 5.0 and p.global_position.y > 0.05:
			prop = p
			break
	_assert(prop != null, "objets : un petit objet libre existe")
	if prop != null:
		var hand: Node3D = main.right_hand
		hand.global_position = prop.global_position + Vector3(0, 0.12, 0)
		hand.global_rotation = Vector3.ZERO
		var y0 := prop.global_position.y
		_assert(box.grab(hand) and box.is_holding(hand), "objets : on attrape l'objet touché")
		for i in 24:
			hand.global_position += Vector3(0, 0.05, 0)
			await physics_frame
		_assert(prop.global_position.y > y0 + 0.5, "objets : l'objet suit la main (%.2f m plus haut)" % (prop.global_position.y - y0))
		box.release(hand)
		_assert(not box.is_holding(hand) and prop.gravity_scale == 1.0, "objets : relâché, il retombe")

	# --- Casse ---
	var victim: PropBody = null
	for p in box.props:
		if is_instance_valid(p) and p != prop and not p.hanging:
			victim = p
			break
	var before := box.destroyed_count
	victim.damage(1000.0)
	await process_frame
	await process_frame
	_assert(box.destroyed_count == before + 1 and not is_instance_valid(victim), "casse : l'objet détruit disparaît et est compté")
	_assert(HuntMode.compute_tokens(5, 9) == HuntMode.compute_tokens(5) + 3, "tokens : +1 tous les 3 objets cassés")
	var heavy: PropBody = null
	for p in box.props:
		if is_instance_valid(p) and p.mass > 60.0:
			heavy = p
			break
	_assert(heavy != null and heavy.hp > 6.0, "casse : un gros meuble encaisse plus (%.0f PV)" % (heavy.hp if heavy != null else 0.0))

	# --- Coup d'arme sur un objet ---
	var target: PropBody = null
	for p in box.props:
		if is_instance_valid(p) and not p.hanging and p.mass < 20.0:
			target = p
			break
	var hp_before := target.hp
	var tip := target.global_position
	box._resolve_swing(main.right_hand, tip, tip - Vector3(0.3, 0, 0), Vector3(5, 0, 0), 2.8)
	_assert(not is_instance_valid(target) or target.hp < hp_before, "armes : un coup abîme l'objet touché")

	# --- Murs : percer à coups répétés ---
	var holes_before := box._holes.size()
	var wall_pos := Vector3(2.0, 1.4, 3.0)
	for i in 3:
		box._wall_hit(wall_pos, Vector3(0, 0, -1), 1.0)
	await process_frame
	_assert(box._holes.size() == holes_before + 1 and box._holes[-1].is_broken, "murs : trois coups percent un trou")
	box._wall_hit(Vector3(1, 0, 1), Vector3.UP, 5.0)
	_assert(box._holes.size() == holes_before + 1, "murs : le sol ne se perce pas")
	box._wall_hit(Vector3(2.0, 2.7, 1.0), Vector3.DOWN, 3.0)
	_assert(box._holes.size() == holes_before + 2, "plafond : un coup de masse suffit à le percer")

	# --- Saut ---
	var y_ground: float = main.xr_origin.position.y
	main.jump()
	for i in 6:
		await physics_frame
	_assert(main._jump_y > 0.0 and main.xr_origin.position.y > y_ground, "saut : le joueur décolle")
	for i in 80:
		await physics_frame
	_assert(main._jump_y == 0.0 and is_equal_approx(main.xr_origin.position.y, y_ground), "saut : il retombe au sol")

	# --- GPS ---
	_assert(main.phone != null and main.phone._gps_panel != null and main.phone._gps_panel.visible, "GPS : le panneau est affiché sur le téléphone")
	_assert(main.phone.is_in_hand, "GPS : le téléphone est sorti d'office")
	var info := hunt.gps_info()
	_assert(info.has("angle") and info.has("distance") and absf(float(info["angle"])) <= PI + 0.001, "GPS : angle et distance fournis")
	var dist_before: float = info["distance"]
	main.xr_origin.rotation.y += PI
	var turned := hunt.gps_info()
	_assert(absf(absf(float(turned["angle"]) - float(info["angle"])) - PI) < 0.5 or absf(absf(float(turned["angle"]) - float(info["angle"])) - PI) > 5.5, "GPS : la flèche tourne avec le regard")
	main.phone.update_gps(0.8, 7.0, 0)
	_assert(main.phone._gps_distance.text == "7 m", "GPS : la distance s'affiche")
	main.phone.update_gps(0.0, 1.0, 1)
	_assert(main.phone._gps_distance.text.begins_with("TOUT") and main.phone._gps_hint.text == "au plafond", "GPS : « tout près » et plafond")
	_assert(dist_before > 0.0, "GPS : distance positive")

	# --- Boutons ---
	main._on_button_pressed("grip_click", main.right_hand)
	main._on_button_released("grip_click", main.right_hand)
	var weapon_before: String = box.weapon_id
	main._on_button_pressed("primary_click", main.right_hand)
	_assert(box.weapon_id != weapon_before, "boutons : le clic du stick droit change d'arme")

	# --- Retour au lobby ---
	main._tick_lobby_hold(true, 2.0)
	await process_frame
	_assert(main.lobby != null and main._movement_body.collision_mask == 1, "lobby : retour propre (masque du joueur remis)")

	LlmClient.force_offline = false
	print("=== RESULTAT: %s (%d échec(s)) ===" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)
