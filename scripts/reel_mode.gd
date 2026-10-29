class_name ReelMode
extends Node3D
## Mode « Réels » : un studio de tournage dans l'appartement.
##
## 1. Le tableau des tendances propose des idées de réels complotistes (écrites en
##    direct par le LLM quand le serveur répond, sinon tirées d'une réserve locale)
##    et quatre tons à adopter. On en choisit une et un ton en les visant.
## 2. On se place sur la croix rose face au trépied et on appuie sur REC : compte à
##    rebours, puis 30 s maximum devant la caméra. L'écran de retour montre ce que
##    voit la caméra (avec ton avatar, tes mains, et tes tableaux achetés derrière
##    toi), le prompteur te guide, le micro mesure COMMENT tu parles.
## 3. Le réel part au jury (le LLM) avec l'idée, le ton, les mesures de ta voix et
##    UNE image de ta prise. Sa réponse arrive en flux : vues, likes, verdict puis
##    commentaires s'affichent dès qu'ils tombent. Pendant ce temps on peut tourner
##    le réel suivant. Les tokens dépendent de la popularité.

signal message(text: String, is_alert: bool)
signal session_finished(reels: int, tokens: int, best_views: int)
signal reel_judged(index: int)

enum State { CHOOSING, COUNTDOWN, RECORDING, FINISHING }

const MAX_REELS := 6
const MIN_TAKE := 6.0
const MAX_TAKE := 30.0
const CAPTURE_AT := 9.0 ## seconde de la prise où l'on photographie le cadre
const AVATAR_LAYER := 1 << 19 ## visible seulement de la caméra du trépied

# Plan du studio (coordonnées monde) : le décor est le mur est du salon (le tableau
# royal s'y accroche une fois acheté), la caméra filme vers l'est.
const MARK := Vector3(2.7, 0.0, -0.75)
const TRIPOD := Vector3(0.95, 0.0, -0.5)
const CAM_HEIGHT := 1.45
const SCREEN_POS := Vector3(2.65, 1.42, -2.1)
const BOARD_POS := Vector3(2.65, 0.0, 1.6)
const REC_POS := Vector3(0.95, 1.1, 0.1)
const PLAYER_YAW := PI / 2.0 # face à l'ouest, vers le trépied

const CUES := [
	{"until": 6.0, "text": "Accroche : « %s »"},
	{"until": 16.0, "text": "Montre ta PREUVE : pointe un truc de l'appart du doigt !"},
	{"until": 24.0, "text": "Tout s'explique… révèle le complot, sans trembler."},
	{"until": 999.0, "text": "La chute ! Dis-leur de s'abonner (et de vendre leurs meubles)."},
]

var apartment: MapBase = null
var camera: Node3D = null
var hands: Array[Node3D] = []
var profile: PlayerProfile = null
var environment: Environment = null

var state: State = State.CHOOSING
var interactables: Array[Node3D] = []
var reels: Array[Dictionary] = []
var session_tokens := 0
var best_views := 0
var voice: VoiceMeter = null
var premises: Array[Dictionary] = []
var premise_index := -1
var tone_index := -1
var started := false

var cam_vp: SubViewport = null
var monitor: ReelMonitor = null
var post: ReelPostView = null
var rec_button: LobbyButton = null

var _cam: Camera3D = null
var _monitor_quad: MeshInstance3D = null
var _post_quad: MeshInstance3D = null
var _tabs: Node3D = null
var _tab_buttons: Array[LobbyButton] = []
var _board: Node3D = null
var _premise_cards: Array[LobbyButton] = []
var _tone_cards: Array[LobbyButton] = []
var _reroll_button: LobbyButton = null
var _end_button: LobbyButton = null
var _status_label: Label3D = null
var _hint_label: Label3D = null
var _avatar_head: MeshInstance3D = null
var _avatar_body: MeshInstance3D = null
var _avatar_hands: Array[MeshInstance3D] = []
var _heart_texture: Texture2D = null
var _selected := -1 ## index du réel affiché à l'écran (-1 = caméra)
var _take_time := 0.0
var _captured: Image = null
var _viewers := 0.0
var _feed_clock := 0.0
var _heart_clock := 0.0
var _cam_clock := 0.0
var _seen_premises: Array[String] = []
var _ideas_client: LlmClient = null
var _judge_client: LlmClient = null
var _judging: Dictionary = {}
var _queue: Array[Dictionary] = []
var _live_slot := 0
var _rng := RandomNumberGenerator.new()
var _warned_mark := false


func setup(p_apartment: MapBase, p_camera: Node3D, p_hands: Array[Node3D], p_profile: PlayerProfile, p_env: Environment = null) -> void:
	apartment = p_apartment
	camera = p_camera
	hands = p_hands
	profile = p_profile
	environment = p_env
	_rng.randomize()


