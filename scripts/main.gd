class_name Main
extends Node3D
## Point d'entrée de NÉVROSE — premier fragment jouable (Meta Quest 2).
##
## GDD §4/§5 : stick gauche = déplacement constant, stick droit = snap 45°,
## gâchettes = interagir/tirer. La jauge de schizo monte tant que la pilule
## n'est pas trouvée ; la pilule spawne dans un conteneur aléatoire (GDD §5.1).

# ---------------------------------------------------------------------------
# Constantes de jeu (tweakables)
# ---------------------------------------------------------------------------
const SNAP_TURN_RAD := PI / 4.0 # 45° — confort VR (GDD §8)
const MOVE_SPEED := 1.8 # m/s, vitesse constante, aucune dérive (GDD §4)
const STICK_DEADZONE := 0.15
const SNAP_COOLDOWN := 0.25 # s entre deux snaps
const RAY_LENGTH := 3.0

const SANITY_RATE := 1.4 # points/seconde tant que pas de dose (monte "vite")
const SANITY_DOSE_RELIEF := 55.0 # reset partiel à la prise (GDD §5.1)
const SANITY_RATE_AFTER_DOSE := 0.7 # la montée ralentit après une dose
const SANITY_RATE_ESCALATION := 0.3 # Round 3 : +0.3 par round (dose_count)

# Limites de la pièce pour le clamp de déplacement (mur = mur, zéro collision coûteuse)
# Map 2 étendue : salon+cuisine+couloir+garage+chambre+sdb+dressing
# x ∈ [-3.7, 12.0], z ∈ [-3.3, 6.3]
const ROOM_MIN := Vector2(-3.7, -3.3)
const ROOM_MAX := Vector2(12.0, 6.3)

# Lobby cosy : mêmes contrôles, mais folie et gameplay en pause.
const LOBBY_SCENE := preload("res://scenes/lobby.tscn")
const LOBBY_MIN := Vector2(-2.25, -2.15)
const LOBBY_MAX := Vector2(2.25, 2.15)

# Seuils de folie (GDD §5.2) : la folie se lit sur le monde, pas sur une barre.
const FOLIE_LEGERE := 35.0 # vignette douce
const FOLIE_FORTE := 65.0 # vignette marquée + murs qui respirent
const FOLIE_CRITIQUE := 88.0 # teinte critique + messages urgents

# ---------------------------------------------------------------------------
# Nœuds XR (résolus dans main.tscn)
# ---------------------------------------------------------------------------
@onready var xr_origin: XROrigin3D = $XROrigin3D
@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_hand: XRController3D = $XROrigin3D/LeftHand
@onready var right_hand: XRController3D = $XROrigin3D/RightHand

# Mains animées (godot-xr-tools) — le script hand.gd lit grip/trigger du
# XRController3D parent et pilote le blend tree automatiquement.
var _left_hand_mesh: Node3D = null
var _right_hand_mesh: Node3D = null
var _body: VRBody = null
var _held_key: KeyObject = null ## Clé actuellement dans la main (GDD §5.6)
var phone: Phone = null ## Smartphone avec Messenger
var vr_gameover_label: Label3D = null ## Game over 3D visible dans le casque OpenXR
const HAND_SCENE_R := preload("res://addons/godot-xr-tools/hands/scenes/lowpoly/right_hand_low.tscn")
const HAND_SCENE_L := preload("res://addons/godot-xr-tools/hands/scenes/lowpoly/left_hand_low.tscn")
# Distance max pour interagir "au contact" (proximité) sans viser au rayon
const PROXIMITY_RADIUS := 0.45

# ---------------------------------------------------------------------------
# État de partie
# ---------------------------------------------------------------------------
var xr_interface: XRInterface
var xr_active := false
var sanity := 0.0
var sanity_rate := SANITY_RATE
var game_over := false
var dose_count := 0

var _snap_cooldown := 0.0
var _desktop_yaw := 0.0
var _desktop_pitch := 0.0
var _movement_body: CharacterBody3D = null
var _pointed: Node = null # conteneur/pilule actuellement pointé
var _chat_hold := 0.0 # temps restant avant retour au compte à rebours
var _chat_accum := 0.0
var _creepy_idx := 0
var _chat_msg_count := 0 # total de lignes creepy — 1 message Messenger sur 3

var apartment: MapBase = null
var lobby: LobbyWorld = null
var game_started := false
var _lobby_laser: MeshInstance3D = null
var vignette_rect: ColorRect
var chat_label: Label
var center_dot: ColorRect
var gameover_label: Label
var creepy_voices: Node = null ## AudioStreamPlayer3D HRTF (voix dans les murs)

# Journal de session (autoload GameLog). Résolu paresseusement pour rester
# tolérant aux contextes sans autoload (tests headless).
var _logger: GameLogger = null
# Heartbeat de diagnostique : caméra/origine/santé toutes les secondes au début.
var _hb_t := 0.0
var _hb_n := 0


## Écrit une ligne dans le journal .txt (GameLogger), repli sur print().
func _log(cat: String, msg: String) -> void:
	if _logger == null:
		_logger = get_node_or_null("/root/GameLog") as GameLogger
	if _logger != null:
		_logger.log_line(cat, msg)
	else:
		print("[%s] %s" % [cat, msg])

