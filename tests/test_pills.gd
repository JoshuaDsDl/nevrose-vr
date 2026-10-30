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