## À appeler une fois le nœud dans l'arbre : construit le plateau et démarre le micro.
func start() -> void:
	_heart_texture = ReelIcons.heart()
	_brighten_scene()
	_build_set()
	_build_camera_and_screens()
	_build_board()
	_build_rec_button()
	_build_avatar()
	voice = VoiceMeter.new()
	voice.name = "Voice"
	add_child(voice)
	voice.start()
	_judge_client = LlmClient.new()
	_judge_client.name = "JudgeClient"
	add_child(_judge_client)
	_judge_client.line_received.connect(_on_judge_line)
	_judge_client.finished.connect(_on_judge_finished)
	_ideas_client = LlmClient.new()
	_ideas_client.name = "IdeasClient"
	add_child(_ideas_client)
	_ideas_client.line_received.connect(_on_idea_line)
	_ideas_client.finished.connect(_on_ideas_finished)
	camera.set("cull_mask", int(camera.get("cull_mask")) & ~AVATAR_LAYER)
	_pick_local_premises()
	_refresh_board()
	_show_monitor()
	monitor.show_standby("Place-toi sur la croix rose,\nface à l'objectif.")
	started = true
	_request_live_ideas()
	message.emit("Studio prêt. Choisis une idée et un ton sur le tableau, place-toi sur la croix rose et appuie sur REC.", false)


func shutdown() -> void:
	if is_instance_valid(camera):
		camera.set("cull_mask", int(camera.get("cull_mask")) | AVATAR_LAYER)
	if voice != null:
		voice.stop()
	for c in [_judge_client, _ideas_client]:
		if c != null:
			c.cancel()


## Position de départ du joueur : sur la croix, face au trépied.
func player_start() -> Vector3:
	return MARK


# ---------------------------------------------------------------------------
# Plateau : lumière, croix au sol, trépied
# ---------------------------------------------------------------------------
func _brighten_scene() -> void:
	if environment == null:
		return
	environment.ambient_light_energy = 1.15
	environment.fog_density = 0.01


func _build_set() -> void:
	# Croix rose au sol : l'endroit où se placer.
	var mark := Node3D.new()
	mark.name = "Croix"
	mark.position = MARK + Vector3(0, 0.012, 0)
	add_child(mark)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.65)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 2:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.012, 0.07)
		bar.mesh = bm
		bar.material_override = mat
		bar.rotation.y = PI / 4.0 * (1 if i == 0 else -1)
		mark.add_child(bar)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.36
	tm.outer_radius = 0.4
	ring.mesh = tm
	ring.material_override = mat
	ring.scale = Vector3(1, 0.1, 1)
	mark.add_child(ring)

	# Trépied : trois pieds, une colonne, le téléphone qui filme et un anneau lumineux.
	var tripod := Node3D.new()
	tripod.name = "Trepied"
	tripod.position = TRIPOD
	add_child(tripod)
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.07, 0.07, 0.08)
	black.roughness = 0.5
	black.metallic = 0.4
	for i in 3:
		var leg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.012
		lm.bottom_radius = 0.016
		lm.height = 1.4
		leg.mesh = lm
		leg.material_override = black
		var a := TAU * i / 3.0 + 0.5
		leg.position = Vector3(cos(a) * 0.19, 0.68, sin(a) * 0.19)
		leg.look_at_from_position(leg.position, Vector3(0, 1.4, 0), Vector3.UP)
		leg.rotate_object_local(Vector3.RIGHT, PI / 2.0)
		tripod.add_child(leg)
	var column := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.018
	cm.bottom_radius = 0.018
	cm.height = 0.2
	column.mesh = cm
	column.material_override = black
	column.position.y = CAM_HEIGHT - 0.12
	tripod.add_child(column)
	var phone := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.075, 0.155, 0.009)
	phone.mesh = pm
	phone.material_override = black
	phone.position.y = CAM_HEIGHT
	tripod.add_child(phone)
	var lens := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.012
	sm.height = 0.024
	lens.mesh = sm
	var lens_mat := StandardMaterial3D.new()
	lens_mat.albedo_color = Color(0.1, 0.2, 0.5)
	lens_mat.emission_enabled = true
	lens_mat.emission = Color(0.2, 0.4, 1.0)
	lens_mat.emission_energy_multiplier = 1.4
	lens.material_override = lens_mat
	lens.position = Vector3(0.02, CAM_HEIGHT + 0.055, -0.01)
	tripod.add_child(lens)
	var halo := MeshInstance3D.new()
	var hm := TorusMesh.new()
	hm.inner_radius = 0.15
	hm.outer_radius = 0.18
	halo.mesh = hm
	var halo_mat := StandardMaterial3D.new()
	halo_mat.albedo_color = Color(1.0, 0.95, 0.85)
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo.material_override = halo_mat
	halo.position = Vector3(0, CAM_HEIGHT, -0.03)
	halo.rotation.x = PI / 2.0
	tripod.add_child(halo)

	# Éclairage de plateau : un projecteur chaud braqué sur la croix.
	var key := SpotLight3D.new()
	key.name = "Projecteur"
	key.light_color = Color(1.0, 0.93, 0.82)
	key.light_energy = 1.6
	key.spot_range = 7.0
	key.spot_angle = 38.0
	key.spot_attenuation = 0.6
	key.position = TRIPOD + Vector3(0.3, 2.1, 0.5)
	add_child(key)
	key.look_at(MARK + Vector3(0, 1.3, 0), Vector3.UP)
	var fill := OmniLight3D.new()
	fill.name = "Appoint"
	fill.light_color = Color(0.8, 0.85, 1.0)
	fill.light_energy = 0.8
	fill.omni_range = 5.0
	fill.position = MARK + Vector3(-0.8, 2.0, -0.9)
	add_child(fill)


