class_name Main
extends Node3D
## Point d'entrée de NÉVROSE — fragment 1 jouable (Meta Quest 2).
##
## Tout le retour au joueur est dans le monde : le téléphone (messages et compte
## à rebours), le rayon de la manette, les lumières, les voix. Aucun texte ni
## point de visée collé à la caméra.
##
## Stick gauche = déplacement, stick droit = virage 45°, gâchette = interagir.
## La folie monte tant que la pilule n'est pas avalée (GDD §5).

# ---------------------------------------------------------------------------
# Constantes de jeu
# ---------------------------------------------------------------------------
const SNAP_TURN_RAD := PI / 4.0 # 45° — confort VR (GDD §8)
const SNAP_COOLDOWN := 0.25
const MOVE_SPEED := 1.8 # m/s, vitesse constante (GDD §4)
const STICK_DEADZONE := 0.15
const RAY_LENGTH := 3.0
const PROXIMITY_RADIUS := 0.45 # interaction au contact sans viser
const DOSE_REACH := 0.75 # une pilule se prend en se penchant : la main peut descendre (tiroir bas, sol)
const TRIGGER_PRESS := 0.75 # gâchette analogique : seuil d'appui…
const TRIGGER_RELEASE := 0.35 # …et seuil de relâchement (hystérésis)

enum Mode { NONE, RESIST, HUNT, REEL }

const START_SANITY := 12.0 # on est déjà fou en arrivant : les voix commencent tout de suite
const TOKENS_PER_SECOND := 0.12 # mode Résistance : plus on tient, plus on gagne
const TOKENS_PER_DOSE := 5
const SANITY_RATE := 1.4 # points/seconde sans dose (GDD §5.2)
const SANITY_DOSE_RELIEF := 55.0
const SANITY_RATE_AFTER_DOSE := 0.7
const SANITY_RATE_ESCALATION := 0.3 # +0.3 par dose avalée
const FOLIE_CRITIQUE := 88.0 # au-delà : messages d'alerte
const FOLIE_LEGERE := 35.0 # au-delà : messages inquiets
const MESSAGE_INTERVAL := 4 # un message du téléphone toutes les 4 secondes

# Limites de l'appartement (clamp de déplacement, murs gérés par collisions)
const ROOM_MIN := Vector2(-3.7, -5.0)
const ROOM_MAX := Vector2(15.0, 8.0)
# Lobby : pièce d'accueil sans folie, seulement le départ
const LOBBY_SCENE := preload("res://scenes/lobby.tscn")
const LOBBY_MIN := Vector2(-2.25, -2.15)
const LOBBY_MAX := Vector2(2.25, 2.15)
const LOBBY_SPAWN := Vector2(1.0, 1.35)
const CAPSULE_CENTER_Y := 0.75 ## centre de la capsule de déplacement : pieds à 25 cm (passe les seuils), tête à 1,25 m
const APARTMENT_SPAWN := Vector2(0.0, 0.0) # centre du salon (libre, vérifié par la marche)
const RESET_HOLD := 0.5 # secondes de maintien de la combinaison A + B (manette droite)
const JUMP_SPEED := 3.1 # m/s : un saut d'environ 0,5 m
const GRAVITY := 9.8
const LOBBY_HOLD := 1.2 # secondes de maintien d'un bouton « retour au lobby » (menu, Y ou B)

const HAND_SCENE_R := preload("res://addons/godot-xr-tools/hands/scenes/lowpoly/right_hand_low.tscn")
const HAND_SCENE_L := preload("res://addons/godot-xr-tools/hands/scenes/lowpoly/left_hand_low.tscn")

const CHAT_CALME := [
	"T'as pris ta dose ce matin ou tu déconnes ?",
	"Cherche la lumière cyan : c'est ta pilule.",
]
const CHAT_INQUIET := [
	"Fréro. Les murs bougent. C'est pas normal.",
	"Il te reste peu de temps. CHERCHE LA LUMIÈRE.",
	"Le faux est celui qui tremble. Souviens-toi.",
]
const CHAT_CRITIQUE := [
	"IL EST DANS LA PIÈCE AVEC TOI",
	"ne regarde pas derrière. CHERCHE LES PILULES.",
	"t u   v a s   d e v e n i r   l e   m u r",
]
const GAME_OVER_TEXT := "L'appart t'a assimilé. Tu es le mur, maintenant.\nTu n'auras jamais réussi à sortir.\nGâchette : retour au lobby."

# ---------------------------------------------------------------------------
# Nœuds XR (résolus dans main.tscn)
# ---------------------------------------------------------------------------
@onready var xr_origin: XROrigin3D = $XROrigin3D
@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_hand: XRController3D = $XROrigin3D/LeftHand
@onready var right_hand: XRController3D = $XROrigin3D/RightHand

# ---------------------------------------------------------------------------
# État
# ---------------------------------------------------------------------------
var xr_interface: XRInterface
var xr_active := false
var game_started := false
var game_over := false
var sanity := START_SANITY
var sanity_rate := SANITY_RATE
var dose_count := 0
var mode: Mode = Mode.NONE
var run_time := 0.0 ## secondes survécues dans le mode Résistance
var last_tokens := 0 ## tokens gagnés à la fin de la dernière partie
var profile: PlayerProfile = null
var hunt: HuntMode = null
var reel: ReelMode = null

var apartment: MapBase = null
var lobby: LobbyWorld = null
var phone: Phone = null
var creepy_voices: Node = null ## voix dans les murs (HRTF)

var _body: VRBody = null
const DEFAULT_HEIGHT := 1.7 ## taille de référence (corps et caméra de bureau)
var player_height := DEFAULT_HEIGHT ## taille mesurée du joueur, à partir du casque
var _fit_timer := -1.0 ## > 0 : délai avant de mesurer la taille (le casque se recale)
var _movement_body: CharacterBody3D = null
var _laser: MeshInstance3D = null ## rayon de visée de la main droite (VR)
var _pointed: Node = null ## conteneur, clé ou pilule actuellement visé
var _held_key: KeyObject = null
var _held_pill: Dose = null
var _pill_ready := false ## la pilule tenue est dans la bouche
var _reset_hold := 0.0 ## temps de maintien de la combinaison de réinitialisation
var _lobby_hold := 0.0 ## temps de maintien du bouton « retour au lobby »
var _lobby_ticks := 0 ## vibrations déjà données pendant le maintien
var _lobby_hud: Label3D = null ## indicateur de progression devant les yeux
var sandbox: HuntSandbox = null ## objets attrapables du mode Résistance (en Chasse : hunt.sandbox)
var nav: NavGrid = null ## carte d'accessibilité : GPS vers la pilule (mode Résistance)
var easter: EasterEgg = null
var music: LobbyMusic = null ## musique du lobby, vit ici pour reprendre où elle s'était arrêtée
var _pill_gps_on := false
var _touch_state := {} ## main -> touche-t-elle un objet ? (retours haptiques)
var _touch_prev := {}
var _touch_shape: SphereShape3D = null
var _jump_y := 0.0 ## hauteur du saut en cours (mode Chasse)
var _jump_vy := 0.0
var _fps_clock := 0.0
var _snap_cooldown := 0.0
var _trigger_down := {} ## état « gâchette enfoncée » par main
var _desktop_yaw := 0.0
var _desktop_pitch := 0.0
var _message_timer := 0.0
var _message_count := 0
var _clock_accum := 0.0
var _hint_timer := 0.0
var _prox_timer := 0.0
var _world_env: WorldEnvironment = null
var _logger: GameLogger = null


