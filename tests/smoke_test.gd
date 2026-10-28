class_name SmokeTest
extends SceneTree
## Test fonctionnel headless — lance :
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/smoke_test.gd
##
## Scénarios :
##   A — la scène principale s'instancie, les nœuds XR existent, le lobby précède la partie
##   B — l'appartement procédural est construit (coquille + meubles + conteneurs)
##   C — la jauge de schizo monte avec le temps (GDD §5.2)
##   D — la pilule spawne ; la prendre soulage la schizo (GDD §5.1)
##   E — un conteneur s'ouvre et révèle son contenu
##   F — le snap turn 45° tourne l'origine (GDD §4/§8)

var _failures := 0


func _assert(cond: bool, label: String) -> void:
	if cond:
		print("  [OK] ", label)
	else:
		_failures += 1
		printerr("  [ECHEC] ", label)


func _initialize() -> void:
	print("=== SMOKE TEST NÉVROSE ===")
	var packed: PackedScene = load("res://scenes/main.tscn")
	_assert(packed != null, "A: main.tscn se charge")
	if packed == null:
		_finish()
		return

	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	# --- A : structure XR ---
	_assert(main.get_node_or_null("XROrigin3D/XRCamera3D") != null, "A: XRCamera3D présente")
	_assert(main.get_node_or_null("XROrigin3D/LeftHand") != null, "A: manette gauche présente")
	_assert(main.get_node_or_null("XROrigin3D/RightHand") != null, "A: manette droite présente")
	_assert(main.is_xr_active() == false, "A: headless = fallback bureau (OpenXR inactif)")

	# --- A : lobby (avant le départ) ---
	var lobby: LobbyWorld = main.lobby
	_assert(lobby != null, "A: lobby présent au boot")
	_assert(not main.game_started, "A: partie non lancée au boot")
	_assert(main.apartment == null, "A: appartement absent avant le départ")
	_assert(main.phone == null, "A: téléphone absent avant le départ")
	var sanity_lobby: float = main.sanity
	for i in 10:
		await physics_frame
	_assert(main.sanity == sanity_lobby, "A: folie figée dans le lobby")
	lobby.computer.on_unpointed()
	_assert(not lobby.computer.play_prompt.visible, "A: prompt masqué quand l'ordinateur n'est pas visé")
	lobby.computer.on_pointed()
	_assert(lobby.computer.play_prompt.visible, "A: prompt visible au survol de l'ordinateur")

	# Le vrai dispatch passe par l'objet pointé puis par interact().
	main._pointed = main.lobby.computer
	main.interact()
	await process_frame
	await process_frame
	_assert(main.game_started, "A: l'ordinateur lance la partie")
	_assert(main.lobby == null, "A: référence du lobby effacée après le départ")
	_assert(not is_instance_valid(lobby), "A: lobby libéré après le départ")

	# --- A : smartphone (créé après le départ) ---
	_assert(main.phone != null, "A: smartphone Messenger présent")
	_assert(not main.phone.is_in_hand, "A: téléphone initialement dans la poche")
	main.phone.toggle_pocket()
	_assert(main.phone.is_in_hand, "A: sortie du téléphone de la poche vers la main")
	main.phone.toggle_pocket()
	_assert(not main.phone.is_in_hand, "A: retour du téléphone dans la poche")

	# --- B : appartement (Map2Extended — salon + cuisine + extension) ---
	var apt: MapBase = main.apartment
	_assert(apt != null, "B: appartement (MapBase) instancié")
	_assert(apt.get_node_or_null("Shell/Floor") != null, "B: sol construit")
	_assert(apt.get_node_or_null("Shell/WallN") != null, "B: mur nord construit")
	_assert(apt.get_node_or_null("Kitchen") != null, "B: cuisine construite")
	_assert(apt.get_node_or_null("LivingRoom") != null, "B: salon construit")
	_assert(apt.containers.size() >= 5, "B: conteneurs interactifs (tiroirs + placard) : %d" % apt.containers.size())
	_assert(apt.get_node_or_null("MugMimic") != null, "B: mimic statique présent (round 1)")
	_assert(apt.get_node_or_null("SideTableMimic") != null, "B: 2e mimic statique présent (table d'appoint)")
	_assert(apt.mimics.size() >= 2, "B: au moins 2 mimics dans la map : %d" % apt.mimics.size())
	_assert(apt.get_node_or_null("Extension") == null, "B: ancien runtime Extension absent")
	_assert(apt.get_node_or_null("Shell/ExtensionEst") != null, "B: extension éditée présente")
	var chemins_extension := [
		"Shell/ExtensionEst/Chambre/LitDouble",
		"Shell/ExtensionEst/Chambre/Bureau",
		"Shell/ExtensionEst/Garage/LaveLinge",
		"Shell/ExtensionEst/SDB/Baignoire",
		"Shell/ExtensionEst/Dressing/Armoire1",
	]
	for chemin in chemins_extension:
		var meuble := apt.get_node_or_null(chemin) as Node3D
		_assert(meuble != null, "B: meuble présent : %s" % chemin)
		if meuble != null:
			_assert(is_equal_approx(meuble.scale.x, meuble.scale.y) and is_equal_approx(meuble.scale.x, meuble.scale.z), "B: échelle uniforme : %s" % chemin)

	# --- B : pitch de la souris en fallback bureau ---
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var mouse_motion := InputEventMouseMotion.new()
	mouse_motion.relative = Vector2(0.0, 100.0)
	main._update_desktop_look(mouse_motion.relative)
	_assert(not is_zero_approx(main.xr_camera.rotation.x), "B: le pitch souris modifie la caméra")
	mouse_motion.relative = Vector2(0.0, 100000.0)
	main._update_desktop_look(mouse_motion.relative)
	_assert(is_equal_approx(main.xr_camera.rotation.x, deg_to_rad(-80.0)), "B: le pitch reste clampé à -80°")
	mouse_motion.relative = Vector2(0.0, -200000.0)
	main._update_desktop_look(mouse_motion.relative)
	_assert(is_equal_approx(main.xr_camera.rotation.x, deg_to_rad(80.0)), "B: le pitch reste clampé à +80°")
	main._desktop_pitch = 0.0
	main.xr_camera.rotation.x = 0.0

	# --- B : collisions de la capsule avec les murs et les meubles ---
	main.xr_origin.position = Vector3(6.5, 1.7, 2.0)
	main._move_with_collisions(Vector3(0.0, 0.0, -2.0))
	await physics_frame
	await physics_frame
	_assert(main.xr_origin.position.z > 1.4, "B: le mur du couloir bloque la capsule (z = %.2f)" % main.xr_origin.position.z)
	main.xr_origin.position = Vector3(1.675, 1.7, -1.0)
	main._move_with_collisions(Vector3(0.0, 0.0, -3.0))
	await physics_frame
	await physics_frame
	_assert(main.xr_origin.position.z > -2.15, "B: le frigo bloque la capsule (z = %.2f)" % main.xr_origin.position.z)
	main.xr_origin.position = Vector3(0.0, 1.7, 0.0)
	main.xr_origin.rotation = Vector3.ZERO
	main.xr_camera.rotation = Vector3.ZERO
	main._desktop_yaw = 0.0
	main._desktop_pitch = 0.0

	# --- B : une seule voix à la fois, intro comprise ---
	_assert(main.creepy_voices._is_voice_playing(), "B: le murmure d'introduction est actif")
	main.creepy_voices._play_random_voice(0.5)
	var voices_playing := 0
	for player in main.creepy_voices._players:
		if player.playing:
			voices_playing += 1
	_assert(voices_playing == 1, "B: aucune voix ne se superpose à l'intro")
	for player in main.creepy_voices._players:
		player.stop()
	main.creepy_voices._play_random_voice(0.5)
	voices_playing = 0
	for player in main.creepy_voices._players:
		if player.playing:
			voices_playing += 1
	_assert(voices_playing == 1, "B: une voix aléatoire démarre après l'arrêt des players")
	for player in main.creepy_voices._players:
		player.stop()

	# --- C : montée de la schizo ---
	var s0: float = main.sanity
	for i in 30:
		await physics_frame
	_assert(main.sanity > s0, "C: la schizo monte toute seule (%.2f -> %.2f)" % [s0, main.sanity])

	# --- D : dose ---
	_assert(is_instance_valid(apt._dose), "D: une dose a spawné")
	var s_before_dose: float = main.sanity
	main.on_dose_taken() # simule la prise (la dose se libère dans la foulée)
	await process_frame
	_assert(main.sanity < s_before_dose, "D: la dose reset la schizo (%.2f -> %.2f)" % [s_before_dose, main.sanity])
	_assert(main.dose_count == 1, "D: compteur de doses = 1")

	# --- E : conteneur ---
	# On prend le premier tiroir NON verrouillé (un tiroir verrouillé
	# répondrait par un flash "verrouillé" au lieu de s'ouvrir).
	var drawer: InteractiveContainer = null
	for c in apt.containers:
		if c.mode == InteractiveContainer.Mode.SLIDE and not c.is_locked:
			drawer = c
			break
	_assert(drawer != null, "E: tiroir trouvé")
	drawer.interact()
	await create_timer(0.6).timeout
	_assert(drawer.is_open, "E: le tiroir s'ouvre")
	_assert(drawer.position.z > -2.1, "E: le tiroir a glissé (z = %.2f)" % drawer.position.z)
	drawer.interact()
	await create_timer(0.6).timeout
	_assert(not drawer.is_open, "E: le tiroir se referme")

	# --- E+ : dissolution de la tasse mimic ---
	var mug_mimic := apt.get_node("MugMimic") as Mimic
	main._pointed = mug_mimic
	var sanity_avant_mimic: float = main.sanity
	main.interact()
	_assert(mug_mimic._dissolving, "E+: la tasse mimic commence à se dissoudre")
	_assert(is_equal_approx(main.sanity, sanity_avant_mimic + 6.0), "E+: purger la tasse ajoute 6 de sanity")
	await create_timer(0.5).timeout
	_assert(not is_instance_valid(mug_mimic), "E+: la tasse mimic est libérée après sa dissolution")
	# Le rayon a déjà nettoyé la cible expirée : une nouvelle interaction
	# ne doit ni la réutiliser ni appliquer une seconde pénalité.
	var sanity_apres_mimic: float = main.sanity
	main.interact()
	_assert(is_equal_approx(main.sanity, sanity_apres_mimic), "E+: seconde interaction sans crash ni nouvelle pénalité")
	main._pointed = null

	# --- E+ : façades et fermeture déterministe des conteneurs ---
	var garage_drawer := apt.get_node("GarageDrawer") as InteractiveContainer
	var fridge_door := apt.get_node("FridgeDoor") as InteractiveContainer
	var closet_door := apt.get_node("ClosetDoor") as InteractiveContainer
	_assert(garage_drawer.front_mesh.name == "drawer", "E+: GarageDrawer utilise la façade drawer du GLB")
	_assert(fridge_door.front_mesh.name == "doorFridge", "E+: FridgeDoor utilise la façade doorFridge du GLB")
	_assert(closet_door.mode == InteractiveContainer.Mode.SLIDE, "E+: ClosetDoor fonctionne en coulissement")
	var garage_material: Material = garage_drawer.front_mesh.material_override
	garage_drawer.on_pointed()
	garage_drawer.on_unpointed()
	_assert(garage_drawer.front_mesh.material_overlay == null, "E+: la surbrillance de GarageDrawer disparaît au survol sortant")
	_assert(garage_drawer.front_mesh.material_override == garage_material, "E+: le survol ne remplace pas le matériau de GarageDrawer")
	# Ne pas faire fuiter une surbrillance dans les scénarios suivants.
	garage_drawer.front_mesh.material_overlay = null
	garage_drawer.interact()
	garage_drawer.close_now() # Fermeture volontairement pendant le tween d'ouverture.
	_assert(not garage_drawer.is_open, "E+: close_now ferme GarageDrawer pendant son tween")
	_assert(garage_drawer.position.is_equal_approx(garage_drawer._closed_pos), "E+: close_now restaure la position fermée")
	_assert(is_equal_approx(garage_drawer.rotation.y, garage_drawer._closed_rot_y), "E+: close_now restaure la rotation fermée")

	# Le placard à forcer doit s'ouvrir après trois interactions, le tiroir
	# de cuisine doit reconnaître sa propre clé.
	for i in 3:
		closet_door.interact()
	await create_timer(0.45).timeout
	_assert(closet_door.is_open and not closet_door.is_locked, "E+: le placard de cuisine s'ouvre après trois forcings")
	closet_door.close_now()
	var kitchen_drawer := apt.get_node("KitchenDrawerKey") as InteractiveContainer
	kitchen_drawer.interact(kitchen_drawer.required_key)
	await create_timer(0.45).timeout
	_assert(kitchen_drawer.is_open and not kitchen_drawer.is_locked, "E+: le tiroir de cuisine s'ouvre avec sa clé")
	kitchen_drawer.close_now()

	# --- E+ : pilule révélée dans GarageDrawer, prioritaire sur sa façade ---
	# La dose de la section D réapparaît après 2 s. On attend sa fin avant de
	# remplacer temporairement le contenu du tiroir pour éviter tout écrasement.
	await create_timer(2.1).timeout
	var dose_initiale_tiroir: Node3D = garage_drawer.dose
	var dose_test := Dose.new()
	dose_test.name = "DoseTestConteneur"
	garage_drawer.add_child(dose_test)
	dose_test.position = garage_drawer.content_offset
	garage_drawer.dose = dose_test
	dose_test.visible = true
	dose_test.monitoring = true
	dose_test.monitorable = true
	if not garage_drawer.is_open:
		garage_drawer.interact()
	await create_timer(0.45).timeout

	# Position simple : un mètre devant la façade, sans autre meuble sur le rayon.
	# La caméra vise le centre de la pilule, comme en fallback bureau.
	var transform_origine_avant: Transform3D = main.xr_origin.transform
	var transform_camera_avant: Transform3D = main.xr_camera.transform
	var yaw_avant_pilule: float = main._desktop_yaw
	var pitch_avant_pilule: float = main._desktop_pitch
	var direction_face := garage_drawer.global_transform.basis.z.normalized()
	main.xr_origin.global_position = dose_test.global_position + direction_face
	main.xr_origin.rotation = Vector3.ZERO
	main.xr_camera.transform = Transform3D.IDENTITY
	main._desktop_yaw = 0.0
	main._desktop_pitch = 0.0
	main.xr_camera.look_at(dose_test.global_position, Vector3.UP)
	main._tick_interaction_ray()
	_assert(main._pointed == garage_drawer.dose and main._pointed == dose_test, "E+: le rayon vise la pilule révélée plutôt que GarageDrawer")
	main.interact()
	_assert(main._held_pill == garage_drawer.dose and main._held_pill == dose_test, "E+: interact ramasse la pilule contenue dans GarageDrawer")

	# Ne pas consommer la dose : le test ne doit changer ni le compteur ni la run.
	main._pointed = null
	if main._held_pill == dose_test:
		main._held_pill = null
	if is_instance_valid(dose_test):
		dose_test.queue_free()
	garage_drawer.dose = null
	garage_drawer.close_now()
	if is_instance_valid(dose_initiale_tiroir):
		garage_drawer.dose = dose_initiale_tiroir
	main.xr_origin.transform = transform_origine_avant
	main.xr_camera.transform = transform_camera_avant
	main._desktop_yaw = yaw_avant_pilule
	main._desktop_pitch = pitch_avant_pilule
	await process_frame

	# --- E+ : ouverture et fermeture de la porte d'entrée ---
	var entrance_door: EntranceDoor = null
	if apt.has_node("EntranceDoor"):
		entrance_door = apt.get_node("EntranceDoor") as EntranceDoor
	elif apt.has_node("Shell/EntranceDoor"):
		# La coquille instanciée par Map2Extended ajoute le niveau Shell.
		entrance_door = apt.get_node("Shell/EntranceDoor") as EntranceDoor
	_assert(entrance_door != null, "E+: porte d'entrée présente")
	if entrance_door != null:
		_assert(entrance_door.get_node_or_null("area") is Area3D, "E+: la porte d'entrée possède son enfant area")
		var rotation_fermee: float = entrance_door.rotation.y
		entrance_door.interact()
		await create_timer(0.45).timeout
		_assert(not is_equal_approx(entrance_door.rotation.y, rotation_fermee), "E+: la porte d'entrée pivote à l'ouverture")
		entrance_door.interact()
		await create_timer(0.45).timeout
		_assert(is_equal_approx(entrance_door.rotation.y, rotation_fermee), "E+: la porte d'entrée retrouve sa rotation fermée")
		# Une troisième ouverture doit laisser la capsule passer dans le couloir.
		main.xr_origin.position = Vector3(3.4, 1.7, 2.0)
		entrance_door.interact()
		await create_timer(0.45).timeout
		main._move_with_collisions(Vector3(2.0, 0.0, 0.0))
		await physics_frame
		await physics_frame
		_assert(main.xr_origin.position.x > 4.3, "E+: la porte ouverte laisse passer le joueur (x = %.2f)" % main.xr_origin.position.x)
		entrance_door.interact()

	# --- E+ : carillon spatial de la pilule, limité à cinq mètres ---
	var dose_audio := apt.get_dose()
	_assert(is_instance_valid(dose_audio), "E+: une dose est disponible pour le test audio")
	if is_instance_valid(dose_audio):
		var audio_dose: AudioStreamPlayer3D = null
		for enfant in dose_audio.get_children():
			if enfant is AudioStreamPlayer3D:
				audio_dose = enfant as AudioStreamPlayer3D
				break
		_assert(audio_dose != null, "E+: la pilule possède un AudioStreamPlayer3D")
		if audio_dose != null:
			_assert(audio_dose.stream != null, "E+: le carillon de la pilule possède un stream")
			_assert(audio_dose.max_distance > 0.0 and audio_dose.max_distance <= 5.0, "E+: la portée du carillon ne dépasse pas 5 m (%.2f)" % audio_dose.max_distance)

	# --- E+ : cooldown des notifications du téléphone ---
	var derniere_alerte_ms: int = main.phone._last_alert_notification_ms
	main.phone.receive_message("Test routine", false)
	_assert(main.phone._last_alert_notification_ms == derniere_alerte_ms, "E+: un message ordinaire ne déclenche pas de notification d'alerte")
	main.phone.receive_message("Test alerte", true)
	var premiere_alerte_ms: int = main.phone._last_alert_notification_ms
	_assert(premiere_alerte_ms != derniere_alerte_ms, "E+: une alerte met à jour l'horodatage de notification")
	main.phone.receive_message("Test alerte répétée", true)
	_assert(main.phone._last_alert_notification_ms == premiere_alerte_ms, "E+: une alerte pendant le cooldown est ignorée")
	main.phone._last_alert_notification_ms = derniere_alerte_ms

	# --- F : snap turn ---
	var yaw0: float = main.xr_origin.rotation.y
	main.snap_turn(1.0)
	_assert(is_equal_approx(main.xr_origin.rotation.y, yaw0 - PI / 4.0), "F: snap turn -45°")

	# --- Game over ---
	main.sanity = 99.9
	for i in 10:
		await physics_frame
	_assert(main.game_over, "GO: 100% de schizo déclenche l'assimilation")
	# En fallback bureau, seul le game over dédié reste visible.
	_assert(main.gameover_label.visible, "GO: game over bureau visible en fallback desktop")
	_assert(not main.vr_gameover_label.visible, "GO: game over VR masqué en fallback desktop")
	_assert(not main.chat_label.visible, "GO: chat masqué pendant le game over")
	_assert(not main.center_dot.visible, "GO: point central masqué pendant le game over")
	main._restart()
	_assert(not main.game_over and main.sanity == 0.0, "GO: le restart réinitialise la run")
	# Le restart restaure le HUD et masque les deux écrans de game over.
	_assert(main.chat_label.visible, "GO: chat réaffiché après le restart")
	_assert(main.center_dot.visible, "GO: point central réaffiché après le restart")
	_assert(not main.gameover_label.visible, "GO: game over bureau masqué après le restart")
	_assert(not main.vr_gameover_label.visible, "GO: game over VR masqué après le restart")

	_finish()


func _finish() -> void:
	print("=== RESULTAT: %s (%d échec(s)) ===" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)