# ---------------------------------------------------------------------------
# Caméra du trépied, écran de retour et fiche des réels
# ---------------------------------------------------------------------------
func _build_camera_and_screens() -> void:
	cam_vp = SubViewport.new()
	cam_vp.name = "CamVP"
	cam_vp.size = Vector2i(288, 512)
	cam_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(cam_vp)
	_cam = Camera3D.new()
	_cam.name = "Camera"
	_cam.fov = 62.0
	_cam.near = 0.05
	_cam.far = 14.0
	cam_vp.add_child(_cam)
	_cam.global_position = TRIPOD + Vector3(0, CAM_HEIGHT, -0.05)
	_cam.look_at(MARK + Vector3(0, 1.3, 0), Vector3.UP)

	monitor = ReelMonitor.new()
	monitor.name = "Monitor"
	add_child(monitor)
	monitor.set_camera_texture(cam_vp.get_texture())

	post = ReelPostView.new()
	post.name = "Post"
	add_child(post)

	_monitor_quad = _make_screen("EcranCamera", Vector2(0.76, 1.35), monitor)
	_post_quad = _make_screen("EcranReel", Vector2(1.0, 1.61), post)
	_tabs = Node3D.new()
	_tabs.name = "Onglets"
	_tabs.position = SCREEN_POS + Vector3(0, -0.99, 0)
	add_child(_tabs)
	_tabs.rotation.y = _screen_yaw()


func _screen_yaw() -> float:
	# Les écrans regardent la croix (le +Z local d'un quad fait face au joueur).
	var to := MARK - SCREEN_POS
	return atan2(to.x, to.z)


func _make_screen(node_name: String, size_m: Vector2, source: SubViewport) -> MeshInstance3D:
	var holder := MeshInstance3D.new()
	holder.name = node_name
	var bezel := BoxMesh.new()
	bezel.size = Vector3(size_m.x + 0.06, size_m.y + 0.06, 0.04)
	holder.mesh = bezel
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.03, 0.03, 0.04)
	bm.roughness = 0.4
	holder.material_override = bm
	holder.position = SCREEN_POS
	holder.rotation.y = _screen_yaw()
	add_child(holder)
	var face := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size_m
	face.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = source.get_texture()
	face.material_override = mat
	face.position.z = 0.022
	holder.add_child(face)
	var stand := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.06, SCREEN_POS.y - size_m.y * 0.5 - 0.03, 0.05)
	stand.mesh = sb
	stand.material_override = bm
	stand.position = Vector3(0, -(size_m.y * 0.5 + 0.03) - sb.size.y * 0.5, -0.03)
	holder.add_child(stand)
	return holder


func _show_monitor() -> void:
	_selected = -1
	_monitor_quad.visible = true
	_post_quad.visible = false
	_refresh_tabs()


func _show_entry(index: int) -> void:
	if index < 0 or index >= reels.size():
		_show_monitor()
		return
	_selected = index
	_monitor_quad.visible = false
	_post_quad.visible = true
	var entry := reels[index]
	post.reset("nevrose.officiel", profile.followers)
	post.set_frame(entry["image"])
	var result: Dictionary = entry["result"]
	if entry["state"] == "done":
		post.render_final(result, int(entry["tokens"]))
		post.set_judge(String(entry["judge"]))
	else:
		post.set_title(String(entry["premise"]["title"]))
		post.set_analyzing("En attente de l'Algorithme…" if entry["state"] == "queued" else "L'Algorithme regarde ton réel…")
		for key in ["views", "likes", "comments", "shares", "followers"]:
			if result.has(key):
				post.count_up(key, int(result[key]), true)
		if result.has("score"):
			post.set_score(float(result["score"]))
		if result.has("verdict"):
			post.set_verdict(String(result["verdict"]))
		for c in result.get("comment_list", []):
			post.add_comment(c["user"], c["text"], true)
	_refresh_tabs()


func _refresh_tabs() -> void:
	for b in _tab_buttons:
		interactables.erase(b)
		b.queue_free()
	_tab_buttons.clear()
	var total := reels.size() + 1
	var spacing := 0.34
	for i in total:
		var b := LobbyButton.new()
		b.name = "Onglet_%d" % i
		_tabs.add_child(b)
		var title := "CAMÉRA" if i == 0 else "RÉEL %d" % i
		b.setup(Vector2(0.3, 0.14), title, "", Color(0.95, 0.3, 0.62), 0.0013, 0.001)
		b.title_label.position.y = 0.025
		b.title_label.font_size = 36
		b.tag_label.font_size = 30
		b.tag_label.position.y = -0.035
		b.position = Vector3((i - (total - 1) * 0.5) * spacing, 0.0, 0.02)
		var tag := ""
		if i > 0:
			var e := reels[i - 1]
			tag = ReelData.format_count(int(e["result"].get("views", 0))) + " vues" if e["state"] == "done" else "analyse…"
		var current := (i == 0 and _selected == -1) or (i > 0 and _selected == i - 1)
		b.set_state(tag, Color(1.0, 0.85, 0.3) if current else Color(0.95, 0.3, 0.62), true)
		var target := i - 1
		b.pressed.connect(func() -> void: _show_entry(target) if target >= 0 else _show_monitor())
		_tab_buttons.append(b)
		interactables.append(b)