func _ready() -> void:
	add_to_group("main")
	_log("MAIN", "lancement")
	profile = PlayerProfile.new()
	profile.name = "Profile"
	add_child(profile)
	music = LobbyMusic.new()
	music.name = "LobbyMusic"
	add_child(music)
	_init_openxr()
	_build_player()
	_build_lobby()
	_register_debug_inputs()
	easter = EasterEgg.new()
	easter.name = "EasterEgg"
	add_child(easter)
	easter.setup(left_hand, right_hand, xr_camera)
	easter.message.connect(func(text: String) -> void: _say(text, false, true))
	left_hand.button_pressed.connect(_on_button_pressed.bind(left_hand))
	right_hand.button_pressed.connect(_on_button_pressed.bind(right_hand))
	left_hand.button_released.connect(_on_button_released.bind(left_hand))
	right_hand.button_released.connect(_on_button_released.bind(right_hand))


## Écrit une ligne dans le journal (GameLog), repli sur print().
func _log(cat: String, msg: String) -> void:
	if _logger == null:
		_logger = get_node_or_null("/root/GameLog") as GameLogger
	if _logger != null:
		_logger.log_line(cat, msg)
	else:
		print("[%s] %s" % [cat, msg])


func is_xr_active() -> bool:
	return xr_active


# ---------------------------------------------------------------------------
# OpenXR : session VR si un casque est présent, sinon fallback bureau
# ---------------------------------------------------------------------------
func _init_openxr() -> void:
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.initialize():
		xr_active = true
		# Sans use_xr, rien n'est soumis au runtime XR : écran noir.
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_log("XR", "OpenXR initialisé")
	else:
		xr_active = false
		xr_origin.position.y = 1.7
		_log("XR", "OpenXR indisponible, mode bureau")


# ---------------------------------------------------------------------------
# Lobby : départ par l'ordinateur, avec le même rayon que le jeu
# ---------------------------------------------------------------------------
func _build_lobby() -> void:
	lobby = LOBBY_SCENE.instantiate() as LobbyWorld
	lobby.name = "Lobby"
	add_child(lobby)
	lobby.setup(profile)
	lobby.play_requested.connect(start_game)
	_recalibrate()
	if music != null:
		music.resume()
	xr_origin.position = Vector3(1.0, 1.7 if not xr_active else 0.0, 1.35)
	xr_origin.rotation = Vector3.ZERO
	_desktop_yaw = 0.0
	_desktop_pitch = 0.0
	xr_camera.rotation = Vector3.ZERO


## Point de départ unique de la partie, appelé par l'ordinateur du lobby.
func start_game(p_mode: int = Mode.RESIST) -> void:
	if game_started:
		return
	game_started = true
	mode = p_mode as Mode
	sanity = START_SANITY
	run_time = 0.0
	_hint_timer = 0.0
	if is_instance_valid(_pointed) and _pointed.has_method(&"on_unpointed"):
		_pointed.on_unpointed()
	_pointed = null
	if is_instance_valid(lobby):
		lobby.queue_free()
	lobby = null
	if music != null:
		music.pause()

	xr_origin.position = Vector3(APARTMENT_SPAWN.x, 1.7 if not xr_active else 0.0, APARTMENT_SPAWN.y)
	xr_origin.rotation = Vector3.ZERO
	_desktop_yaw = 0.0
	_desktop_pitch = 0.0
	xr_camera.rotation = Vector3.ZERO
	_build_world()
	_build_phone()
	if mode == Mode.HUNT:
		creepy_voices.enabled = false
		_start_hunt()
	elif mode == Mode.REEL:
		creepy_voices.enabled = false
		_start_reel()
	else:
		_spawn_dose()
		_say("Les voix reviennent. Suis la flèche du GPS : c'est ta pilule.")
		creepy_voices.play_intro_whisper()
		_start_resist_extras()
	_pulse_haptics()
	_log("GAME", "début de partie (mode %s)" % ["résistance", "chasse", "réels"][clampi(int(mode) - 1, 0, 2)])


# ---------------------------------------------------------------------------
# Monde : l'appartement et son ambiance
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
	env.glow_enabled = not xr_active # le halo plein écran coûte trop cher sur Quest 2
	env.glow_intensity = 0.35
	env.glow_strength = 0.8
	env.glow_bloom = 0.08
	world_env.environment = env
	add_child(world_env)
	_world_env = world_env

	if mode == Mode.REEL:
		apartment = StudioMap.new()
		apartment.name = "Studio"
	else:
		apartment = preload("res://scripts/map2_extended.gd").new()
		apartment.name = "Map2Extended"
	add_child(apartment)
	apartment.build()
	apartment.apply_decorations(profile.active_items())

	for c in apartment.containers:
		if c.lock_type != InteractiveContainer.LockType.NONE:
			c.lock_broken.connect(_on_container_lock_broken)
			c.unlocked_by_key.connect(_on_container_unlocked_by_key)
			c.force_progress.connect(_on_container_force_progress)
			c.key_required.connect(_on_container_key_required)

	creepy_voices = preload("res://scripts/creepy_voices.gd").new()
	creepy_voices.name = "CreepyVoices"
	add_child(creepy_voices)
	creepy_voices.configure_room(apartment.room_w, apartment.room_d, apartment.room_h)
	creepy_voices.listener = xr_camera


func _build_phone() -> void:
	phone = Phone.new()
	phone.name = "Phone"
	add_child(phone)
	phone.setup_pocket(left_hand, right_hand, xr_camera)


