class_name TestPhone
extends SceneTree

var _failures := 0


func _assert(cond: bool, label: String) -> void:
	if cond:
		print("  [OK] ", label)
	else:
		_failures += 1
		printerr("  [ECHEC] ", label)


func _initialize() -> void:
	print("=== TEST PHONE & MESSENGER ===")

	var phone_script: GDScript = load("res://scripts/phone.gd")
	_assert(phone_script != null, "1: phone.gd se charge sans erreur")
	if phone_script == null:
		_finish()
		return

	var phone: Phone = Phone.new()
	root.add_child(phone)
	await process_frame
	await process_frame

	# Vérification des nœuds 3D
	var body: MeshInstance3D = phone.get_node_or_null("BodyMesh")
	_assert(body != null, "2: BodyMesh présent")
	_assert(body.mesh is BoxMesh, "2: BodyMesh est un BoxMesh")

	var screen: MeshInstance3D = phone.get_node_or_null("ScreenMesh")
	_assert(screen != null, "3: ScreenMesh présent")
	var screen_mat: StandardMaterial3D = screen.material_override as StandardMaterial3D
	_assert(screen_mat != null, "3: Material override de l'écran présent")
	_assert(screen_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "3: Écran non ombré (SHADING_MODE_UNSHADED)")

	# Vérification du SubViewport
	var vp: SubViewport = phone.get_node_or_null("ScreenViewport")
	_assert(vp != null, "4: SubViewport présent")
	_assert(vp.size == Vector2i(384, 640), "4: Résolution SubViewport 384x640")
	_assert(screen_mat.albedo_texture == vp.get_texture(), "4: Texture du SubViewport connectée à l'écran")

	# Mock des mains et de la caméra XR
	var origin := Node3D.new()
	origin.name = "XROriginMock"
	root.add_child(origin)

	var left_hand := XRController3D.new()
	left_hand.name = "LeftHandMock"
	left_hand.tracker = &"left_hand"
	origin.add_child(left_hand)

	var right_hand := XRController3D.new()
	right_hand.name = "RightHandMock"
	right_hand.tracker = &"right_hand"
	origin.add_child(right_hand)

	var camera := XRCamera3D.new()
	camera.name = "CameraMock"
	origin.add_child(camera)

	# Configuration de la poche
	phone.setup_pocket(left_hand, right_hand, camera)
	_assert(not phone.is_in_hand, "5: is_in_hand = false initialement (en poche)")
	_assert(not phone.visible, "5: phone masqué en mode poche")

	# Toggle poche -> main
	phone.toggle_pocket()
	_assert(phone.is_in_hand, "6: toggle_pocket() passe is_in_hand = true")
	_assert(phone.visible, "6: phone visible en main")

	# Test messages Messenger
	phone.receive_message("Message 1 : reste calme", false)
	phone.receive_message("Message 2 : le temps presse", false)
	phone.receive_message("Message 3 : il n'y a pas de sortie", true)
	phone.receive_message("Message 4 : prends la pilule !", true)

	_assert(phone._messages_data.size() == 3, "7: exactement 3 messages conservés dans l'historique")
	_assert(phone._messages_data[2]["text"] == "Message 4 : prends la pilule !", "7: dernier message correct")
	_assert(phone._messages_data[2]["alert"] == true, "7: statut alerte transmis")

	# Test update timer
	phone.update_timer("01:23", 25.0)
	_assert(phone._timer_badge_label.text == "⏱️ 01:23", "8: timer mis à jour (01:23)")
	_assert(phone._contact_status_label.text == "En ligne", "8: statut subconscient en ligne sous 40% folie")

	phone.update_timer("00:45", 60.0)
	_assert(phone._contact_status_label.text == "Signal perturbé...", "9: signal perturbé à 60% folie")

	phone.update_timer("00:10", 90.0)
	_assert(phone._contact_status_label.text == "PERTE DE CONNEXION", "10: perte de connexion à 90% folie")

	# Toggle main -> poche
	phone.toggle_pocket()
	_assert(not phone.is_in_hand, "11: toggle_pocket() range le téléphone")

	phone.queue_free()
	origin.queue_free()
	_finish()


func _finish() -> void:
	print("=== RESULTAT TEST PHONE: %s (%d échec(s)) ===" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)