# ---------------------------------------------------------------------------
# Tableau des tendances : idées, tons, actions
# ---------------------------------------------------------------------------
func _build_board() -> void:
	_board = Node3D.new()
	_board.name = "TableauTendances"
	_board.position = BOARD_POS
	add_child(_board)
	_board.rotation.y = atan2(MARK.x - BOARD_POS.x, MARK.z - BOARD_POS.z)

	var back := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(2.45, 1.95)
	back.mesh = bq
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.05, 0.05, 0.075)
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	back.material_override = bmat
	back.position = Vector3(0, 1.45, -0.01)
	_board.add_child(back)
	var rim := MeshInstance3D.new()
	var rq := QuadMesh.new()
	rq.size = Vector2(2.5, 2.0)
	rim.mesh = rq
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.95, 0.3, 0.62)
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim.material_override = rmat
	rim.position = Vector3(0, 1.45, -0.014)
	_board.add_child(rim)
	for x in [-1.1, 1.1]:
		var post_mesh := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = 0.025
		pc.bottom_radius = 0.025
		pc.height = 0.5
		post_mesh.mesh = pc
		post_mesh.material_override = bmat
		post_mesh.position = Vector3(x, 0.25, -0.03)
		_board.add_child(post_mesh)

	var title := _board_label("TENDANCES DU JOUR", 56, Color(1.0, 0.85, 0.35), Vector3(0, 2.33, 0.01))
	_board.add_child(title)
	_status_label = _board_label("", 32, Color(0.6, 0.85, 1.0), Vector3(0, 2.2, 0.01))
	_board.add_child(_status_label)
	_hint_label = _board_label("", 34, Color(0.85, 0.85, 0.9), Vector3(0, 0.58, 0.01))
	_board.add_child(_hint_label)

	for i in 3:
		var card := LobbyButton.new()
		card.name = "Idee_%d" % i
		_board.add_child(card)
		card.setup(Vector2(0.76, 0.88), "", "", Color(0.95, 0.3, 0.62), 0.0021, 0.0017)
		card.position = Vector3((i - 1) * 0.8, 1.68, 0.02)
		card.title_label.position.y = 0.3
		card.title_label.font_size = 36
		card.body_label.font_size = 32
		card.body_label.position.y = -0.1
		card.pressed.connect(_on_premise_pressed.bind(i))
		_premise_cards.append(card)
		interactables.append(card)

	for i in ReelData.TONES.size():
		var t: Dictionary = ReelData.TONES[i]
		var chip := LobbyButton.new()
		chip.name = "Ton_%s" % t["id"]
		_board.add_child(chip)
		chip.setup(Vector2(0.54, 0.26), String(t["label"]), String(t["desc"]), Color(0.3, 0.9, 0.85), 0.0017, 0.0011)
		chip.title_label.position.y = 0.055
		chip.title_label.font_size = 40
		chip.body_label.position.y = -0.05
		chip.body_label.font_size = 34
		chip.position = Vector3((i - 1.5) * 0.59, 1.07, 0.02)
		chip.pressed.connect(_on_tone_pressed.bind(i))
		_tone_cards.append(chip)
		interactables.append(chip)

	_reroll_button = LobbyButton.new()
	_reroll_button.name = "AutresIdees"
	_board.add_child(_reroll_button)
	_reroll_button.setup(Vector2(0.76, 0.2), "AUTRES IDÉES", "", Color(0.6, 0.85, 1.0), 0.0018, 0.001)
	_reroll_button.title_label.position.y = 0.0
	_reroll_button.position = Vector3(-0.8, 0.78, 0.02)
	_reroll_button.pressed.connect(_on_reroll_pressed)
	interactables.append(_reroll_button)

	_end_button = LobbyButton.new()
	_end_button.name = "Terminer"
	_board.add_child(_end_button)
	_end_button.setup(Vector2(0.76, 0.2), "TERMINER", "", Color(1.0, 0.45, 0.35), 0.0018, 0.001)
	_end_button.title_label.position.y = 0.0
	_end_button.position = Vector3(0.8, 0.78, 0.02)
	_end_button.pressed.connect(_on_end_pressed)
	interactables.append(_end_button)