# Lignes de chat à mesure que la schizo monte (GDD §5.2 : le chat donne le
# compte à rebours ET devient inquiétant).
const CHAT_CALME := [
	"T'as pris ta dose ce matin ou tu déconnes ?",
	"Le tiroir de la cuisine. Regarde bien.",
]
const CHAT_INQUIET := [
	"Fréro. Les murs bougent. C'est pas normal.",
	"Il te reste peu de temps. CHERCHE.",
	"Le faux est celui qui tremble. Souviens-toi.",
]
const CHAT_CRITIQUE := [
	"IL EST DANS LA PIÈCE AVEC TOI",
	"ne regarde pas derrière. CHERCHE LES PILULES.",
	"t u   v a s   d e v e n i r   l e   m u r",
]


func _ready() -> void:
	add_to_group("main")
	_log("MAIN", "lobby : _ready()")
	right_hand.button_pressed.connect(_on_right_button_pressed)
	left_hand.button_pressed.connect(_on_left_button_pressed)
	_init_openxr()
	_build_player_body()
	_build_player_collision()
	_build_hud()
	_build_lobby()
	_register_debug_inputs()


func _build_lobby() -> void:
	lobby = LOBBY_SCENE.instantiate() as LobbyWorld
	lobby.name = "Lobby"
	add_child(lobby)
	lobby.play_requested.connect(start_game)
	xr_origin.position = Vector3(1.0, 1.7 if not xr_active else 0.0, 1.35)
	xr_origin.rotation = Vector3.ZERO
	_desktop_yaw = 0.0
	_desktop_pitch = 0.0
	xr_camera.rotation = Vector3.ZERO
	chat_label.text = ""

	if xr_active:
		# Un fin rayon rend la visée par la main immédiatement compréhensible.
		_lobby_laser = MeshInstance3D.new()
		_lobby_laser.name = "LobbyPointer"
		var beam := BoxMesh.new()
		beam.size = Vector3(0.006, 0.006, RAY_LENGTH)
		_lobby_laser.mesh = beam
		var laser_mat := StandardMaterial3D.new()
		laser_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		laser_mat.albedo_color = Color(0.3, 1.0, 0.9)
		_lobby_laser.material_override = laser_mat
		_lobby_laser.position = Vector3(0.0, 0.0, -RAY_LENGTH * 0.5)
		right_hand.add_child(_lobby_laser)
	_log("WORLD", "lobby cosy prêt — folie en pause")


## Point de départ unique de la partie, appelé par l'ordinateur du lobby.
func start_game() -> void:
	if game_started:
		return
	game_started = true
	if is_instance_valid(_pointed) and _pointed.has_method(&"on_unpointed"):
		_pointed.on_unpointed()
	_pointed = null
	if is_instance_valid(_lobby_laser):
		_lobby_laser.queue_free()
	_lobby_laser = null
	if is_instance_valid(lobby):
		lobby.queue_free()
	lobby = null

	# L'appartement reprend exactement son initialisation d'origine.
	xr_origin.position = Vector3(0.0, 1.7 if not xr_active else 0.0, 0.0)
	xr_origin.rotation = Vector3.ZERO
	_desktop_yaw = 0.0
	_desktop_pitch = 0.0
	xr_camera.rotation = Vector3.ZERO
	_build_world()
	_build_phone()
	_spawn_dose()
	_update_chat("Tu as oublié ta dose. Elle est dans la pièce. Trouve-la.")
	if creepy_voices:
		creepy_voices.play_intro_whisper()
	_pulse_haptics()
	_log("GAME", "transition lobby → appartement")


# ---------------------------------------------------------------------------
# OpenXR : démarre la session VR si un casque est présent, sinon fallback bureau
# ---------------------------------------------------------------------------
func _init_openxr() -> void:
	_log("XR", "recherche de l'interface OpenXR…")
	xr_interface = XRServer.find_interface("OpenXR")
	_log("XR", "interface trouvée : %s" % str(xr_interface != null))
	if xr_interface and xr_interface.initialize():
		xr_active = true
		# CRITIQUE : sans use_xr, rien n'est soumis au runtime XR (écran noir).
		get_viewport().use_xr = true
		# Le viewport devient piloté par le runtime XR ; le casque gère sa fréquence.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_log("XR", "OpenXR initialisé — viewport.use_xr=true")
		print("[NÉVROSE] OpenXR initialisé — mode VR.")
	else:
		xr_active = false
		# Fallback bureau : l'origine XR joue le rôle du joueur, caméra à 1,7 m.
		xr_origin.position.y = 1.7
		_log("XR", "ÉCHEC initialisation OpenXR — fallback bureau")
		print("[NÉVROSE] OpenXR indisponible — mode bureau (tests/debug).")


func is_xr_active() -> bool:
	return xr_active