# ---------------------------------------------------------------------------
# Joueur : mains, corps FPV, capsule de collision, rayon de visée
# ---------------------------------------------------------------------------
func _build_player() -> void:
	var right_mesh: Node3D = HAND_SCENE_R.instantiate()
	right_hand.add_child(right_mesh)
	right_mesh.visible = xr_active
	var left_mesh: Node3D = HAND_SCENE_L.instantiate()
	left_hand.add_child(left_mesh)
	left_mesh.visible = xr_active

	# Corps FPV : seulement en VR, en bureau la caméra se trouverait dans le buste.
	if xr_active:
		_body = VRBody.new()
		_body.name = "PlayerBody"
		xr_origin.add_child(_body)
		_body.setup(xr_camera)
		_body.visible = false # le corps n'est montré que pour filmer (mode Réels)
		_build_laser()

	# Capsule de déplacement partagée VR et bureau : une capsule, pas de RigidBody.
	_movement_body = CharacterBody3D.new()
	_movement_body.name = "MovementBody"
	_movement_body.collision_layer = 2
	_movement_body.collision_mask = 1
	_movement_body.safe_margin = 0.02
	xr_origin.add_child(_movement_body)
	_movement_body.position.y = CAPSULE_CENTER_Y - xr_origin.position.y
	var collision := CollisionShape3D.new()
	collision.name = "Capsule"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.0
	collision.shape = capsule
	collision.position.y = 0.85
	_movement_body.add_child(collision)


## Rayon fin sur la main droite : il devient vif quand il vise quelque chose.
func _build_laser() -> void:
	_laser = MeshInstance3D.new()
	_laser.name = "Laser"
	var beam := BoxMesh.new()
	beam.size = Vector3(0.004, 0.004, RAY_LENGTH)
	_laser.mesh = beam
	_laser.material_override = StandardMaterial3D.new()
	_laser.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser.position = Vector3(0.0, 0.0, -RAY_LENGTH * 0.5)
	right_hand.add_child(_laser)
	_set_laser_target(false)


func _set_laser_target(has_target: bool) -> void:
	if _laser == null:
		return
	var mat := _laser.material_override as StandardMaterial3D
	mat.albedo_color = Color(0.4, 1.0, 0.9, 0.9) if has_target else Color(0.6, 0.7, 0.75, 0.25)


# ---------------------------------------------------------------------------
# Bureau (tests et débogage) : WASD, souris, clic
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
	_add_key_action(&"dbg_reset", [KEY_R])
	_add_key_action(&"dbg_lobby", [KEY_ESCAPE])
	_add_key_action(&"dbg_jump", [KEY_SPACE])
	_add_key_action(&"dbg_grab", [KEY_G])
	_add_key_action(&"dbg_weapon", [KEY_V])
	_add_key_action(&"dbg_phone", [KEY_TAB, KEY_T, KEY_P])
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	_add_event_action(&"dbg_interact", click)
	var snap := InputEventMouseButton.new()
	snap.button_index = MOUSE_BUTTON_RIGHT
	_add_event_action(&"dbg_snap_right", snap)


func _add_key_action(action: StringName, keycodes: Array) -> void:
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


## Séparé de la capture souris pour pouvoir être testé en headless.
func _update_desktop_look(relative: Vector2) -> void:
	_desktop_yaw -= relative.x * 0.0025
	_desktop_pitch = clampf(_desktop_pitch - relative.y * 0.0025, deg_to_rad(-80.0), deg_to_rad(80.0))
	xr_origin.rotation.y = _desktop_yaw
	xr_camera.rotation.x = _desktop_pitch


# ---------------------------------------------------------------------------
# Boucle principale
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	# La gâchette reste active pendant le game over : elle sert à recommencer.
	_poll_triggers()
	_poll_reset(delta)
	_poll_lobby_exit(delta)
	_tick_fit(delta)
	if game_over:
		return
	if not game_started:
		_tick_movement(delta)
		_tick_interaction_ray()
		return
	_tick_movement(delta)
	_tick_interaction_ray()
	_tick_jump(delta)
	_tick_touch_haptics(delta)
	if mode == Mode.HUNT:
		_tick_hunt_gps()
	elif mode == Mode.RESIST:
		_tick_pill_gps()
	if mode == Mode.HUNT or mode == Mode.REEL:
		return # ni folie ni voix : les coups dans les murs, ou le studio de réels
	run_time += delta
	_tick_sanity(delta)
	_tick_pill_feedback()
	_tick_pill_proximity(delta)
	_tick_phone(delta)
	apartment.set_insanity(sanity / 100.0)
	if creepy_voices and creepy_voices.has_method(&"tick"):
		creepy_voices.tick(sanity / 100.0, delta)