func _board_label(text: String, font_size: int, color: Color, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.0022
	l.outline_size = 6
	l.modulate = color
	l.position = pos
	return l


func _pick_local_premises() -> void:
	premises.clear()
	var pool: Array[Dictionary] = []
	for p in ReelData.PREMISES:
		if not (p["title"] in _seen_premises):
			pool.append(p)
	if pool.size() < 3:
		_seen_premises.clear()
		pool = ReelData.PREMISES.duplicate()
	pool.shuffle()
	for i in 3:
		premises.append(pool[i].duplicate())
		_seen_premises.append(pool[i]["title"])
	premise_index = -1


func _refresh_board() -> void:
	for i in _premise_cards.size():
		var card := _premise_cards[i]
		var p: Dictionary = premises[i]
		card.title_label.text = String(p["title"])
		card.body_label.text = String(p["hook"])
		var chosen := i == premise_index
		var tag := "✔ CHOISIE" if chosen else ("EN DIRECT" if p.get("live", false) else "")
		var accent := Color(1.0, 0.85, 0.3) if chosen else (Color(0.5, 0.95, 0.65) if p.get("live", false) else Color(0.95, 0.3, 0.62))
		card.set_state(tag, accent, state == State.CHOOSING)
	for i in _tone_cards.size():
		var chosen := i == tone_index
		_tone_cards[i].set_state("✔" if chosen else "", Color(1.0, 0.85, 0.3) if chosen else Color(0.3, 0.9, 0.85), state == State.CHOOSING)
	_reroll_button.set_state("", Color(0.6, 0.85, 1.0), state == State.CHOOSING)
	_end_button.set_state("", Color(1.0, 0.45, 0.35), state == State.CHOOSING)
	_refresh_rec_button()
	var pending := _pending_count()
	if state == State.FINISHING:
		_hint_label.text = "L'Algorithme termine d'évaluer %d réel(s)…" % pending
	elif reels.size() >= MAX_REELS:
		_hint_label.text = "Six réels, c'est assez. Appuie sur TERMINER."
	elif premise_index < 0:
		_hint_label.text = "1. Choisis une idée    2. Choisis un ton    3. REC sur le trépied"
	elif tone_index < 0:
		_hint_label.text = "Maintenant, choisis le ton de ta voix."
	else:
		_hint_label.text = "Va sur la croix rose et appuie sur REC au trépied."


func _on_premise_pressed(i: int) -> void:
	if state != State.CHOOSING:
		return
	premise_index = i
	_refresh_board()


func _on_tone_pressed(i: int) -> void:
	if state != State.CHOOSING:
		return
	tone_index = i
	_refresh_board()


func _on_reroll_pressed() -> void:
	if state != State.CHOOSING:
		return
	_pick_local_premises()
	_refresh_board()
	_request_live_ideas()


func _on_end_pressed() -> void:
	if state != State.CHOOSING:
		return
	finish_session()


# ---------------------------------------------------------------------------
# Idées en direct (LLM) : elles remplacent les cartes non choisies à leur arrivée
# ---------------------------------------------------------------------------
func _request_live_ideas() -> void:
	if _ideas_client == null or _ideas_client.busy or not LlmClient.is_available():
		if not LlmClient.is_available():
			_status_label.text = "Mode hors ligne : idées locales"
		return
	if not _judging.is_empty() or not _queue.is_empty():
		return # le serveur est occupé à juger un réel
	_status_label.text = "● L'Algorithme cherche des tendances…"
	_ideas_client.ask(ReelData.ideas_messages(), 150, 1.0)


func _on_idea_line(line: String) -> void:
	var idea := ReelData.parse_idea(line)
	if idea.is_empty():
		return
	for k in 3:
		var slot := (_live_slot + k) % 3
		if slot != premise_index:
			premises[slot] = idea
			_live_slot = (slot + 1) % 3
			break
	_status_label.text = "● Tendances en direct"
	_refresh_board()


func _on_ideas_finished(ok: bool, _text: String) -> void:
	if not ok:
		_status_label.text = "Serveur injoignable : idées locales"
	elif _status_label.text.begins_with("● L'Algorithme"):
		_status_label.text = ""


# ---------------------------------------------------------------------------
# Bouton REC / STOP du trépied
# ---------------------------------------------------------------------------
func _build_rec_button() -> void:
	rec_button = LobbyButton.new()
	rec_button.name = "Rec"
	add_child(rec_button)
	rec_button.setup(Vector2(0.4, 0.36), "REC", "", Color(0.35, 0.95, 0.5), 0.0022, 0.0015)
	rec_button.title_label.position.y = 0.04
	rec_button.position = REC_POS
	rec_button.rotation.y = atan2(MARK.x - rec_button.position.x, MARK.z - rec_button.position.z)
	rec_button.pressed.connect(_on_rec_pressed)
	interactables.append(rec_button)
	# Pied de la télécommande : le bouton ne flotte pas dans le vide.
	var pole := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.015
	pc.bottom_radius = 0.015
	pc.height = REC_POS.y - 0.18
	pole.mesh = pc
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.07, 0.07, 0.08)
	pole.material_override = pole_mat
	var away := Vector3(REC_POS.x - MARK.x, 0.0, REC_POS.z - MARK.z).normalized()
	pole.position = Vector3(REC_POS.x, pc.height * 0.5, REC_POS.z) + away * 0.04
	add_child(pole)
	var base := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.14
	bc.bottom_radius = 0.14
	bc.height = 0.03
	base.mesh = bc
	base.material_override = pole_mat
	base.position = Vector3(pole.position.x, 0.015, pole.position.z)
	add_child(base)


func _refresh_rec_button() -> void:
	if rec_button == null:
		return
	match state:
		State.CHOOSING:
			var ready := premise_index >= 0 and tone_index >= 0 and reels.size() < MAX_REELS
			rec_button.title_label.text = "REC"
			rec_button.set_state("", Color(0.35, 0.95, 0.5), ready)
			if not ready:
				rec_button.set_state("idée + ton d'abord", Color(0.5, 0.5, 0.55), false)
		State.RECORDING:
			rec_button.title_label.text = "STOP"
			rec_button.set_state("%d s" % int(_take_time), Color(1.0, 0.25, 0.25), _take_time >= MIN_TAKE)
		_:
			rec_button.title_label.text = "…"
			rec_button.set_state("", Color(0.5, 0.5, 0.55), false)


func _on_rec_pressed() -> void:
	if state == State.CHOOSING:
		_begin_countdown()
	elif state == State.RECORDING and _take_time >= MIN_TAKE:
		_end_take()


# ---------------------------------------------------------------------------
# Prise : compte à rebours, tournage, publication
# ---------------------------------------------------------------------------
func _begin_countdown() -> void:
	if premise_index < 0 or tone_index < 0 or reels.size() >= MAX_REELS:
		return
	state = State.COUNTDOWN
	_show_monitor()
	_refresh_board()
	if not _warned_mark and Vector2(camera.global_position.x - MARK.x, camera.global_position.z - MARK.z).length() > 1.4:
		_warned_mark = true
		message.emit("Tu n'es pas sur la croix rose : tu risques de ne pas être dans le cadre.", false)
	if _ideas_client.busy:
		_ideas_client.cancel() # le serveur doit rester libre pour le jury
	for n in [3, 2, 1]:
		monitor.show_countdown(n)
		_play(Sfx.beep(false), SCREEN_POS, -4.0)
		await get_tree().create_timer(1.0).timeout
		if not is_inside_tree():
			return
	monitor.show_countdown(0)
	_play(Sfx.beep(true), SCREEN_POS, -2.0)
	_start_take()


