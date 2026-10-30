extends SceneTree
## Tests des deux modes de jeu, de la boutique et des tokens.
##   Godot --headless --path . --script res://tests/test_modes.gd

var _failures := 0


func _assert(cond: bool, label: String) -> void:
	if cond:
		print("  [OK] ", label)
	else:
		_failures += 1
		printerr("  [ECHEC] ", label)


func _initialize() -> void:
	print("=== TEST MODES / BOUTIQUE ===")

	# --- Profil et boutique ---
	var profile := PlayerProfile.new()
	profile.persist = false
	_assert(not profile.buy("cadre_paysage"), "boutique : achat refusé sans tokens")
	profile.add_tokens(20)
	_assert(profile.buy("cadre_paysage") and profile.tokens == 12, "boutique : achat débité (8 tokens)")
	_assert(profile.owns("cadre_paysage"), "boutique : objet possédé")
	_assert(not profile.buy("cadre_paysage"), "boutique : pas d'achat en double")
	_assert(not profile.buy("inconnu"), "boutique : objet inconnu refusé")
	_assert(Main.compute_resist_tokens(0.0, 0) == 0, "tokens résistance : 0 s = 0")
	_assert(Main.compute_resist_tokens(300.0, 2) > Main.compute_resist_tokens(60.0, 2), "tokens résistance : plus on tient, plus on gagne")
	_assert(HuntMode.compute_tokens(5) == 33, "tokens chasse : 8 + 5 par mur")

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	# --- Lobby : cartes de mode + boutique ---
	var lobby: LobbyWorld = main.lobby
	_assert(lobby.card_resist != null and lobby.card_hunt != null, "lobby : deux cartes de mode")
	_assert(lobby.shop_cards.size() == DecorCatalog.ITEMS.size(), "lobby : une carte par décoration (%d)" % lobby.shop_cards.size())
	var shop_id := "radio"
	_assert(not (lobby.shop_cards[shop_id] as LobbyButton).enabled, "lobby : objet trop cher grisé")
	main.profile.persist = false
	main.profile.add_tokens(30)
	await process_frame
	_assert((lobby.shop_cards[shop_id] as LobbyButton).enabled, "lobby : objet achetable une fois les tokens gagnés")
	(lobby.shop_cards[shop_id] as LobbyButton).interact()
	_assert(main.profile.owns(shop_id), "lobby : la carte achète la décoration")
	main.profile.buy("nounours")
	main.profile.buy("lampe_table")

	# --- Mode Chasse ---
	main._pointed = lobby.card_hunt
	main.interact()
	for i in 6:
		await physics_frame
	_assert(main.mode == Main.Mode.HUNT, "chasse : mode Chasse actif")
	var apt: MapBase = main.apartment
	_assert(not apt.get_node("Shell/mayozedong_framed").visible, "décor : tableau non acheté invisible")
	_assert(apt.get_node_or_null("Shell/Deco_radio") != null, "décor : la radio achetée est présente")
	_assert(apt.get_node_or_null("Shell/Deco_nounours") != null, "décor : le nounours acheté est présent")
	var hunt: HuntMode = main.hunt
	_assert(hunt != null and hunt.started, "chasse : HuntMode démarré")
	_assert(hunt.candidates.size() + hunt.patches.size() >= hunt.target_count, "chasse : assez de murs candidats (%d)" % (hunt.candidates.size() + hunt.patches.size()))
	_assert(hunt.current != null and hunt.current.active, "chasse : une plaque cogne")
	_assert(not main.creepy_voices.enabled, "chasse : pas de voix de folie")
	_assert(hunt.voice_streams.size() == 15, "chasse : les 15 voix du jeu sont chargées pour les murs")
	var seen_voices := {}
	for i in 30:
		seen_voices[hunt._next_voice_index()] = true
	_assert(seen_voices.size() == 15, "chasse : le sac de voix les fait toutes sortir (%d/15)" % seen_voices.size())
	hunt._voice_clock = 0.0
	for i in 3:
		await physics_frame
	_assert(hunt.voices_played >= 1 and hunt.current.voices_played >= 1, "chasse : une voix sort du mur qui cogne")
	var voice_node := hunt.current.get_node_or_null("Voix") as AudioStreamPlayer3D
	_assert(voice_node != null and voice_node.playing and voice_node.stream != null, "chasse : la voix est jouée depuis la plaque")
	var s0: float = main.sanity
	for i in 20:
		await physics_frame
	_assert(main.sanity == s0, "chasse : la folie ne monte pas")

	# La plaque est visée par le rayon puis frappée par la gâchette.
	var first := hunt.current
	main.xr_origin.global_position = first.global_position + first.normal * 1.2 - Vector3(0, first.global_position.y, 0)
	main.xr_camera.look_at_from_position(first.global_position + first.normal * 1.2, first.global_position, Vector3.UP)
	for i in 3:
		await physics_frame
	main._tick_interaction_ray()
	_assert(main._pointed == first, "chasse : le rayon vise la plaque qui cogne")
	var total := hunt.target_count
	for w in total:
		var patch := hunt.current
		_assert(patch != null and patch.active, "chasse : plaque %d active" % (w + 1))
		for k in KnockPatch.HITS_TO_BREAK:
			patch.interact()
		await process_frame
		_assert(patch.is_broken, "chasse : plaque %d brisée en %d coups" % [w + 1, KnockPatch.HITS_TO_BREAK])
		if w < total - 1:
			await create_timer(3.1).timeout
	_assert(hunt.monster != null, "chasse : le monstre apparaît au dernier mur")
	await create_timer(0.3).timeout
	_assert(hunt.monster != null and hunt.monster.get_node_or_null("Model") != null, "chasse : modèle animé chargé")
	var ap := hunt.monster.find_children("*", "AnimationPlayer", true, false)
	_assert(not ap.is_empty() and (ap[0] as AnimationPlayer).is_playing(), "chasse : le monstre est animé")
	await create_timer(6.5).timeout
	_assert(main.game_over, "chasse : fin de partie après la disparition du monstre")
	_assert(main.last_tokens == HuntMode.compute_tokens(total), "chasse : tokens = %d" % main.last_tokens)
	var tokens_avant: int = main.profile.tokens
	main.interact()
	await process_frame
	_assert(main.lobby != null and main.mode == Main.Mode.NONE, "chasse : retour au lobby")
	_assert(main.profile.owns("radio"), "lobby : les achats sont conservés")

	# --- Retour au lobby par maintien du bouton (en pleine partie) ---
	main.start_game(Main.Mode.RESIST)
	await process_frame
	_assert(main.game_started and main.lobby == null, "lobby : partie en cours avant le maintien")
	main._tick_lobby_hold(true, 0.5)
	main._tick_lobby_hold(false, 0.1)
	_assert(main.game_started, "lobby : un appui trop court ne fait rien")
	main._tick_lobby_hold(true, 0.7)
	main._tick_lobby_hold(true, 0.7)
	_assert(main.game_started, "lobby : le maintien se remet à zéro quand on lâche")
	main._tick_lobby_hold(true, 0.8)
	await process_frame
	_assert(not main.game_started and main.lobby != null and main.mode == Main.Mode.NONE, "lobby : maintien du bouton = retour au lobby")

	# --- Mode Résistance : pilule visible et loin ---
	main.start_game(Main.Mode.RESIST)
	await process_frame
	_assert(absf(main.sanity - Main.START_SANITY) < 2.0, "résistance : on démarre déjà fou (%.1f)" % main.sanity)
	var dose: Dose = main.apartment.get_dose()
	_assert(dose != null and dose.visible and dose.get_node_or_null("Faisceau") != null, "résistance : pilule visible avec son faisceau")
	var d := Vector2(dose.global_position.x - main.xr_camera.global_position.x, dose.global_position.z - main.xr_camera.global_position.z).length()
	_assert(d >= 4.9, "résistance : pilule à %.1f m du départ" % d)
	_assert(main.apartment.containers.all(func(c): return not c.is_locked), "résistance : plus aucun verrou")
	_assert(main.apartment.get_node_or_null("Key_KitchenDrawerKey") == null, "résistance : plus de clés cachées")
	_assert(main._pill_hint() != "", "résistance : indice de direction sur le téléphone")
	_assert(tokens_avant >= 0, "profil cohérent")

	print("=== RESULTAT: %s (%d échec(s)) ===" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)
