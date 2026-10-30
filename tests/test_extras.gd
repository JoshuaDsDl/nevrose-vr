extends SceneTree
## Tests des ajouts « terrain » : pilules dans les placards et GPS, objets jetables en Résistance,
## grenade, téléphone lisible, easter egg du champagne, spatialisation, voix du mode Résistance.
##   Godot --headless --path . --script res://tests/test_extras.gd

var _failures := 0


func _assert(cond: bool, label: String) -> void:
	if cond:
		print("  [OK] ", label)
	else:
		_failures += 1
		printerr("  [ECHEC] ", label)


func _initialize() -> void:
	print("=== TEST EXTRAS ===")
	LlmClient.force_offline = true

	# --- Téléphone : taille et lisibilité ---
	_assert(Phone.PHONE_HEIGHT >= 0.3 and Phone.SCREEN_HEIGHT >= 0.28, "téléphone : format agrandi (%.2f m de haut)" % Phone.PHONE_HEIGHT)
	var mm_per_px := Phone.SCREEN_HEIGHT / float(Phone.VIEWPORT_HEIGHT)
	var text_deg := rad_to_deg(atan2(31.0 * mm_per_px, 0.45)) # texte des messages à 45 cm
	_assert(text_deg > 1.5, "téléphone : texte des messages haut de %.1f° à 45 cm (≥ 1,5° lisible sur Quest 2)" % text_deg)

	# --- Spatialisation ---
	var front := AudioStreamPlayer3D.new()
	var back := AudioStreamPlayer3D.new()
	var listener := Node3D.new()
	root.add_child(listener)
	root.add_child(front)
	root.add_child(back)
	front.global_position = Vector3(0, 0, -3)
	back.global_position = Vector3(0, 0, 3)
	SpatialAudio.configure(front)
	SpatialAudio.tune(front, listener)
	SpatialAudio.tune(back, listener)
	_assert(front.panning_strength >= 2.0 and front.attenuation_filter_cutoff_hz > back.attenuation_filter_cutoff_hz + 4000.0, "son : un son derrière soi est plus sourd qu'un son devant (%.0f contre %.0f Hz)" % [back.attenuation_filter_cutoff_hz, front.attenuation_filter_cutoff_hz])

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.profile.persist = false

	# --- Easter egg ---
	var egg: EasterEgg = main.easter
	_assert(egg != null and egg.state == EasterEgg.State.IDLE, "easter egg : en veille au lancement")
	var cam: Node3D = main.xr_camera
	var hand: Node3D = main.right_hand
	hand.global_position = cam.global_position + Basis(Vector3.UP, cam.global_rotation.y) * Vector3(0.1, -0.85, 0.25)
	_assert(egg.at_butt(hand), "easter egg : main derrière, à hauteur de fesses = détecté")
	hand.global_position = cam.global_position + Basis(Vector3.UP, cam.global_rotation.y) * Vector3(0.1, -0.3, -0.4)
	_assert(not egg.at_butt(hand), "easter egg : main devant soi = non détecté")
	for i in 3:
		egg.tick_hand(hand, true, true, 1.0)
	_assert(egg.state == EasterEgg.State.IDLE, "easter egg : 3 secondes ne suffisent pas")
	egg.tick_hand(hand, true, false, 0.1)
	for i in 3:
		egg.tick_hand(hand, true, true, 1.0)
	_assert(egg.state == EasterEgg.State.IDLE, "easter egg : lâcher la gâchette remet le compteur à zéro")
	egg.tick_hand(hand, true, true, 1.0)
	_assert(egg.state == EasterEgg.State.EGG and is_instance_valid(egg._egg) and egg._egg.get_parent() == hand, "easter egg : 4 secondes = POP, l'œuf surprise est dans la main")
	egg.tick_hand(hand, false, true, 0.1)
	_assert(egg.state == EasterEgg.State.EGG, "easter egg : la gâchette encore tenue n'ouvre pas l'œuf")
	egg.tick_hand(hand, false, false, 0.1)
	egg.tick_hand(hand, false, true, 0.1)
	await process_frame
	_assert(egg.state == EasterEgg.State.OPEN and is_instance_valid(egg._diploma), "easter egg : nouvel appui = l'œuf s'ouvre sur le diplôme")
	var texts := ""
	for c in egg._diploma.get_children():
		if c is Label3D:
			texts += (c as Label3D).text + " "
	_assert(texts.contains("IMT Nord Europe") and texts.contains("DIPLÔME D'INGÉNIEUR"), "easter egg : le diplôme d'ingénieur IMT Nord Europe s'affiche")
	egg._close_diploma()
	_assert(egg.state == EasterEgg.State.IDLE, "easter egg : on peut recommencer")

	# --- Bêta test et musique du lobby ---
	var tokens0: int = main.profile.tokens
	main.lobby._on_beta_pressed()
	_assert(main.profile.tokens == tokens0 + LobbyWorld.BETA_TOKENS, "bêta test : +%d tokens au lobby" % LobbyWorld.BETA_TOKENS)
	_assert(main.music != null and main.music._player != null and main.music._player.stream != null, "musique : piste de lobby prête")
	_assert(main.music._player.stream.get_length() > 0.0 or main.music._player.stream is AudioStreamWAV, "musique : boucle valide")

	# --- Réels : la voix plafonne la note (sans parole, pas de succès) ---
	var script := String(ReelData.SCRIPTS[0]["script"])
	var long_talk := {"mic": true, "duration": ReelData.expected_duration(script) + 2.0, "speak_ratio": 0.8, "variation": 6.0, "avg_db": -20.0}
	_assert(ReelData.voice_cap(long_talk, script) == 10.0, "réels : une vraie lecture n'est pas plafonnée")
	var mute := {"mic": false, "duration": 10.0, "speak_ratio": 0.0}
	_assert(ReelData.voice_cap(mute, script) == 3.0, "réels : sans micro, plafond à 3")
	var silent := {"mic": true, "duration": 10.0, "speak_ratio": 0.02}
	_assert(ReelData.voice_cap(silent, script) == 2.5, "réels : micro muet ou silence, plafond à 2,5")
	var hit := {"score": 9.0, "views": 200000, "likes": 20000, "comments": 500, "shares": 800, "followers": 900}
	ReelData.apply_voice_cap(hit, 2.5, 100)
	_assert(is_equal_approx(float(hit["score"]), 2.5) and int(hit["views"]) < 20000, "réels : un réel silencieux perd ses vues (%d)" % int(hit["views"]))
	_assert(int(hit["likes"]) <= int(hit["views"]) * 0.35, "réels : likes toujours cohérents après plafond")

	# --- Mode Résistance : pilules, GPS, objets jetables ---
	main.start_game(Main.Mode.RESIST)
	var waited := 0
	while waited < 600 and not (main.nav != null and main.nav.is_ready()):
		await physics_frame
		waited += 1
	_assert(main.sandbox != null and main.sandbox.light, "résistance : bac à sable léger actif")
	_assert(main.nav != null and main.nav.is_ready(), "résistance : carte d'accessibilité calculée (%d cases)" % main.nav.reachable.size())
	_assert(main.phone != null and main.phone.is_in_hand and main.phone._gps_panel.visible, "résistance : téléphone en main avec le GPS vers la pilule")
	var apt: MapBase = main.apartment
	_assert(apt.find_child("kitchenFridge", true, false) != null and apt.get_node_or_null("Shell/kitchenFridge") != null, "résistance : les meubles restent en place")
	_assert(main.sandbox.props.size() > 5, "résistance : %d petits objets attrapables (canettes, assiettes…)" % main.sandbox.props.size())
	var all_small := true
	for p in main.sandbox.props:
		if is_instance_valid(p) and (p.mass > 8.5 or p.hanging):
			all_small = false
	_assert(all_small, "résistance : seuls les objets légers sont mobiles")
	var can: PropBody = main.sandbox.props[0]
	var rh: Node3D = main.right_hand
	rh.global_position = can.global_position + Vector3(0, 0.1, 0)
	rh.global_rotation = Vector3.ZERO
	await physics_frame
	var grabbed: bool = main.sandbox.grab(rh)
	if not grabbed:
		print("  [debug] prop=", can.name, " pos=", can.global_position, " layer=", can.collision_layer, " hand=", rh.global_position, " size=", can.size)
	_assert(grabbed, "résistance : on attrape un objet")
	main.sandbox.release(rh)
	can.damage(1000.0)
	await process_frame
	_assert(is_instance_valid(can) and not can.is_dead, "résistance : on jette les objets mais ils ne cassent pas")
	var info: Dictionary = main.nav.gps_info(main.xr_camera, apt.get_dose().global_position, 0)
	_assert(info.has("angle") and info.has("distance"), "résistance : le GPS donne direction et distance")
	main._tick_pill_gps()
	_assert(main.phone._gps_distance.text != "", "résistance : la distance à la pilule s'affiche")
	# Pilules : dans les placards au moins une fois sur deux, avec une lueur qui les trahit.
	var stored := 0
	var open_air := 0
	for i in 40:
		apt.spawn_dose(Vector3(1e9, 0.0, 1e9), 0.0)
		await process_frame
		if is_instance_valid(apt._dose_marker):
			stored += 1
			var c: InteractiveContainer = null
			for cont in apt.containers:
				if cont.dose == apt.get_dose():
					c = cont
			_assert(c != null and not apt.get_dose().visible and apt._dose_marker.visible, "pilules : rangée dans un placard, lueur visible") if stored == 1 else null
			if stored == 1 and c != null:
				c.interact()
				await process_frame
				await process_frame
				_assert(apt.get_dose().visible and not apt._dose_marker.visible, "pilules : le placard ouvert montre la pilule et éteint la lueur")
				c.close_now()
		else:
			open_air += 1
	_assert(stored >= 8 and open_air >= 8, "pilules : réparties entre placards (%d) et pièces (%d)" % [stored, open_air])
	var d := apt.get_dose()
	_assert(d.get_node_or_null("Halo") != null and d.get_node_or_null("Faisceau") != null, "pilules : halo et faisceau pour la repérer de loin")
	_assert(Dose.AURA_MAX_DISTANCE_M >= 12.0 and Dose.AURA_VOLUME_DB > -12.0, "pilules : le carillon s'entend à travers l'appartement")

	# --- Voix de la Résistance : toutes jouées, par extraits ---
	var voices: Node = main.creepy_voices
	_assert(voices._streams.size() == load("res://scripts/creepy_voices.gd").VOICE_COUNT, "voix : les %d fichiers sont chargés" % load("res://scripts/creepy_voices.gd").VOICE_COUNT)
	var seen := {}
	for i in 80: # le sac a déjà servi : deux tirages complets garantissent de tout voir
		seen[voices._next_voice_index()] = true
	_assert(seen.size() == load("res://scripts/creepy_voices.gd").VOICE_COUNT, "voix : le sac fait sortir toutes les voix")
	_assert(voices.max_simultaneous(0.1) >= 2, "voix : deux voix possibles dès le début")

	# --- Grenade en Chasse ---
	main.return_to_lobby()
	await process_frame
	main.profile.add_tokens(200)
	main.profile.buy("arme_grenade")
	main.start_game(Main.Mode.HUNT)
	waited = 0
	while waited < 600 and not (main.hunt != null and main.hunt.sandbox != null and main.hunt.started):
		await physics_frame
		waited += 1
	for i in 10:
		await physics_frame
	var box: HuntSandbox = main.hunt.sandbox
	_assert(box.weapon_id == "arme_grenade" and box.weapon_type() == "grenade", "grenade : équipée (meilleure arme possédée)")
	var near: PropBody = null
	for p in box.props:
		if is_instance_valid(p) and not p.hanging and p.mass < 30.0:
			near = p
			break
	var hp0 := near.hp
	var boom_pos := near.global_position + Vector3(0.4, 0.2, 0.0)
	var count0 := box.destroyed_count
	box.explode(boom_pos, 3.8, 16.0)
	await process_frame
	_assert(not is_instance_valid(near) or near.hp < hp0 or box.destroyed_count > count0, "grenade : l'explosion abîme les objets alentour")
	_assert(box.throw_grenade(main.right_hand) and box.grenades_thrown == 1, "grenade : jetable à la gâchette")
	_assert(not box.throw_grenade(main.right_hand), "grenade : une seule à la fois")
	var thrown := box.get_node_or_null("Grenade")
	_assert(thrown != null and thrown is RigidBody3D, "grenade : le projectile existe, avec le vrai modèle")
	# La gâchette droite tire ou lance via Main.interact, la gauche reste normale.
	main.interact(main.right_hand)

	LlmClient.force_offline = false
	print("=== RESULTAT: %s (%d échec(s)) ===" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)