func _start_take() -> void:
	state = State.RECORDING
	_take_time = 0.0
	_viewers = 3.0
	_captured = null
	voice.begin_take()
	var main := get_tree().get_first_node_in_group("main")
	if main != null and main.has_method(&"pulse_haptics"):
		main.pulse_haptics(0.5, 0.15)
	_refresh_board()


func _end_take() -> void:
	if state != State.RECORDING:
		return
	state = State.CHOOSING
	var stats := voice.end_take()
	stats["duration"] = minf(_take_time, MAX_TAKE) if not stats.get("mic", false) else stats["duration"]
	if _captured == null:
		_captured = _grab_frame()
	var jpeg := PackedByteArray()
	var shown: Image = _captured
	if _captured != null and not _captured.is_empty():
		var small := _captured.duplicate() as Image
		small.resize(224, 392, Image.INTERPOLATE_BILINEAR)
		small.convert(Image.FORMAT_RGB8)
		jpeg = small.save_jpg_to_buffer(0.82)
	monitor.show_uploading()
	_play(Sfx.whoosh(), SCREEN_POS, -2.0)
	var entry := {
		"id": reels.size() + 1,
		"premise": premises[premise_index].duplicate(),
		"tone": ReelData.TONES[tone_index],
		"voice": stats,
		"image": shown,
		"jpeg": jpeg,
		"state": "queued",
		"result": {},
		"shown": {},
		"shown_comments": 0,
		"tokens": 0,
		"judge": "",
		"followers_at_post": profile.followers,
	}
	reels.append(entry)
	_queue.append(entry)
	premise_index = -1
	tone_index = -1
	_pick_local_premises()
	_refresh_board()
	message.emit("Réel publié. L'Algorithme le regarde : tu peux déjà en tourner un autre.", false)
	await get_tree().create_timer(1.2).timeout
	if not is_inside_tree():
		return
	_show_entry(reels.size() - 1)
	_pump_queue()


func _grab_frame() -> Image:
	# Le rendu factice des tests (headless) n'a pas de texture à relire.
	if cam_vp == null or DisplayServer.get_name() == "headless":
		return null
	var tex := cam_vp.get_texture()
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	return img


func _process(delta: float) -> void:
	if not started:
		return
	_update_avatar()
	_cam_clock += delta
	if _cam_clock >= 0.07 and cam_vp != null:
		_cam_clock = 0.0
		cam_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if state != State.RECORDING:
		return
	_take_time += delta
	var level := voice.level if voice != null else 0.0
	var speaking := voice != null and voice.available and voice.speaking
	# Spectateurs en direct : ils affluent quand tu parles fort, partent quand tu te tais.
	var target_rate := (4.0 + level * 38.0) if speaking else (-1.5 if _viewers > 4.0 else 0.3)
	_viewers = maxf(_viewers + target_rate * delta, 1.0)
	_heart_clock += delta
	if speaking and _heart_clock > lerpf(0.9, 0.18, level):
		_heart_clock = 0.0
		_spawn_heart()
	if _captured == null and _take_time >= CAPTURE_AT:
		_captured = _grab_frame()
	_feed_clock += delta
	if _feed_clock >= 0.1:
		_feed_clock = 0.0
		var cue := _cue_for(_take_time)
		monitor.show_recording(_take_time, MAX_TAKE, level, int(_viewers), cue, voice.available)
		rec_button.set_state("%d s" % int(_take_time), Color(1.0, 0.25, 0.25), _take_time >= MIN_TAKE)
	if _take_time >= MAX_TAKE:
		_end_take()


func _cue_for(t: float) -> String:
	for cue in CUES:
		if t < float(cue["until"]):
			var text: String = cue["text"]
			if text.contains("%s"):
				text = text % String(premises[premise_index]["hook"]) if premise_index >= 0 else text
			return text
	return ""


# ---------------------------------------------------------------------------
# Avatar : ce que la caméra du trépied voit de toi
# ---------------------------------------------------------------------------
func _build_avatar() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.9, 0.72, 0.58)
	var hoodie := StandardMaterial3D.new()
	hoodie.albedo_color = Color(0.2, 0.22, 0.3)
	hoodie.roughness = 0.9
	_avatar_head = MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.11
	hm.height = 0.24
	_avatar_head.mesh = hm
	_avatar_head.material_override = skin
	_avatar_head.layers = AVATAR_LAYER
	add_child(_avatar_head)
	for sx in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.014
		em.height = 0.028
		eye.mesh = em
		var eye_mat := StandardMaterial3D.new()
		eye_mat.albedo_color = Color(0.05, 0.05, 0.06)
		eye.material_override = eye_mat
		eye.layers = AVATAR_LAYER
		eye.position = Vector3(sx * 0.04, 0.02, -0.1)
		_avatar_head.add_child(eye)
	_avatar_body = MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.17
	bm.height = 0.8
	_avatar_body.mesh = bm
	_avatar_body.material_override = hoodie
	_avatar_body.layers = AVATAR_LAYER
	add_child(_avatar_body)
	for i in 2:
		var hand := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.1
		hand.mesh = sm
		hand.material_override = skin
		hand.layers = AVATAR_LAYER
		add_child(hand)
		_avatar_hands.append(hand)