# ---------------------------------------------------------------------------
# Monde : l'appartement (généré procéduralement, géométrie légère, zéro texture)
# ---------------------------------------------------------------------------
func _build_world() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.025, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.28, 0.3)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.1, 0.14)
	env.fog_density = 0.035
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_strength = 0.8
	env.glow_bloom = 0.08
	world_env.environment = env
	add_child(world_env)

	apartment = preload("res://scripts/map2_extended.gd").new()
	apartment.name = "Map2Extended"
	add_child(apartment)
	apartment.build()
	_log("WORLD", "map salon+cuisine construite : %d nœuds" % apartment.get_child_count())
	# Note Post-it d'accueil sur le plan de travail de la cuisine
	var note_root := Node3D.new()
	note_root.name = "PostItNote"
	note_root.position = Vector3(-0.6, 0.92, -2.15)
	note_root.rotation_degrees = Vector3(-85.0, 10.0, 0.0)
	add_child(note_root)

	var note_quad := QuadMesh.new()
	note_quad.size = Vector2(0.24, 0.24)
	var note_mesh := MeshInstance3D.new()
	note_mesh.mesh = note_quad
	var note_mat := StandardMaterial3D.new()
	note_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	note_mat.albedo_color = Color(1.0, 0.92, 0.45)
	note_mesh.material_override = note_mat
	note_root.add_child(note_mesh)

	var note_txt := Label3D.new()
	note_txt.text = "N'OUBLIE PAS\nTA DOSE !\n\nFouille les tiroirs.\nGâchette = ouvrir\nBouton Y = téléphone"
	note_txt.font_size = 28
	note_txt.pixel_size = 0.0014
	note_txt.modulate = Color(0.1, 0.1, 0.12)
	note_txt.position = Vector3(0.0, 0.0, 0.005)
	note_root.add_child(note_txt)
	# GDD §5.6 : signaux verrous (clé / force → bruit → mimic)
	for c in apartment.containers:
		if c.lock_type != InteractiveContainer.LockType.NONE:
			c.lock_broken.connect(_on_container_lock_broken)
			c.unlocked_by_key.connect(_on_container_unlocked_by_key)
			c.force_progress.connect(_on_container_force_progress)
			c.key_required.connect(_on_container_key_required)

	# GDD §5.2/§7 : voix dans les murs (HRTF binaural)
	creepy_voices = preload("res://scripts/creepy_voices.gd").new()
	creepy_voices.name = "CreepyVoices"
	add_child(creepy_voices)
	creepy_voices.configure_room(apartment.room_w, apartment.room_d, apartment.room_h)
	_log("AUDIO", "système voix murs initialisé (HRTF spatial)")


# ---------------------------------------------------------------------------
# Joueur : mains VR (modèles low-poly) + corps FPV visible en baissant les yeux.
# Les mains sont attachées aux XRController3D ; le corps à l'origine XR.
# ---------------------------------------------------------------------------
func _build_player_body() -> void:
	_right_hand_mesh = HAND_SCENE_R.instantiate()
	right_hand.add_child(_right_hand_mesh)
	_right_hand_mesh.visible = xr_active
	_left_hand_mesh = HAND_SCENE_L.instantiate()
	left_hand.add_child(_left_hand_mesh)
	_left_hand_mesh.visible = xr_active
	_log("WORLD", "mains animées (godot-xr-tools) attachées : grip=pointer, grip+trigger=saisir")
	# Corps FPV : uniquement en VR. En fallback bureau la caméra est à 1,7 m
	# fixe → on se retrouverait à l'intérieur du buste (torse à y=1,25).
	if not xr_active:
		return
	_body = VRBody.new()
	_body.name = "PlayerBody"
	xr_origin.add_child(_body)
	_body.setup(xr_camera)
	_log("WORLD", "corps FPV ajouté (visible en baissant les yeux)")




## Capsule de déplacement partagée VR/bureau. Les StaticBody3D de la map
## restent simples : une capsule et des boîtes, aucun RigidBody.
func _build_player_collision() -> void:
	_movement_body = CharacterBody3D.new()
	_movement_body.name = "MovementBody"
	_movement_body.collision_layer = 2
	_movement_body.collision_mask = 1
	_movement_body.safe_margin = 0.02
	xr_origin.add_child(_movement_body)
	_movement_body.position.y = -1.7 if not xr_active else 0.0
	var collision := CollisionShape3D.new()
	collision.name = "Capsule"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.7
	collision.shape = capsule
	collision.position.y = 0.85
	_movement_body.add_child(collision)