func _process(delta: float) -> void:
	# Une ligne de performance toutes les 10 s dans nevrose.log : sert à diagnostiquer le casque.
	_fps_clock += delta
	if _fps_clock >= 10.0:
		_fps_clock = 0.0
		_log("PERF", "%d fps, %d objets, %d draw calls" % [Engine.get_frames_per_second(),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	if not xr_active:
		if Input.is_action_just_pressed(&"dbg_interact"):
			interact()
		if Input.is_action_just_pressed(&"dbg_snap_right"):
			snap_turn(1.0)
		if Input.is_action_just_pressed(&"dbg_jump"):
			jump()
		if Input.is_action_just_pressed(&"dbg_grab") and mode == Mode.HUNT:
			_toggle_grab(xr_camera)
		if Input.is_action_just_pressed(&"dbg_weapon") and mode == Mode.HUNT:
			_cycle_weapon()
		if Input.is_action_just_pressed(&"dbg_reset"):
			reset_position()
	if Input.is_action_just_pressed(&"dbg_phone") and phone:
		phone.toggle_pocket()


func _tick_sanity(delta: float) -> void:
	# Chaque dose avalée accélère la montée de la folie.
	var eff := sanity_rate + SANITY_RATE_ESCALATION * dose_count
	sanity = minf(100.0, sanity + eff * delta)
	if sanity >= 100.0:
		_trigger_game_over()


# ---------------------------------------------------------------------------
# Déplacement : stick gauche (VR) ou WASD (bureau)
# ---------------------------------------------------------------------------
func _tick_movement(delta: float) -> void:
	var move := Vector2.ZERO
	if xr_active:
		move = left_hand.get_vector2(&"primary")
		move.y = -move.y # le runtime OpenXR renvoie Y inversé sur Quest
	else:
		move = Input.get_vector(&"dbg_left", &"dbg_right", &"dbg_forward", &"dbg_back")
		if Input.is_action_pressed(&"dbg_turn_left"):
			_desktop_yaw += SNAP_TURN_RAD * delta * 2.0
		if Input.is_action_pressed(&"dbg_turn_right"):
			_desktop_yaw -= SNAP_TURN_RAD * delta * 2.0
		xr_origin.rotation.y = _desktop_yaw

	if move.length() < STICK_DEADZONE:
		move = Vector2.ZERO

	# Virage 45° sur le stick droit, avec anti-rebond.
	_snap_cooldown -= delta
	if xr_active and _snap_cooldown <= 0.0:
		var turn_x := right_hand.get_vector2(&"primary").x
		if absf(turn_x) > 0.6:
			snap_turn(signf(turn_x))
			_snap_cooldown = SNAP_COOLDOWN

	if move.is_zero_approx():
		return

	# Direction relative au regard (yaw seul, pas le pitch).
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


## Déplace la capsule avec trois glissements maximum, puis reporte le mouvement réel
## sur XROrigin3D : la caméra ne traverse pas les murs.
func _move_with_collisions(displacement: Vector3) -> void:
	if _movement_body == null or displacement.is_zero_approx():
		return
	_movement_body.position = Vector3(0.0, CAPSULE_CENTER_Y - xr_origin.position.y, 0.0)
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

	var bounds_min := ROOM_MIN if game_started else LOBBY_MIN
	var bounds_max := ROOM_MAX if game_started else LOBBY_MAX
	var clamped := xr_origin.position
	clamped.x = clampf(clamped.x, bounds_min.x, bounds_max.x)
	clamped.z = clampf(clamped.z, bounds_min.y, bounds_max.y)
	xr_origin.position = clamped
	_movement_body.position = Vector3(0.0, CAPSULE_CENTER_Y - xr_origin.position.y, 0.0)


func snap_turn(direction: float) -> void:
	if direction == 0.0:
		return
	xr_origin.rotate_y(-direction * SNAP_TURN_RAD)


# ---------------------------------------------------------------------------
# Visée et interaction
# ---------------------------------------------------------------------------
## Rayon depuis la main droite (VR) ou la caméra (bureau).
func _tick_interaction_ray() -> void:
	if not is_instance_valid(_pointed):
		_pointed = null
	var from: Vector3
	var dir: Vector3
	if xr_active:
		from = right_hand.global_transform.origin
		dir = -right_hand.global_transform.basis.z
	else:
		from = xr_camera.global_transform.origin
		dir = -xr_camera.global_transform.basis.z

	var query := PhysicsRayQueryParameters3D.create(from, from + dir * RAY_LENGTH)
	query.collide_with_bodies = false
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	var new_pointed: Node = null
	if hit and hit.collider is Area3D:
		var area := hit.collider as Area3D
		var owner_node: Node = area.get_parent()
		if area is Dose or area.has_method(&"on_pointed"):
			new_pointed = area
		elif owner_node and owner_node.has_method(&"on_pointed"):
			new_pointed = owner_node

	# Une dose révélée dans un conteneur se vise avant la façade.
	if new_pointed is InteractiveContainer and (new_pointed as InteractiveContainer).is_open:
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
		if is_instance_valid(_pointed):
			_pointed.on_pointed()
	_set_laser_target(is_instance_valid(_pointed))


func interact(source_hand: XRController3D = null) -> void:
	if not is_instance_valid(_pointed):
		_pointed = null
	if game_over:
		return_to_lobby()
		return
	# Chasse avec une arme à feu ou une grenade : la gâchette droite tire / lance.
	var sb := _sbx()
	if mode == Mode.HUNT and sb != null and sb.uses_trigger() and source_hand != left_hand:
		sb.trigger_pressed(source_hand if source_hand != null else xr_camera)
		return
	# Pilule tenue : gâchette = avaler si elle est dans la bouche.
	if _held_pill and is_instance_valid(_held_pill):
		_held_pill.interact()
		return
	if _pointed is KeyObject:
		_pickup_key(_pointed as KeyObject)
		return
	if _pointed is Dose:
		pickup_pill(_pointed as Dose)
		return
	if _pointed != null and _pointed.has_method(&"interact"):
		_run_interaction(_pointed, source_hand)
		return
	# Au contact, sans viser : le conteneur ou la pilule la plus proche.
	var near := _nearest_interactable()
	if near != null:
		_run_interaction(near, source_hand)


func _run_interaction(target: Node, source_hand: XRController3D) -> void:
	var was_in_lobby := not game_started
	var key_ref: KeyObject = _held_key if _held_key else null
	target.interact(key_ref)
	if not was_in_lobby:
		_pulse_haptics(0.25, 0.08, source_hand)


## L'interactable le plus proche d'une main, dans PROXIMITY_RADIUS.
func _nearest_interactable() -> Node:
	if not game_started:
		if lobby == null:
			return null
		for hand in [right_hand, left_hand]:
			for item in lobby.interactables:
				if is_instance_valid(item) and hand.global_transform.origin.distance_to(item.global_transform.origin) < PROXIMITY_RADIUS:
					return item
		return null
	if mode == Mode.REEL:
		if reel == null:
			return null
		for hand in [right_hand, left_hand]:
			for item in reel.interactables:
				if is_instance_valid(item) and item.visible and hand.global_transform.origin.distance_to(item.global_transform.origin) < PROXIMITY_RADIUS:
					return item
		return null
	if mode == Mode.HUNT:
		if hunt != null and is_instance_valid(hunt.current) and hunt.current.active:
			for hand in [right_hand, left_hand]:
				if hand.global_transform.origin.distance_to(hunt.current.global_transform.origin) < 0.6:
					return hunt.current
		return null
	var best: Node = null
	var best_d := PROXIMITY_RADIUS
	for hand in [right_hand, left_hand]:
		var origin: Vector3 = hand.global_transform.origin
		for c in apartment.containers:
			if not c.has_method(&"interact"):
				continue
			var d: float = origin.distance_to(c.global_transform.origin)
			if d < best_d:
				best_d = d
				best = c
		var dose: Node = apartment.get_dose()
		if dose != null and is_instance_valid(dose) and dose.has_method(&"interact"):
			var dd: float = origin.distance_to(dose.global_transform.origin)
			if dd < DOSE_REACH and (best == null or dd < best_d):
				best_d = dd
				best = dose
	return best


## Gâchette analogique (float) : Godot n'émet pas button_pressed pour elle.
func _poll_triggers() -> void:
	if not xr_active:
		return
	_poll_trigger(right_hand, &"right")
	_poll_trigger(left_hand, &"left")


func _poll_trigger(hand: XRController3D, key: StringName) -> void:
	var value := hand.get_float(&"trigger")
	var was_down: bool = _trigger_down.get(key, false)
	if not was_down and value > TRIGGER_PRESS:
		_trigger_down[key] = true
		interact(hand)
	elif was_down and value < TRIGGER_RELEASE:
		_trigger_down[key] = false


## Combinaison de réinitialisation : maintenir A et B de la manette droite ensemble
## pendant RESET_HOLD secondes ramène le joueur au point de départ.
func _poll_reset(delta: float) -> void:
	if not xr_active:
		return
	var combo := right_hand.is_button_pressed(&"ax_button") and right_hand.is_button_pressed(&"by_button")
	if not combo:
		_reset_hold = 0.0
		return
	_reset_hold += delta
	if _reset_hold >= RESET_HOLD:
		_reset_hold = 0.0
		reset_position()


## Maintenir le bouton menu (manette gauche ; Échap au bureau) ramène au lobby depuis
## n'importe quel mode, y compris pendant une partie. Les tokens déjà gagnés sont gardés.
func _poll_lobby_exit(delta: float) -> void:
	var pressed := false
	if xr_active:
		# Trois boutons au choix : le bouton menu (manette gauche) n'est pas toujours remonté
		# par le système du Quest, Y (gauche) et B (droite) le sont toujours.
		var right_b := right_hand.is_button_pressed(&"by_button") and not right_hand.is_button_pressed(&"ax_button") # B seul sort ; A+B réinitialise
		pressed = left_hand.is_button_pressed(&"menu_button") \
			or left_hand.is_button_pressed(&"by_button") \
			or right_b
	elif InputMap.has_action(&"dbg_lobby"):
		pressed = Input.is_action_pressed(&"dbg_lobby")
	_tick_lobby_hold(pressed, delta)


## Séparé de la lecture des boutons pour pouvoir être testé en headless.
func _tick_lobby_hold(pressed: bool, delta: float) -> void:
	if not pressed or not game_started:
		if _lobby_hold > 0.0:
			_show_lobby_hud(false)
		_lobby_hold = 0.0
		_lobby_ticks = 0
		return
	if _lobby_hold == 0.0:
		_log("GAME", "maintien du bouton retour au lobby détecté")
	_lobby_hold += delta
	_show_lobby_hud(true)
	# Deux vibrations de plus en plus fortes annoncent le retour, pour pouvoir lâcher à temps.
	var ticks := int(_lobby_hold / (LOBBY_HOLD / 3.0))
	if ticks > _lobby_ticks and ticks < 3:
		_lobby_ticks = ticks
		_pulse_haptics(0.2 + 0.25 * ticks, 0.08, left_hand)
	if _lobby_hold >= LOBBY_HOLD:
		_lobby_hold = 0.0
		_lobby_ticks = 0
		_show_lobby_hud(false)
		_log("GAME", "retour au lobby demandé (bouton maintenu)")
		_pulse_haptics(0.8, 0.2)
		return_to_lobby()


## Indicateur « Retour au lobby » : une barre qui se remplit, visible par-dessus le décor.
func _show_lobby_hud(on: bool) -> void:
	if not on:
		if is_instance_valid(_lobby_hud):
			_lobby_hud.visible = false
		return
	if not is_instance_valid(_lobby_hud):
		_lobby_hud = Label3D.new()
		_lobby_hud.name = "RetourLobby"
		_lobby_hud.font = LobbyButton.bold_font()
		_lobby_hud.pixel_size = 0.0007
		_lobby_hud.font_size = 56
		_lobby_hud.outline_size = 10
		_lobby_hud.outline_modulate = Color(0, 0, 0, 0.9)
		_lobby_hud.modulate = Color(1.0, 0.85, 0.35)
		_lobby_hud.no_depth_test = true
		_lobby_hud.render_priority = 100
		_lobby_hud.position = Vector3(0.0, -0.12, -0.6)
		xr_camera.add_child(_lobby_hud)
	var filled := clampi(int(_lobby_hold / LOBBY_HOLD * 10.0), 0, 10)
	_lobby_hud.text = "RETOUR AU LOBBY\n[%s%s]" % ["#".repeat(filled), "-".repeat(10 - filled)]
	_lobby_hud.visible = true


func _on_button_released(action_name: String, hand: XRController3D) -> void:
	var sb := _sbx()
	if action_name == &"grip_click" and sb != null:
		sb.release(hand)


## Le bac à sable de la partie en cours : celui de la Chasse, ou celui (léger) de la Résistance.
func _sbx() -> HuntSandbox:
	if mode == Mode.HUNT:
		return hunt.sandbox if hunt != null else null
	return sandbox


## Grip : attrape l'objet visé ou touché ; relâché, l'objet part avec l'élan de la main.
## Au bureau (touche G) la même touche attrape puis lâche.
func _toggle_grab(hand: Node3D, force_grab := false) -> void:
	var sb := _sbx()
	if sb == null:
		return
	if sb.is_holding(hand) and not force_grab:
		sb.release(hand)
	else:
		sb.grab(hand)


func _cycle_weapon() -> void:
	var sb := _sbx()
	if sb == null:
		return
	sb.cycle_weapon()
	_say("Arme : %s" % sb.weapon_name())


# ---------------------------------------------------------------------------
# Mode Résistance : objets attrapables et GPS vers la pilule
# ---------------------------------------------------------------------------
func _start_resist_extras() -> void:
	var hands: Array[Node3D] = [left_hand, right_hand]
	sandbox = HuntSandbox.new()
	sandbox.name = "Sandbox"
	add_child(sandbox)
	sandbox.setup(apartment, xr_camera, hands, profile.active_items(), true)
	nav = NavGrid.new()
	nav.name = "Nav"
	add_child(nav)
	# Le téléphone sort tout de suite : il porte le GPS de la pilule.
	if phone != null:
		phone.set_gps(true, "GPS  -  TA PILULE")
		_pill_gps_on = true
		if not phone.is_in_hand:
			phone.toggle_pocket()
	await nav.compute_reachable(xr_camera.global_position, Vector2(-3.9, -4.7), Vector2(14.2, 7.3))
	_refresh_pill_nav()


func _refresh_pill_nav() -> void:
	if nav == null or apartment == null:
		return
	var dose := apartment.get_dose()
	if dose != null and is_instance_valid(dose):
		nav.build_distance_field(dose.global_position)


## Flèche vers la pilule tant qu'on ne l'a pas en main ; elle s'éteint quand on la tient.
func _tick_pill_gps() -> void:
	if phone == null or nav == null or apartment == null:
		return
	var dose := apartment.get_dose()
	var holding := is_instance_valid(_held_pill)
	if dose == null or not is_instance_valid(dose) or holding or game_over:
		if _pill_gps_on:
			phone.set_gps(false)
			_pill_gps_on = false
		return
	if not _pill_gps_on:
		phone.set_gps(true, "GPS  -  TA PILULE")
		_pill_gps_on = true
	var info := nav.gps_info(xr_camera, dose.global_position, 0)
	if not info.is_empty():
		phone.update_gps(float(info["angle"]), float(info["distance"]), 0)


# ---------------------------------------------------------------------------
# Retours haptiques : la manette vibre quand la main touche un meuble, un mur, un objet
# ---------------------------------------------------------------------------
func _tick_touch_haptics(delta: float) -> void:
	if not xr_active or not game_started or game_over:
		return
	if _touch_shape == null:
		_touch_shape = SphereShape3D.new()
		_touch_shape.radius = 0.1
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _touch_shape
	params.collision_mask = 1 | PropBody.LAYER
	var space := get_world_3d().direct_space_state
	for hand in [left_hand, right_hand]:
		var pos: Vector3 = hand.global_position
		var speed := 0.0
		if _touch_prev.has(hand) and delta > 0.0:
			speed = (pos - (_touch_prev[hand] as Vector3)).length() / delta
		_touch_prev[hand] = pos
		params.transform = Transform3D(Basis.IDENTITY, pos)
		var touching := not space.intersect_shape(params, 1).is_empty()
		var was: bool = _touch_state.get(hand, false)
		if touching and not was:
			# Choc d'arrivée : d'autant plus fort que la main arrive vite.
			_pulse_haptics(clampf(0.3 + speed * 0.18, 0.3, 0.9), 0.08, hand)
		elif touching and speed > 0.25:
			# On frotte contre la surface : petit grondement continu.
			_pulse_haptics(0.12, 0.04, hand)
		_touch_state[hand] = touching


## Saut (mode Chasse) : un petit bond, pas de plafond de verre — la capsule suit.
func jump() -> void:
	if mode != Mode.HUNT or not game_started or game_over or _jump_y > 0.0:
		return
	_jump_vy = JUMP_SPEED
	_jump_y = 0.001


func _tick_jump(delta: float) -> void:
	if _jump_y <= 0.0:
		return
	_jump_vy -= GRAVITY * delta
	_jump_y += _jump_vy * delta
	var base_y := 1.7 if not xr_active else 0.0
	if _jump_y <= 0.0:
		_jump_y = 0.0
		_jump_vy = 0.0
	xr_origin.position.y = base_y + _jump_y


## Mise à jour de la flèche du téléphone : elle montre le chemin vers le mur qui cogne.
func _tick_hunt_gps() -> void:
	if hunt == null or phone == null:
		return
	var info := hunt.gps_info()
	if info.is_empty():
		return
	phone.update_gps(float(info["angle"]), float(info["distance"]), int(info["vertical"]))


## Recentre le suivi du casque là où le joueur se tient, puis mesure sa taille.
## Appelé au lancement et à la réinitialisation.
func _recalibrate() -> void:
	if xr_active:
		XRServer.center_on_hmd(XRServer.RESET_FULL_ROTATION, true)
	_fit_timer = 0.3


func _tick_fit(delta: float) -> void:
	if _fit_timer < 0.0:
		return
	_fit_timer -= delta
	if _fit_timer > 0.0:
		return
	_fit_timer = -1.0
	if xr_active:
		var eyes := xr_camera.position.y # hauteur des yeux au-dessus du sol (origine à 0)
		if eyes > 0.9 and eyes < 2.4:
			player_height = eyes
	if _body != null:
		_body.fit(player_height)


## Remet le joueur au point de départ, orienté vers l'avant, sans toucher à la partie.
func reset_position() -> void:
	_recalibrate()
	var spawn := LOBBY_SPAWN if not game_started else APARTMENT_SPAWN
	_jump_y = 0.0
	_jump_vy = 0.0
	xr_origin.position = Vector3(spawn.x, 0.0 if xr_active else 1.7, spawn.y)
	xr_origin.rotation = Vector3.ZERO
	_movement_body.position = Vector3(0.0, CAPSULE_CENTER_Y - xr_origin.position.y, 0.0)
	_desktop_yaw = 0.0
	_pulse_haptics(0.3, 0.1)
	_log("GAME", "réinitialisation de position")


## Boutons X/Y et grip : sortir ou ranger le téléphone. Menu : relancer après game over.
func _on_button_pressed(action_name: String, hand: XRController3D) -> void:
	# Mode Chasse : grip = attraper/lancer, A = sauter, clic du stick droit = changer d'arme.
	if game_started and not game_over and (mode == Mode.HUNT or mode == Mode.RESIST):
		if action_name == &"grip_click":
			_toggle_grab(hand, true)
			return
	if mode == Mode.HUNT and game_started and not game_over:
		if action_name == &"ax_button" and hand == right_hand:
			jump()
			return
		if action_name == &"primary_click" and hand == right_hand:
			_cycle_weapon()
			return
	if action_name in [&"ax_button", &"by_button", &"grip_click", &"primary_click"]:
		if phone:
			phone.toggle_pocket()
	# Le bouton menu sert au retour au lobby (maintien) : voir _poll_lobby_exit.


# ---------------------------------------------------------------------------
# Objets tenus : clé et pilule
# ---------------------------------------------------------------------------
func _pickup_key(key: KeyObject) -> void:
	if not is_instance_valid(key):
		return
	if _held_key:
		_say("Ta main est déjà pleine.")
		return
	_held_key = key
	key.is_held = true
	key.name = "HeldKey"
	key.reparent(right_hand)
	key.position = Vector3(0.0, -0.08, 0.12)
	key.rotation = Vector3(PI / 2, 0, 0)
	_log("GAME", "clé ramassée")
	_say("Tu as une clé. Elle sert à quelque chose…")
	_pulse_haptics(0.35, 0.10, right_hand)


func pickup_pill(pill: Dose) -> void:
	if not is_instance_valid(pill):
		return
	if _held_pill and is_instance_valid(_held_pill):
		_say("Tu tiens déjà une pilule.")
		return
	_held_pill = pill
	pill.is_held = true
	pill.camera = xr_camera
	pill.name = "HeldPill"
	pill.reparent(right_hand)
	pill.position = Vector3(0.0, -0.06, 0.10)
	pill.rotation = Vector3(PI / 2, 0, 0)
	_log("GAME", "pilule saisie")
	_say("Tu l'as. Porte-la à ta bouche. Gâchette = avaler.")
	_pulse_haptics(0.40, 0.10, right_hand)


## Vibration quand la pilule entre dans la zone de la bouche (pas de point à l'écran).
func _tick_pill_feedback() -> void:
	if not (_held_pill and is_instance_valid(_held_pill)):
		_pill_ready = false
		return
	var ready := _held_pill.can_eat()
	if ready and not _pill_ready:
		# Pilule à la bouche : on l'avale tout de suite, sans appuyer sur la gâchette.
		_pulse_haptics(0.3, 0.06, right_hand)
		_held_pill.interact()
		ready = false
	_pill_ready = ready


## Vibration qui s'accélère quand on approche de la pilule (aide sans texte).
func _tick_pill_proximity(delta: float) -> void:
	var dose: Node3D = apartment.get_dose() if apartment else null
	if dose == null or not is_instance_valid(dose) or (dose is Dose and (dose as Dose).is_held):
		return
	var d := xr_camera.global_position.distance_to(dose.global_position)
	if d > 4.0:
		return
	_prox_timer -= delta
	if _prox_timer <= 0.0:
		_prox_timer = remap(clampf(d, 0.5, 4.0), 0.5, 4.0, 0.25, 1.3)
		_pulse_haptics(remap(clampf(d, 0.5, 4.0), 0.5, 4.0, 0.45, 0.12), 0.06)


## « Ta pilule brille à gauche, pas loin » : relatif au regard.
func _pill_hint() -> String:
	var dose: Node3D = apartment.get_dose() if apartment else null
	if dose == null or not is_instance_valid(dose):
		return ""
	var to := dose.global_position - xr_camera.global_position
	var local := xr_camera.global_transform.basis.inverse() * to
	var dist := Vector2(to.x, to.z).length()
	var side := ""
	if absf(local.x) > absf(local.z):
		side = "à ta droite" if local.x > 0.0 else "à ta gauche"
	else:
		side = "devant toi" if local.z < 0.0 else "derrière toi"
	var far := "tout près" if dist < 2.5 else ("très loin" if dist > 8.0 else "pas loin")
	return "Ta pilule brille %s, %s." % [side, far]


func _consume_key() -> void:
	if _held_key and is_instance_valid(_held_key):
		_held_key.queue_free()
	_held_key = null


func _consume_pill() -> void:
	if _held_pill and is_instance_valid(_held_pill):
		_held_pill.queue_free()
	_held_pill = null
	_pill_ready = false


# ---------------------------------------------------------------------------
# Conteneurs, mimics et doses
# ---------------------------------------------------------------------------
func _on_container_lock_broken(_container: Node3D, noise: float) -> void:
	_consume_key()
	sanity = minf(100.0, sanity + 8.0)
	_pulse_haptics()
	_log("GAME", "verrou forcé (bruit=%.1f)" % noise)
	_say("Le verrou cède avec un CRAC. Quelque part, quelque chose s'est levé de son sommeil.")
	spawn_mobile_mimic()


func _on_container_unlocked_by_key(_container: Node3D) -> void:
	_consume_key()
	_log("GAME", "déverrouillé par clé")
	_say("La clé tourne dans le silence. Il n'a rien entendu.")
	_pulse_haptics(0.30, 0.10)


func _on_container_force_progress(_container: Node3D, hits: int, required: int) -> void:
	_pulse_haptics(0.2, 0.08)
	_say("Forcer le meuble : %d/%d" % [hits, required])


func _on_container_key_required(_container: Node3D) -> void:
	_say("Il te faut la bonne clé pour ce meuble.")


## Un mimic mobile a atteint le joueur.
func on_mimic_close() -> void:
	sanity = minf(100.0, sanity + 12.0)
	_pulse_haptics()
	_log("GAME", "mimic mobile atteint le joueur")
	_say("Il est là. Juste derrière ta nuque. Tu sens son souffle froid.")


## Un verrou forcé attire un mimic mobile, qui arrive des coins de la pièce.
func spawn_mobile_mimic() -> void:
	var m := Mimic.new()
	m.name = "MobileMimic"
	m.is_mobile = true
	m.move_speed = 0.35
	m.attract_target = xr_camera
	add_child(m)
	var edges := [
		Vector3(-3.4, 0.0, -2.4),
		Vector3(3.4, 0.0, -2.4),
		Vector3(-3.4, 0.0, 2.4),
		Vector3(3.4, 0.0, 2.4),
	]
	m.position = edges.pick_random()
	_log("GAME", "mimic mobile spawné à %s" % m.position)


## Appelé par la pilule avalée.
func on_dose_taken() -> void:
	dose_count += 1
	sanity = maxf(0.0, sanity - SANITY_DOSE_RELIEF)
	sanity_rate = SANITY_RATE_AFTER_DOSE
	_consume_pill()
	_log("GAME", "dose avalée n°%d (folie=%.0f)" % [dose_count, sanity])
	_pulse_haptics()
	_say("Dose absorbée. Ça va mieux… pour l'instant. Cherche la suivante. Il n'y a PAS de sortie.")
	await get_tree().create_timer(2.0).timeout
	if game_started and not game_over and apartment != null:
		_spawn_dose()


## Appelé par un mimic purgé : le doute coûte cher.
func on_mimic_purged() -> void:
	sanity = minf(100.0, sanity + 6.0)
	_pulse_haptics()
	_say("C'était pas ta tasse. Elle t'observait. La prochaine pilule est ailleurs.")


func _spawn_dose() -> void:
	apartment.spawn_dose(xr_camera.global_position)
	_refresh_pill_nav()
	_log("GAME", "dose spawnée")


# ---------------------------------------------------------------------------
# Téléphone : compte à rebours et messages (le seul retour écrit du jeu)
# ---------------------------------------------------------------------------
## Un message du subconscient, affiché et lu sur le téléphone (diégétique).
## Après l'assimilation, le téléphone ne reçoit plus rien, sauf le message de fin.
func _say(text: String, is_alert := false, force := false) -> void:
	if game_over and not force:
		return
	if phone:
		phone.receive_message(text, is_alert)


## Chaque seconde : compte à rebours sur l'écran du téléphone.
## Toutes les MESSAGE_INTERVAL secondes : un message, de plus en plus pressant.
func _tick_phone(delta: float) -> void:
	_clock_accum += delta
	if _clock_accum < 1.0:
		return
	_clock_accum = 0.0
	var t := sanity / 100.0
	var remaining := (100.0 - sanity) / maxf(sanity_rate, 0.01)
	var time_str := "%02d:%02d" % [int(remaining) / 60, int(remaining) % 60]
	if phone:
		phone.update_timer(time_str, sanity)
	_hint_timer += 1.0
	if _hint_timer >= 15.0 and not (_held_pill and is_instance_valid(_held_pill)):
		_hint_timer = 0.0
		var hint := _pill_hint()
		if hint != "":
			_say(hint)
	_message_timer += 1.0
	if _message_timer < MESSAGE_INTERVAL:
		return
	_message_timer = 0.0
	_message_count += 1
	var pool: Array = CHAT_CALME
	var is_alert := false
	if t * 100.0 > FOLIE_CRITIQUE:
		pool = CHAT_CRITIQUE
		is_alert = true
	elif t * 100.0 > FOLIE_LEGERE:
		pool = CHAT_INQUIET
	_say("%s (%s)" % [pool[_message_count % pool.size()], time_str], is_alert)


# ---------------------------------------------------------------------------
# Fin de partie : le téléphone sort de la poche et porte le message
# ---------------------------------------------------------------------------
func _trigger_game_over() -> void:
	game_over = true
	last_tokens = compute_resist_tokens(run_time, dose_count)
	profile.add_tokens(last_tokens)
	_log("GAME", "game over : assimilation (%.0f s, %d doses, +%d tokens)" % [run_time, dose_count, last_tokens])
	_say(GAME_OVER_TEXT + "
Tu as tenu %d s : +%d tokens." % [int(run_time), last_tokens], true, true)
	if phone and not phone.is_in_hand:
		phone.toggle_pocket()
	_set_laser_target(false)
	# Les mimics cessent d'agir : plus de contact ni de message après la fin.
	for mimic in _all_mimics():
		mimic.set_physics_process(false)
		mimic.set_process(false)


func _all_mimics() -> Array:
	var all: Array = []
	for mimic in apartment.mimics:
		if is_instance_valid(mimic):
			all.append(mimic)
	for child in get_children():
		if child is Mimic:
			all.append(child)
	return all


## Tokens du mode Résistance : le temps tenu compte le plus, chaque pilule avalée aussi.
static func compute_resist_tokens(seconds: float, doses: int) -> int:
	return int(seconds * TOKENS_PER_SECOND) + doses * TOKENS_PER_DOSE


func _restart() -> void:
	game_over = false
	sanity = START_SANITY
	run_time = 0.0
	sanity_rate = SANITY_RATE
	dose_count = 0
	_message_timer = 0.0
	for mimic in _all_mimics():
		if mimic.is_mobile:
			mimic.queue_free()
		else:
			mimic.set_physics_process(true)
			mimic.set_process(true)
	_consume_pill()
	_consume_key()
	apartment.reset_containers()
	_spawn_dose()
	if creepy_voices:
		creepy_voices.enabled = true
	_log("GAME", "recommencer")
	_say("Encore une chance. Trouve la pilule. Il n'y a pas de sortie.")


# ---------------------------------------------------------------------------
# Mode Chasse et retour au lobby
# ---------------------------------------------------------------------------
func _start_hunt() -> void:
	hunt = HuntMode.new()
	hunt.name = "Hunt"
	add_child(hunt)
	var hands: Array[Node3D] = [left_hand, right_hand]
	hunt.setup(apartment, xr_camera, hands)
	hunt.owned_items = profile.active_items()
	hunt.message.connect(_on_hunt_message)
	hunt.hunt_finished.connect(_on_hunt_finished)
	# Les objets deviennent physiques : le joueur est bloqué par eux (couche 8) mais pas par ses propres armes.
	_movement_body.collision_mask = 1 | PropBody.LAYER
	# Plus rien à faire des mimics ici : on libère le processeur du casque pour la physique.
	for mimic in apartment.mimics:
		if is_instance_valid(mimic):
			mimic.set_physics_process(false)
			mimic.set_process(false)
	# Le téléphone sort tout de suite : c'est le GPS.
	if phone != null:
		phone.set_gps(true, "GPS  -  ÇA COGNE")
		if not phone.is_in_hand:
			phone.toggle_pocket()
	hunt.start()


func _start_reel() -> void:
	reel = ReelMode.new()
	reel.name = "Reel"
	add_child(reel)
	var hands: Array[Node3D] = [left_hand, right_hand]
	reel.setup(apartment, xr_camera, hands, profile, _world_env.environment if _world_env != null else null)
	reel.message.connect(_on_hunt_message)
	reel.session_finished.connect(_on_reel_finished)
	reel.start()
	if is_instance_valid(_body):
		_body.visible = true # le corps n'existe que pour filmer
	var spawn := reel.player_start()
	xr_origin.position = Vector3(spawn.x, xr_origin.position.y, spawn.z)
	xr_origin.rotation = Vector3(0.0, ReelMode.PLAYER_YAW, 0.0) # face au trépied
	_desktop_yaw = ReelMode.PLAYER_YAW
	xr_camera.rotation = Vector3.ZERO


func _on_reel_finished(reels: int, tokens: int, best_views: int) -> void:
	game_over = true
	last_tokens = tokens
	_log("GAME", "séance de réels terminée : %d réels, meilleur score %d vues, +%d tokens" % [reels, best_views, tokens])
	var text := "Séance terminée.
%d réel(s), meilleur : %s vues.
+%d tokens. Tu as maintenant %s abonnés.
Gâchette : retour au lobby." % [
		reels, ReelData.format_count(best_views), tokens, ReelData.format_count(profile.followers)]
	if reels == 0:
		text = "Aucun réel posté : 0 token. L'Algorithme t'a oublié.
Gâchette : retour au lobby."
	_say(text, true, true)
	if phone and not phone.is_in_hand:
		phone.toggle_pocket()
	_set_laser_target(false)


func _on_hunt_message(text: String, is_alert: bool) -> void:
	_say(text, is_alert)


func _on_hunt_finished(walls: int, tokens: int) -> void:
	game_over = true
	last_tokens = tokens
	profile.add_tokens(tokens)
	_log("GAME", "chasse terminée : %d murs cassés, +%d tokens" % [walls, tokens])
	var broken := hunt.sandbox.destroyed_count if hunt != null and hunt.sandbox != null else 0
	_say("%d murs défoncés pour rien, %d objets cassés : +%d tokens.
Gâchette : retour au lobby." % [walls, broken, tokens], true, true)
	if phone:
		phone.set_gps(false)
	if phone and not phone.is_in_hand:
		phone.toggle_pocket()
	_set_laser_target(false)


## Démonte la partie et revient au lobby (les tokens sont déjà crédités).
func return_to_lobby() -> void:
	_log("GAME", "retour au lobby")
	if is_instance_valid(_body):
		_body.visible = false
	_movement_body.collision_mask = 1
	_jump_y = 0.0
	_jump_vy = 0.0
	for node in [sandbox, nav]:
		if is_instance_valid(node):
			node.queue_free()
	sandbox = null
	nav = null
	_pill_gps_on = false
	_touch_state.clear()
	if is_instance_valid(_pointed) and _pointed.has_method(&"on_unpointed"):
		_pointed.on_unpointed()
	_pointed = null
	_consume_pill()
	_consume_key()
	for mimic in _all_mimics():
		if is_instance_valid(mimic) and mimic.is_mobile:
			mimic.queue_free()
	if is_instance_valid(reel):
		reel.shutdown()
	for node in [hunt, reel, apartment, creepy_voices, phone, _world_env]:
		if is_instance_valid(node):
			node.queue_free()
	hunt = null
	reel = null
	apartment = null
	creepy_voices = null
	phone = null
	_world_env = null
	game_over = false
	game_started = false
	mode = Mode.NONE
	sanity = START_SANITY
	sanity_rate = SANITY_RATE
	dose_count = 0
	run_time = 0.0
	_message_timer = 0.0
	_message_count = 0
	_set_laser_target(false)
	_build_lobby()


func pulse_haptics(amplitude := 0.45, duration := 0.12, hand: XRController3D = null) -> void:
	_pulse_haptics(amplitude, duration, hand)


## Vibration Quest 2 : amplitude 0..1, durée en secondes. Sans manette active : rien.
func _pulse_haptics(amplitude := 0.45, duration := 0.12, hand: XRController3D = null) -> void:
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