func _update_avatar() -> void:
	if _avatar_head == null or not is_instance_valid(camera):
		return
	var head := camera.global_position
	_avatar_head.global_position = head
	_avatar_head.global_rotation = Vector3(0, camera.global_rotation.y, 0)
	_avatar_body.global_position = Vector3(head.x, head.y - 0.62, head.z)
	_avatar_body.global_rotation = Vector3(0, camera.global_rotation.y, 0)
	for i in mini(hands.size(), _avatar_hands.size()):
		if is_instance_valid(hands[i]):
			_avatar_hands[i].global_position = hands[i].global_position
	# Les mains de la manette ne sont pas dans la caméra du trépied en bureau : on les rapproche du torse.
	var main := get_tree().get_first_node_in_group("main")
	if main != null and not main.is_xr_active():
		var yaw := camera.global_transform.basis
		_avatar_hands[0].global_position = head + (-yaw.z * 0.35 - yaw.x * 0.22) + Vector3(0, -0.4, 0)
		_avatar_hands[1].global_position = head + (-yaw.z * 0.35 + yaw.x * 0.22) + Vector3(0, -0.4, 0)


func _spawn_heart() -> void:
	var s := Sprite3D.new()
	s.texture = _heart_texture
	s.pixel_size = 0.0035
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.modulate = Color(1, 1, 1, 0.95)
	add_child(s)
	var origin := SCREEN_POS + Basis(Vector3.UP, _screen_yaw()) * Vector3(_rng.randf_range(-0.45, 0.45), -0.55, 0.1)
	s.global_position = origin
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "global_position", origin + Vector3(_rng.randf_range(-0.2, 0.2), 1.3, 0.0), 2.2)
	tw.tween_property(s, "modulate:a", 0.0, 2.2).set_delay(0.8)
	tw.chain().tween_callback(s.queue_free)


func _heart_burst(count: int) -> void:
	for i in count:
		get_tree().create_timer(0.06 * i).timeout.connect(_spawn_heart)


# ---------------------------------------------------------------------------
# Le jury : un réel à la fois, réponse en flux
# ---------------------------------------------------------------------------
func _pending_count() -> int:
	var n := 0
	for e in reels:
		if e["state"] != "done":
			n += 1
	return n


func _pump_queue() -> void:
	if not _judging.is_empty() or _queue.is_empty():
		return
	_judging = _queue.pop_front()
	_judging["state"] = "judging"
	if _selected == int(_judging["id"]) - 1:
		post.set_analyzing("L'Algorithme regarde ton réel…")
	_refresh_tabs()
	var ctx := _judge_context(_judging)
	if not LlmClient.is_available():
		_judge_client.ask([], 1) # échec immédiat → juge local
		return
	if _ideas_client.busy:
		_ideas_client.cancel()
	_judge_client.ask(ReelData.judge_messages(ctx, _judging["jpeg"]), 320, 0.9)


func _judge_context(entry: Dictionary) -> Dictionary:
	var previous: Array = []
	for e in reels:
		if e["id"] != entry["id"] and e["state"] == "done":
			previous.append(String(e["result"].get("title", e["premise"]["title"])))
	return {
		"premise": entry["premise"],
		"tone": entry["tone"],
		"voice": entry["voice"],
		"followers": entry["followers_at_post"],
		"previous": previous,
		"decor": _decor_names(),
	}


func _decor_names() -> Array:
	var names: Array = []
	if profile == null:
		return names
	for item in DecorCatalog.ITEMS:
		if profile.owns(String(item["id"])):
			names.append(String(item["name"]))
	return names


func _on_judge_line(line: String) -> void:
	if _judging.is_empty():
		return
	var key := ReelData.parse_line(_judging["result"], line)
	if key != "":
		_judging["judge"] = String(_judge_client.provider_name).get_slice(" · ", 1) if _judge_client.provider_name.contains(" · ") else _judge_client.provider_name
		_enqueue_reveal(_judging, key)
		_reveal_key(_judging, key)


func _on_judge_finished(ok: bool, _text: String) -> void:
	if _judging.is_empty():
		return
	var entry := _judging
	if not ok and not entry["result"].has("views"):
		entry["judge"] = "juge local"
	elif not entry["result"].has("views") or not entry["result"].has("verdict"):
		entry["judge"] = "%s + juge local" % entry["judge"]
	_complete(entry)


## Les lignes du jury peuvent arriver d'un coup (serveur rapide) : on les dévoile
## une par une, avec un petit suspense, pour que l'écran reste lisible.
func _enqueue_reveal(entry: Dictionary, key: String) -> void:
	if not entry.has("reveal_queue"):
		entry["reveal_queue"] = []
	(entry["reveal_queue"] as Array).append(key)
	if entry.get("revealing", false):
		return
	entry["revealing"] = true
	while not (entry["reveal_queue"] as Array).is_empty():
		var next: String = (entry["reveal_queue"] as Array).pop_front()
		_reveal_key(entry, next)
		await get_tree().create_timer(0.6 if next != "comment" else 0.45).timeout
		if not is_inside_tree():
			return
	entry["revealing"] = false