# ---------------------------------------------------------------------------
# HUD : vignette de folie (shader), chat compte à rebours, point central
# ---------------------------------------------------------------------------
func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.layer = 10
	xr_camera.add_child(hud)

	vignette_rect = ColorRect.new()
	vignette_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette_rect.material = ShaderMaterial.new()
	vignette_rect.material.shader = preload("res://scripts/vignette.gdshader")
	hud.add_child(vignette_rect)

	center_dot = ColorRect.new()
	center_dot.size = Vector2(6, 6)
	center_dot.position = Vector2(-3, -3)
	center_dot.set_anchors_preset(Control.PRESET_CENTER)
	center_dot.color = Color(1, 1, 1, 0.65)
	center_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(center_dot)

	chat_label = Label.new()
	chat_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	chat_label.offset_left = 60
	chat_label.offset_right = -60
	chat_label.offset_top = -140
	chat_label.offset_bottom = -60
	chat_label.add_theme_font_size_override("font_size", 28)
	chat_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	chat_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	chat_label.add_theme_constant_override("shadow_offset_x", 2)
	chat_label.add_theme_constant_override("shadow_offset_y", 2)
	chat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chat_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	chat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.add_child(chat_label)

	gameover_label = Label.new()
	gameover_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	gameover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gameover_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gameover_label.add_theme_font_size_override("font_size", 44)
	gameover_label.add_theme_color_override("font_color", Color(0.85, 0.1, 0.1))
	gameover_label.visible = false
	hud.add_child(gameover_label)


	# Game Over 3D dans le casque
	vr_gameover_label = Label3D.new()
	vr_gameover_label.name = "VRGameOverLabel"
	xr_camera.add_child(vr_gameover_label)
	vr_gameover_label.position = Vector3(0.0, 0.0, -1.1)
	vr_gameover_label.text = "L'APPART T'A ASSIMILÉ\n\nTu n'as pas pris ta dose à temps.\n\nAppuie sur la Gâchette pour recommencer"
	vr_gameover_label.font_size = 32
	vr_gameover_label.pixel_size = 0.0022
	vr_gameover_label.modulate = Color(1.0, 0.2, 0.2)
	vr_gameover_label.outline_size = 6
	vr_gameover_label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	vr_gameover_label.visible = false

	_log("HUD", "HUD prêt : vignette + point central + chat + game over + HUD 3D VR")


func _build_phone() -> void:
	phone = Phone.new()
	phone.name = "Phone"
	add_child(phone)
	phone.setup_pocket(left_hand, right_hand, xr_camera)
	_log("PHONE", "Smartphone Messenger initialisé (poche gauche)")


# ---------------------------------------------------------------------------
# Inputs bureau (debug/tests headless) : WASD + souris + clic
# ---------------------------------------------------------------------------
func _register_debug_inputs() -> void:
	if xr_active:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_add_key_action(&"dbg_forward", [KEY_W, KEY_UP])
	_add_key_action(&"dbg_back", [KEY_S, KEY_DOWN])
	_add_key_action(&"dbg_left", [KEY_A, KEY_LEFT])
	_add_key_action(&"dbg_right", [KEY_D, KEY_RIGHT])
	_add_key_action(&"dbg_turn_left", [KEY_Q])
	_add_key_action(&"dbg_turn_right", [KEY_E])
	_add_key_action(&"dbg_interact", [KEY_F])
	_add_key_action(&"dbg_phone", [KEY_TAB, KEY_T, KEY_P])
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	_add_event_action(&"dbg_interact", ev)
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_RIGHT
	_add_event_action(&"dbg_snap_right", ev2)