## Affiche ce que le jury vient de dire (si ce réel est à l'écran).
func _reveal_key(entry: Dictionary, key: String) -> void:
	var idx := int(entry["id"]) - 1
	var result: Dictionary = entry["result"]
	var shown_now := idx == _selected
	if shown_now:
		post.set_analyzing("Les chiffres tombent…")
	match key:
		"views":
			entry["shown"]["views"] = true
			if shown_now:
				post.count_up("views", int(result["views"]))
				_play(Sfx.ding(), SCREEN_POS, -3.0)
		"likes":
			entry["shown"]["likes"] = true
			if shown_now:
				post.count_up("likes", int(result["likes"]))
				_heart_burst(clampi(int(result["likes"]) / 80 + 3, 3, 16))
		"comments", "shares":
			entry["shown"][key] = true
			if shown_now:
				post.count_up(key, int(result[key]))
		"followers":
			entry["shown"]["followers"] = true
			if shown_now:
				post.count_up("followers", int(result["followers"]))
		"score":
			entry["shown"]["score"] = true
			if shown_now:
				post.set_score(float(result["score"]))
		"title":
			entry["shown"]["title"] = true
			if shown_now:
				post.set_title(String(result["title"]))
		"verdict":
			entry["shown"]["verdict"] = true
			if shown_now:
				post.set_verdict(String(result["verdict"]))
		"comment":
			var list: Array = result.get("comment_list", [])
			while entry["shown_comments"] < list.size():
				var c: Dictionary = list[entry["shown_comments"]]
				entry["shown_comments"] += 1
				if shown_now:
					post.add_comment(c["user"], c["text"])
					_play(Sfx.pop(), SCREEN_POS, -6.0)


## Fin du flux : complète ce qui manque, fixe les chiffres, révèle les tokens.
func _complete(entry: Dictionary) -> void:
	var ctx := _judge_context(entry)
	var had_all: bool = entry["result"].has("views") and entry["result"].has("verdict")
	ReelData.fill_missing(entry["result"], ctx, _rng)
	if entry["judge"] == "":
		entry["judge"] = "juge local"
	entry["state"] = "done"
	var result: Dictionary = entry["result"]
	var tokens := ReelData.compute_tokens(result)
	entry["tokens"] = tokens
	profile.add_tokens(tokens)
	profile.register_reel(int(result["views"]), int(result["followers"]))
	session_tokens += tokens
	best_views = maxi(best_views, int(result["views"]))
	_judging = {}
	var idx := int(entry["id"]) - 1
	reel_judged.emit(idx)
	_refresh_tabs()
	_pump_queue()
	await _reveal_rest(entry, had_all)
	if not is_inside_tree():
		return
	message.emit("« %s » : %s vues, +%d tokens." % [result["title"], ReelData.format_count(int(result["views"])), tokens], false)
	if state == State.CHOOSING:
		_refresh_board()
	if state == State.FINISHING and _pending_count() == 0:
		_emit_finished()
	elif state == State.FINISHING:
		_refresh_board()


## Dévoile, avec un petit délai entre chaque, ce qui n'a pas encore été montré.
func _reveal_rest(entry: Dictionary, was_streamed: bool) -> void:
	var idx := int(entry["id"]) - 1
	var result: Dictionary = entry["result"]
	while entry.get("revealing", false):
		await get_tree().process_frame
	var order := ["views", "likes", "comments", "shares", "followers", "score", "title", "verdict"]
	for key in order:
		if entry["shown"].get(key, false):
			continue
		_reveal_key(entry, key)
		entry["shown"][key] = true
		if idx == _selected and not was_streamed:
			await get_tree().create_timer(0.55).timeout
			if not is_inside_tree():
				return
	# Chiffres définitifs (le LLM peut avoir exagéré : ils ont été corrigés).
	if idx == _selected:
		for k in ["views", "likes", "comments", "shares", "followers"]:
			post.count_up(k, int(result[k]), true)
		var list: Array = result.get("comment_list", [])
		while entry["shown_comments"] < list.size() and entry["shown_comments"] < ReelPostView.MAX_COMMENTS:
			var c: Dictionary = list[entry["shown_comments"]]
			entry["shown_comments"] += 1
			post.add_comment(c["user"], c["text"])
			_play(Sfx.pop(), SCREEN_POS, -6.0)
			await get_tree().create_timer(0.5).timeout
			if not is_inside_tree():
				return
		post.set_analyzing("", false)
		post.set_judge(String(entry["judge"]))
		post.show_tokens(int(entry["tokens"]))
		_play(Sfx.coins(), SCREEN_POS, -2.0)
		_heart_burst(8)
		var main := get_tree().get_first_node_in_group("main")
		if main != null and main.has_method(&"pulse_haptics"):
			main.pulse_haptics(0.4, 0.2)


# ---------------------------------------------------------------------------
# Fin de séance
# ---------------------------------------------------------------------------
func finish_session() -> void:
	if state == State.FINISHING:
		return
	if _pending_count() == 0:
		state = State.FINISHING
		_emit_finished()
		return
	state = State.FINISHING
	_refresh_board()
	message.emit("L'Algorithme n'a pas fini : on attend ses verdicts avant de fermer le studio.", false)


func _emit_finished() -> void:
	session_finished.emit(reels.size(), session_tokens, best_views)


# ---------------------------------------------------------------------------
func _play(stream: AudioStream, pos: Vector3, volume_db := 0.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.unit_size = 6.0
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)