func _add_key_action(action: StringName, keycodes: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keycodes:
		var ev := InputEventKey.new()
		ev.keycode = k
		_add_event_action(action, ev)


func _add_event_action(action: StringName, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_add_event(action, event)


func _unhandled_input(event: InputEvent) -> void:
	if xr_active or game_over:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_update_desktop_look(event.relative)


## Séparé de la capture Windows pour tester la même logique en headless.
func _update_desktop_look(relative: Vector2) -> void:
	_desktop_yaw -= relative.x * 0.0025
	_desktop_pitch = clampf(_desktop_pitch - relative.y * 0.0025, deg_to_rad(-80.0), deg_to_rad(80.0))
	xr_origin.rotation.y = _desktop_yaw
	xr_camera.rotation.x = _desktop_pitch


# ---------------------------------------------------------------------------
# Boucle principale
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if game_over:
		return
	if not game_started:
		# Le lobby conserve déplacement et visée, mais aucune pression de jeu.
		_tick_movement(delta)
		_tick_interaction_ray()
		return
	_tick_sanity(delta)
	_tick_movement(delta)
	_tick_interaction_ray()
	_tick_sanity_feedback(delta)
	_tick_pill_eat_feedback(delta)


func _tick_sanity(delta: float) -> void:
	# Round 3 : montée de schizo plus rapide — chaque round (dose) accélère.
	var eff := sanity_rate + SANITY_RATE_ESCALATION * dose_count
	sanity = minf(100.0, sanity + eff * delta)
	if sanity >= 100.0:
		_trigger_game_over()


# Déplacement : stick gauche (VR) / WASD (bureau). Capsule CharacterBody3D
# + clamp extérieur pour les limites — aucun RigidBody, léger pour Quest 2.
func _tick_movement(delta: float) -> void:
	var move := Vector2.ZERO
	if xr_active:
		# Sur Quest le runtime OpenXR renvoie Y inversé (stick avant = +Y).
		# On corrige à la source pour garder la convention Godot (avant = -Y).
		move = left_hand.get_vector2(&"primary")
		move.y = -move.y
	else:
		move = Input.get_vector(&"dbg_left", &"dbg_right", &"dbg_forward", &"dbg_back")
		if Input.is_action_pressed(&"dbg_turn_left"):
			_desktop_yaw += SNAP_TURN_RAD * delta * 2.0
		if Input.is_action_pressed(&"dbg_turn_right"):
			_desktop_yaw -= SNAP_TURN_RAD * delta * 2.0
		xr_origin.rotation.y = _desktop_yaw

	if move.length() < STICK_DEADZONE:
		move = Vector2.ZERO

	# Snap turn 45° sur le stick droit (bord d'appui), avec anti-rebond.
	_snap_cooldown -= delta
	if xr_active and _snap_cooldown <= 0.0:
		var turn_x := right_hand.get_vector2(&"primary").x
		if absf(turn_x) > 0.6:
			snap_turn(signf(turn_x))
			_snap_cooldown = SNAP_COOLDOWN

	if move.is_zero_approx():
		return

	# Direction relative au regard (yaw de la caméra uniquement — pas de pitch).
	# Stick vers l'avant = move.y négatif → -move.y positif → on avance.
	var basis_yaw := xr_camera.global_transform.basis
	var forward := -basis_yaw.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := basis_yaw.x
	right.y = 0.0
	right = right.normalized()

	var displacement := (forward * -move.y + right * move.x) * MOVE_SPEED * delta
	var new_pos: Vector3 = xr_origin.position + displacement
	var bounds_min := ROOM_MIN if game_started else LOBBY_MIN
	var bounds_max := ROOM_MAX if game_started else LOBBY_MAX
	new_pos.x = clampf(new_pos.x, bounds_min.x, bounds_max.x)
	new_pos.z = clampf(new_pos.z, bounds_min.y, bounds_max.y)
	_move_with_collisions(new_pos - xr_origin.position)


## Déplace la capsule avec trois glissements maximum, puis applique le motion
## réellement parcouru à XROrigin3D. La caméra reste ainsi hors des obstacles.
func _move_with_collisions(displacement: Vector3) -> void:
	if _movement_body == null or displacement.is_zero_approx():
		return
	_movement_body.position = Vector3(0.0, -xr_origin.position.y if not xr_active else 0.0, 0.0)
	var body_start := _movement_body.global_position
	var motion := displacement
	for i in 3:
		if motion.is_zero_approx():
			break
		var collision := _movement_body.move_and_collide(motion)
		if collision == null:
			break
		motion = collision.get_remainder().slide(collision.get_normal())
	var actual_motion := _movement_body.global_position - body_start
	var origin_start := xr_origin.global_position
	xr_origin.global_position = origin_start + actual_motion
	xr_origin.global_position.y = origin_start.y

	# Le clamp reste une barrière extérieure, notamment pour le jardin/lobby.
	var bounds_min := ROOM_MIN if game_started else LOBBY_MIN
	var bounds_max := ROOM_MAX if game_started else LOBBY_MAX
	var clamped := xr_origin.position
	clamped.x = clampf(clamped.x, bounds_min.x, bounds_max.x)
	clamped.z = clampf(clamped.z, bounds_min.y, bounds_max.y)
	xr_origin.position = clamped
	_movement_body.position = Vector3(0.0, -xr_origin.position.y if not xr_active else 0.0, 0.0)


func snap_turn(direction: float) -> void:
	if direction == 0.0:
		return
	xr_origin.rotate_y(-direction * SNAP_TURN_RAD)


# ---------------------------------------------------------------------------
# Interaction : rayon depuis la main droite (VR) ou la caméra (bureau).
# Gâchette / clic = ouvrir un conteneur ou prendre la pilule.
# ---------------------------------------------------------------------------
func _tick_interaction_ray() -> void:
	if not is_instance_valid(_pointed):
		_pointed = null
	var from: Vector3
	var dir: Vector3
	if xr_active:
		var hand_basis := right_hand.global_transform.basis
		from = right_hand.global_transform.origin
		dir = -hand_basis.z
	else:
		from = xr_camera.global_transform.origin
		dir = -xr_camera.global_transform.basis.z

	var query := PhysicsRayQueryParameters3D.create(from, from + dir * RAY_LENGTH)
	query.collide_with_bodies = false
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	var new_pointed: Node = null
	if hit and hit.collider and hit.collider.has_method(&"on_pointed"):
		new_pointed = hit.collider
	# Les conteneurs ET la pilule exposent on_pointed() ; tout est Area3D.
	if hit and hit.collider is Area3D:
		var owner_node: Node = (hit.collider as Area3D).get_parent()
		if hit.collider is Dose:
			new_pointed = hit.collider
		elif owner_node and owner_node.has_method(&"on_pointed"):
			new_pointed = owner_node
		elif (hit.collider as Object).has_method(&"on_pointed"):
			new_pointed = hit.collider

	# Une dose révélée dans un conteneur doit être cliquable avant sa façade.
	if new_pointed is InteractiveContainer and new_pointed.is_open:
		var container := new_pointed as InteractiveContainer
		if is_instance_valid(container.dose) and container.dose.visible:
			var dose_query := PhysicsRayQueryParameters3D.create(from, from + dir * RAY_LENGTH)
			dose_query.collide_with_bodies = false
			dose_query.collide_with_areas = true
			dose_query.exclude = [container.area.get_rid()]
			var dose_hit := get_world_3d().direct_space_state.intersect_ray(dose_query)
			if dose_hit and dose_hit.collider == container.dose:
				new_pointed = container.dose

	if new_pointed != _pointed:
		if is_instance_valid(_pointed) and _pointed.has_method(&"on_unpointed"):
			_pointed.on_unpointed()
		_pointed = new_pointed
		if is_instance_valid(_pointed) and _pointed:
			_pointed.on_pointed()
			center_dot.color = Color(0.4, 1.0, 0.9, 0.95)
		else:
			center_dot.color = Color(1, 1, 1, 0.65)


func interact(source_hand: XRController3D = null) -> void:
	if not is_instance_valid(_pointed):
		_pointed = null
	if game_over:
		_restart()
		return
	# 0) Pilule tenue : gâchette = avaler (si dans la zone bouche)
	if _held_pill and is_instance_valid(_held_pill):
		_held_pill.interact() ## interne : can_eat() → _consume()
		return
	# 1) Clé pointée → la ramasser
	if _pointed is KeyObject and is_instance_valid(_pointed):
		_pickup_key(_pointed as KeyObject)
		return
	# 2) Pilule pointée (pas encore tenue) → la ramasser
	if _pointed is Dose and is_instance_valid(_pointed):
		pickup_pill(_pointed as Dose)
		return
	# 3) Objet pointé au rayon (priorité) → déjà résolu dans _pointed.
	if _pointed != null and is_instance_valid(_pointed) and _pointed.has_method(&"interact"):
		var key_ref: KeyObject = _held_key if _held_key else null
		var was_in_lobby := not game_started
		_pointed.interact(key_ref)
		if was_in_lobby:
			return # start_game() fournit déjà son retour haptique.
		_pulse_haptics(0.25, 0.08, source_hand)
		return
	# 4) Proximité : on cherche un conteneur/pilule interactif près de la main.
	var near := _nearest_interactable()
	if near != null:
		var key_ref2: KeyObject = _held_key if _held_key else null
		var was_in_lobby := not game_started
		near.interact(key_ref2)
		if not was_in_lobby:
			_pulse_haptics(0.25, 0.08, source_hand)


# Retourne l'interactable le plus proche d'une main (gâchette), dans un rayon
# PROXIMITY_RADIUS. Utilisé quand le rayon ne vise rien mais qu'on est au contact.
func _nearest_interactable() -> Node:
	if not game_started:
		if lobby == null:
			return null
		for hand in [right_hand, left_hand]:
			var origin: Vector3 = hand.global_transform.origin
			if origin.distance_to(lobby.computer.global_transform.origin) < PROXIMITY_RADIUS:
				return lobby.computer
		return null
	var best: Node = null
	var best_d := PROXIMITY_RADIUS
	for hand in [right_hand, left_hand]:
		var origin: Vector3 = hand.global_transform.origin
		for c in apartment.containers:
			if not (c.has_method(&"interact")):
				continue
			var d: float = origin.distance_to(c.global_transform.origin)
			if d < best_d:
				best_d = d
				best = c
		# La pilule en surface (pas dans un conteneur)
		var dose: Node = apartment.get_dose()
		if dose != null and is_instance_valid(dose) and dose.has_method(&"interact"):
			var dd: float = origin.distance_to(dose.global_transform.origin)
			if dd < best_d:
				best_d = dd
				best = dose
	return best


# Ramasse une clé (GDD §5.6) — elle reste "dans la main" (vivante + visible)
# jusqu'à ce qu'elle soit utilisée sur son conteneur.
func _pickup_key(key: KeyObject) -> void:
	if not is_instance_valid(key):
		return
	if _held_key:
		_update_chat("Ta main est déjà pleine.")
		return
	_held_key = key
	key.is_held = true
	key.name = "HeldKey"
	key.reparent(right_hand) ## remonte dans la main animée → suit le controller
	key.position = Vector3(0.0, -0.08, 0.12)
	key.rotation = Vector3(PI / 2, 0, 0)
	_log("GAME", "clé ramassée")
	_update_chat("Tu as une clé. Elle sert à quelque chose…")
	_pulse_haptics(0.35, 0.10, right_hand)


# Ramasse une pilule (GDD §5.1) — elle suit la main, le joueur la porte à la
# bouche (zone ~28 cm sous la caméra) puis gâchette = avaler.
var _held_pill: Dose = null

func pickup_pill(pill: Dose) -> void:
	if not is_instance_valid(pill):
		return
	if _held_pill and is_instance_valid(_held_pill):
		_update_chat("Tu tiens déjà une pilule.")
		return
	_held_pill = pill
	pill.is_held = true
	pill.camera = xr_camera
	pill.name = "HeldPill"
	pill.reparent(right_hand)
	pill.position = Vector3(0.0, -0.06, 0.10)
	pill.rotation = Vector3(PI / 2, 0, 0)
	_log("GAME", "pilule saisie — porte-la à ta bouche et gâchette")
	_update_chat("Tu l'as. Porte-la à ta bouche. Gâchette = avaler.")
	_pulse_haptics(0.40, 0.10, right_hand)


## Appelé chaque frame pour vérifier si la pilule est dans la zone bouche
## et afficher l'indicateur (vignette + chat).
func _tick_pill_eat_feedback(delta: float) -> void:
	if _held_pill and is_instance_valid(_held_pill):
		if _held_pill.can_eat():
			# Indicateur : le point central devient vert + chat
			center_dot.color = Color(0.3, 1.0, 0.5, 1.0)
			center_dot.size = Vector2(12, 12)
			center_dot.position = Vector2(-6, -6)
		else:
			center_dot.color = Color(0.4, 1.0, 0.9, 0.95)
			center_dot.size = Vector2(6, 6)
			center_dot.position = Vector2(-3, -3)


# Consomme la clé (après déverrouillage réussi).
func _consume_key() -> void:
	if _held_key and is_instance_valid(_held_key):
		_held_key.queue_free()
	_held_key = null


# Consomme la pilule (après avoir mangé).
func _consume_pill() -> void:
	if _held_pill and is_instance_valid(_held_pill):
		_held_pill.queue_free()
	_held_pill = null


# GDD §5.6 : conteneur forcé ouvert = bruit qui attire les mimics.
func _on_container_lock_broken(container: Node3D, noise: float) -> void:
	_consume_key()
	sanity = minf(100.0, sanity + 8.0)
	_pulse_haptics()
	_log("GAME", "verrou FORCÉ sur %s (bruit=%.1f)" % [container.name, noise])
	_update_chat("Le verrou cède avec un CRAC. Quelque part, quelque chose s'est levé de son sommeil.")
	# Round 3 : le bruit attire un mimic mobile
	spawn_mobile_mimic()


# GDD §5.6 : déverrouillé par la bonne clé (silencieux).
func _on_container_unlocked_by_key(container: Node3D) -> void:
	_consume_key()
	_log("GAME", "déverrouillé par clé : %s" % container.name)
	_update_chat("La clé tourne dans le silence. Il n'a rien entendu.")
	_pulse_haptics(0.30, 0.10)


func _on_container_force_progress(_container: Node3D, hits: int, required: int) -> void:
	_pulse_haptics(0.2, 0.08)
	_update_chat("Forcer le meuble : %d/%d" % [hits, required])


func _on_container_key_required(_container: Node3D) -> void:
	_update_chat("Il te faut la bonne clé pour ce meuble.")


# Round 3 : un mimic mobile a atteint le joueur (présence oppressante).
func on_mimic_close() -> void:
	sanity = minf(100.0, sanity + 12.0)
	_pulse_haptics()
	_log("GAME", "mimic mobile atteint le joueur (+12 sanity)")
	_update_chat("Il est là. Juste derrière ta nuque. Tu sens son souffle froid.")


# Round 3 : le bruit d'un verrou forcé attire un mimic mobile (GDD §5.6 → §5.3).
# Il apparaît aux limites de la pièce et dérive vers le joueur.
func spawn_mobile_mimic() -> void:
	var m := Mimic.new()
	m.name = "MobileMimic"
	m.is_mobile = true
	m.move_speed = 0.35
	m.attract_target = xr_camera
	add_child(m)
	# Spawn aux 4 coins de la pièce (map 8x6 m — loin du joueur)
	var edges := [
		Vector3(-3.4, 0.0, -2.4),
		Vector3(3.4, 0.0, -2.4),
		Vector3(-3.4, 0.0, 2.4),
		Vector3(3.4, 0.0, 2.4),
	]
	m.position = edges.pick_random()
	_log("GAME", "mimic mobile spawné à %s" % m.position)


# Appelé par la pilule quand elle est absorbée (GDD §5.1).
func on_dose_taken() -> void:
	dose_count += 1
	sanity = maxf(0.0, sanity - SANITY_DOSE_RELIEF)
	sanity_rate = SANITY_RATE_AFTER_DOSE
	_consume_pill() ## nettoie la référence (la pilule s'est déjà freed)
	_log("GAME", "dose absorbue n°%d (sanity=%.0f)" % [dose_count, sanity])
	_pulse_haptics()
	_update_chat("Dose absorbue. Ça va mieux… pour l'instant. Cherche la suivante. Il n'y a PAS de sortie.")
	await get_tree().create_timer(2.0).timeout
	_spawn_dose()


# Appelé par un mimic purgé (GDD §5.3) : le doute coûte cher.
func on_mimic_purged() -> void:
	sanity = minf(100.0, sanity + 6.0)
	_pulse_haptics()
	_update_chat("C'était pas ta tasse. Elle t'observait. La prochaine pilule est ailleurs.")


func _spawn_dose() -> void:
	apartment.spawn_dose()
	_log("GAME", "nouvelle dose spawnée")


# ---------------------------------------------------------------------------
# Folie : vignette + murs qui respirent + chat compte à rebours (GDD §5.2/§7)
# ---------------------------------------------------------------------------
func _tick_sanity_feedback(delta: float) -> void:
	var t := sanity / 100.0
	vignette_rect.material.set_shader_parameter(&"intensity", lerpf(0.12, 1.0, t))
	apartment.set_insanity(t)
	_tick_chat(delta, t)
	# Voix dans les murs — plus la schizo monte, plus elles sont fréquentes
	if creepy_voices and creepy_voices.has_method(&"tick"):
		creepy_voices.tick(t, delta)


# Le chat est l'horloge de la pression (GDD §5.2) : compte à rebours avant la
# folie totale + messages qui se fragmentent quand la schizo monte.
func _tick_chat(delta: float, t: float) -> void:
	_chat_hold -= delta
	if _chat_hold > 0.0:
		return
	_chat_accum += delta
	if _chat_accum < 1.0:
		return
	_chat_accum = 0.0
	var remaining := (100.0 - sanity) / maxf(sanity_rate, 0.01)
	var mm := int(remaining) / 60
	var ss := int(remaining) % 60
	var time_str := "%02d:%02d" % [mm, ss]
	if phone:
		phone.update_timer(time_str, sanity)
	var pool: Array = CHAT_CALME
	var is_alert := false
	if t * 100.0 > FOLIE_CRITIQUE:
		pool = CHAT_CRITIQUE
		is_alert = true
	elif t * 100.0 > FOLIE_LEGERE:
		pool = CHAT_INQUIET
	var line: String = pool[_creepy_idx % pool.size()]
	_creepy_idx += 1
	# Le compte à rebours reste dans le chat HUD à chaque tick, mais le message
	# Messenger (et son carillon) ne part que 1 fois sur 3 — sinon le téléphone
	# harcèle le joueur toutes les ~4 s.
	_chat_msg_count += 1
	if _chat_msg_count % 3 == 0:
		_update_chat("Il te reste %d:%02d avant que ça bascule.\n%s" % [mm, ss, line], line, is_alert)
	else:
		_update_chat("Il te reste %d:%02d avant que ça bascule.\n%s" % [mm, ss, line], "", false, false)


func _update_chat(text: String, phone_line: String = "", is_alert: bool = false,
		notify_phone := true) -> void:
	_chat_hold = 3.0
	chat_label.text = text
	if phone and notify_phone:
		var msg: String = phone_line if not phone_line.is_empty() else text
		phone.receive_message(msg, is_alert)


func _trigger_game_over() -> void:
	game_over = true
	_log("GAME", "GAME OVER — assimilation (sanity=100)")
	gameover_label.text = (
		"L'APPART T'A ASSIMILÉ.\n" +
		"Tu es le mur, maintenant.\n\n" +
		"Tu n'auras jamais réussi à sortir.\n" +
		"Tu n'as fait que DÉCALER. Et ça, ça ne suffit pas.\n\n" +
		"Gâchette / clic : recommencer (et perdre à nouveau)"
	)
	# Un seul affichage : HUD 2D en bureau, Label3D dans le casque.
	gameover_label.visible = not xr_active
	if vr_gameover_label:
		vr_gameover_label.visible = xr_active
	chat_label.visible = false
	center_dot.visible = false
	vignette_rect.material.set_shader_parameter(&"intensity", 1.0)


func _restart() -> void:
	game_over = false
	sanity = 0.0
	sanity_rate = SANITY_RATE
	dose_count = 0
	gameover_label.visible = false
	if vr_gameover_label:
		vr_gameover_label.visible = false
	chat_label.visible = true
	center_dot.visible = true
	_consume_pill()
	_consume_key()
	apartment.reset_containers()
	_spawn_dose()
	if creepy_voices:
		creepy_voices.enabled = true
	_log("GAME", "restart (round %d)" % dose_count)
	_update_chat("Encore une chance. Trouve la pilule. Il n'y a pas de sortie.")


## Impulsion courte Quest 2 : amplitude 0..1 et durée en SECONDES.
## Sans casque ou sans manette active, aucun appel n'est envoyé au runtime.
func _pulse_haptics(amplitude := 0.45, duration := 0.12,
		hand: XRController3D = null) -> void:
	if not xr_active:
		return
	var controllers: Array[XRController3D] = []
	if hand != null:
		controllers.append(hand)
	else:
		controllers.append(right_hand)
		controllers.append(left_hand)
	for controller in controllers:
		if controller != null and controller.get_is_active():
			xr_interface.trigger_haptic_pulse(&"haptic", controller.tracker, 0.0,
				clampf(amplitude, 0.0, 1.0), maxf(duration, 0.01), 0.0)


# ---------------------------------------------------------------------------
# Signaux manettes VR (gâchettes)
# ---------------------------------------------------------------------------
func _on_right_button_pressed(action_name: String) -> void:
	# Gâchette index droite = interagir (ouvrir / prendre), au rayon ou au contact.
	if action_name == &"trigger":
		interact(right_hand)


func _on_left_button_pressed(action_name: String) -> void:
	# Gâchette index gauche = aussi interagir (symétrique, confort ambidextre).
	if action_name == &"trigger":
		interact(left_hand)
		return
	# Boutons X/Y ou grip gauche = sortir / ranger le smartphone
	if action_name in [&"ax_button", &"by_button", &"grip_click", &"primary_click"]:
		if phone:
			phone.toggle_pocket()
		return
	# Le menu pa gauche sert de reset rapide si le joueur est coincé.
	if action_name == &"menu_button" and game_over:
		_restart()


func _process(delta: float) -> void:
	# Heartbeat de diagnostique : 20 premières secondes, une ligne par seconde.
	_hb_t += delta
	if _hb_n < 20 and _hb_t >= 1.0:
		_hb_t = 0.0
		_hb_n += 1
		_log("HB", "cam=%s | origin=%s | sanity=%.0f | xr=%s | doses=%d" % [
			str(xr_camera.global_transform.origin),
			str(xr_origin.global_transform.origin),
			sanity, str(xr_active), dose_count])
	if not xr_active:
		if Input.is_action_just_pressed(&"dbg_interact"):
			interact()
		if Input.is_action_just_pressed(&"dbg_snap_right"):
			snap_turn(1.0)
	if Input.is_action_just_pressed(&"dbg_phone"):
		if phone:
			phone.toggle_pocket()
