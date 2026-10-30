class_name HuntMode
extends Node3D
## Mode « Chasse au monstre » : quelque chose cogne dans les murs et le plafond.
## Casse la plaque qui cogne (gâchette ou coup de poing) ; ça cogne alors ailleurs.
## Au dernier mur, le monstre apparaît… puis se dissout : il n'a jamais existé.
## L'appartement est ravagé pour rien, mais ça rapporte des tokens.

signal message(text: String, is_alert: bool)
signal hunt_finished(walls_broken: int, tokens: int)

const WALLS_MIN := 4
const WALLS_MAX := 6
const CONCURRENT_PLATES := 3 ## endroits qui cognent en même temps : plusieurs murs à casser
const TOKENS_BASE := 8
const TOKENS_PER_WALL := 5
const APT_MIN := Vector2(-3.9, -4.7)
const APT_MAX := Vector2(14.2, 7.3)
const MIN_STEP_DISTANCE := 4.0 ## le prochain mur est au moins à 4 m du précédent
const HINT_PERIOD := 22.0
const PUNCH_SPEED := 2.0 ## m/s : un vrai geste, pas un frôlement
const PUNCH_REACH := 0.6
const TOKENS_PER_3_OBJECTS := 1 ## +1 token tous les 3 objets cassés
const PUNCH_COOLDOWN := 0.4
const VOICE_DIR := "res://assets/voices/"
const VOICE_COUNT := 34 ## v01.wav … v34.wav : toutes les voix du jeu
const VOICE_FIRST_DELAY := 1.4 ## la première voix sort peu après le premier « toc toc »
const VOICE_GAP_MIN := 4.5
const VOICE_GAP_MAX := 7.5

var apartment: MapBase = null
var camera: Node3D = null
var hands: Array[Node3D] = []
var owned_items: Array = [] ## contenu de la boutique possédé (armes)
var sandbox: HuntSandbox = null

var target_count := 5
var broken_count := 0
var current: KnockPatch = null ## plaque la plus proche : sert au GPS et à l'indice
var live_plates: Array[KnockPatch] = [] ## toutes les plaques actives (qui cognent)
var finished := false
var started := false
var monster: Monster = null
var candidates: Array[Dictionary] = []
var patches: Array[KnockPatch] = []
var rejected: Array[Vector3] = [] ## points écartés car inaccessibles (diagnostic)

var voice_streams: Array[AudioStream] = []
var voices_played := 0
var _voice_bag: Array[int] = []
var _last_voice := -1
var _voice_clock := 0.0
var _hint_clock := 0.0
var nav: NavGrid = null ## carte d'accessibilité + GPS


func setup(p_apartment: MapBase, p_camera: Node3D, p_hands: Array[Node3D]) -> void:
	apartment = p_apartment
	camera = p_camera
	hands = p_hands


## Coroutine : attend une frame physique pour que les collisions des meubles existent.
func start() -> void:
	_load_voices()
	target_count = randi_range(WALLS_MIN, WALLS_MAX)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Carte des endroits où l'on peut vraiment se tenir (avant que les meubles ne deviennent mobiles) :
	# aucune plaque ne sera placée derrière une porte verrouillée ni à l'extérieur.
	nav = NavGrid.new()
	nav.name = "Nav"
	add_child(nav)
	await nav.compute_reachable(camera.global_position, APT_MIN, APT_MAX)
	sandbox = HuntSandbox.new()
	sandbox.name = "Sandbox"
	add_child(sandbox)
	sandbox.setup(apartment, camera, hands, owned_items)
	sandbox.swung.connect(_on_swing)
	sandbox.shot.connect(_on_shot)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_collect_candidates()
	started = true
	message.emit("Quelqu'un cogne dans les murs. Écoute. Casse là où ça cogne : gâchette, ou frappe du poing.", false)
	_voice_clock = VOICE_FIRST_DELAY
	for i in CONCURRENT_PLATES:
		_activate_next()
	_refresh_current()


# ---------------------------------------------------------------------------
# Candidats : faces intérieures des murs et dessous du plafond
# ---------------------------------------------------------------------------
func _collect_candidates() -> void:
	candidates.clear()
	_scan(apartment.get_node("Shell"))
	candidates.shuffle()


func _scan(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null and (node as MeshInstance3D).visible:
		var n := String(node.name)
		var parent := node.get_parent()
		if n.begins_with("Mur") or (n == "Mesh" and parent != null and String(parent.name).begins_with("Wall") and parent is StaticBody3D):
			_add_wall_candidates(node as MeshInstance3D)
		elif n == "Mesh" and parent != null and String(parent.name) == "Ceiling":
			_add_ceiling_candidates(node as MeshInstance3D)
	for c in node.get_children():
		_scan(c)


func _wall_color(mi: MeshInstance3D) -> Color:
	var mat: Material = mi.material_override
	if mat == null:
		mat = mi.get_active_material(0)
	if mat is StandardMaterial3D:
		return (mat as StandardMaterial3D).albedo_color
	return Color(0.75, 0.7, 0.62)


func _add_wall_candidates(mi: MeshInstance3D) -> void:
	var b: AABB = mi.global_transform * mi.mesh.get_aabb()
	if b.size.y < 2.0:
		return
	var thin_x := b.size.x < b.size.z
	var length := b.size.z if thin_x else b.size.x
	if minf(b.size.x, b.size.z) > 0.4 or length < 1.4:
		return
	var color := _wall_color(mi)
	var center := b.get_center()
	for side in [-1.0, 1.0]:
		for attempt in 3:
			var along := randf_range(-(length * 0.5 - 0.55), length * 0.5 - 0.55)
			var y := randf_range(1.0, 1.9)
			var n: Vector3
			var pos: Vector3
			if thin_x:
				n = Vector3(side, 0, 0)
				pos = Vector3(center.x + side * (b.size.x * 0.5 + 0.004), y, center.z + along)
			else:
				n = Vector3(0, 0, side)
				pos = Vector3(center.x + along, y, center.z + side * (b.size.z * 0.5 + 0.004))
			_try_candidate(pos, n, color)


func _add_ceiling_candidates(mi: MeshInstance3D) -> void:
	var b: AABB = mi.global_transform * mi.mesh.get_aabb()
	var color := _wall_color(mi)
	for attempt in 4:
		var pos := Vector3(randf_range(b.position.x + 1.0, b.end.x - 1.0),
			b.position.y - 0.004, randf_range(b.position.z + 0.8, b.end.z - 0.8))
		_try_candidate(pos, Vector3.DOWN, color)


## Garde le point s'il est dans l'appartement et dégagé (pas derrière un meuble).
func _try_candidate(pos: Vector3, n: Vector3, color: Color) -> void:
	var front := pos + n * 0.9
	if nav != null and nav.is_ready() and not nav.has_point(front):
		rejected.append(pos)
		return # hors de portée : mur extérieur, pièce fermée, recoin inaccessible
	if front.x < APT_MIN.x or front.x > APT_MAX.x or front.z < APT_MIN.y or front.z > APT_MAX.y:
		return
	if absf(n.y) < 0.5 and (front.y < 0.3):
		return
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(front, pos + n * 0.06)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 1
	if not space.intersect_ray(query).is_empty():
		return
	candidates.append({"pos": pos, "normal": n, "color": color})


# ---------------------------------------------------------------------------
# Déroulement
# ---------------------------------------------------------------------------
func _pick_candidate() -> Dictionary:
	var from: Vector3 = camera.global_position if current == null else current.global_position
	var far: Array[Dictionary] = []
	for c in candidates:
		var p: Vector3 = c["pos"]
		if Vector2(p.x - from.x, p.z - from.z).length() >= MIN_STEP_DISTANCE:
			far.append(c)
	var pool: Array[Dictionary] = far if not far.is_empty() else candidates
	if pool.is_empty():
		return {}
	var choice: Dictionary = pool.pick_random()
	candidates.erase(choice)
	return choice


func _activate_next() -> void:
	if finished:
		return
	var c := _pick_candidate()
	if c.is_empty():
		if _live().is_empty():
			_finish_hunt()
		return
	var patch := KnockPatch.new()
	patch.name = "Knock_%d" % patches.size()
	patch.wall_color = c["color"]
	add_child(patch)
	patch.place(c["pos"], c["normal"])
	patch.broken.connect(_on_patch_broken)
	patches.append(patch)
	live_plates.append(patch)
	patch.activate()


## Plaques actives et non cassées.
func _live() -> Array[KnockPatch]:
	var out: Array[KnockPatch] = []
	for p in live_plates:
		if is_instance_valid(p) and p.active and not p.is_broken:
			out.append(p)
	return out


## La plaque la plus proche devient « current » (GPS, indice). On ne change qu'avec 1 m d'avance.
func _refresh_current() -> void:
	var live := _live()
	if live.is_empty():
		current = null
		return
	var from := camera.global_position
	var best: KnockPatch = live[0]
	for p in live:
		if p.global_position.distance_to(from) < best.global_position.distance_to(from):
			best = p
	var lost := current == null or not is_instance_valid(current) or not current.active or current.is_broken
	if lost or (best != current and best.global_position.distance_to(from) + 1.0 < current.global_position.distance_to(from)):
		current = best
		if nav != null and nav.is_ready():
			nav.build_distance_field(best.global_position + best.normal * 0.7)
		_hint_clock = 0.0

func _on_patch_broken(patch: KnockPatch) -> void:
	broken_count += 1
	live_plates.erase(patch)
	if broken_count >= target_count or (candidates.is_empty() and _live().is_empty()):
		_reveal_monster(patch)
		return
	var lines := [
		"Rien. Un trou, de la poussière. Mais ça cogne encore…",
		"Pas là. Ça a bougé. Écoute.",
		"Il est passé de l'autre côté. Il se moque de toi.",
		"Encore rien. Il est plus rapide que toi.",
	]
	message.emit(lines[(broken_count - 1) % lines.size()], false)
	get_tree().create_timer(2.8).timeout.connect(func() -> void:
		if not finished and is_inside_tree():
			_activate_next())

func _reveal_monster(patch: KnockPatch) -> void:
	finished = true
	var cam_pos := camera.global_position
	var to_player := Vector3(cam_pos.x - patch.global_position.x, 0.0, cam_pos.z - patch.global_position.z)
	if to_player.length() < 0.2:
		to_player = Vector3(patch.normal.x, 0.0, patch.normal.z)
	to_player = to_player.normalized()
	monster = Monster.new()
	monster.name = "Monstre"
	add_child(monster)
	monster.global_position = Vector3(patch.global_position.x, 0.0, patch.global_position.z) + to_player * 1.4
	monster.look_at(Vector3(cam_pos.x, 0.0, cam_pos.z), Vector3.UP, true)
	var sting := AudioStreamPlayer3D.new()
	sting.stream = Sfx.sting()
	sting.volume_db = 6.0
	sting.unit_size = 8.0
	monster.add_child(sting)
	sting.play()
	# Le cri : très fort et strident, presque pas atténué par la distance.
	var scream := AudioStreamPlayer3D.new()
	scream.name = "Cri"
	scream.stream = Sfx.shriek()
	scream.volume_db = 14.0
	scream.max_db = 14.0
	scream.unit_size = 30.0
	scream.position.y = 1.6
	monster.add_child(scream)
	scream.play()
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.1, 0.05)
	flash.light_energy = 3.0
	flash.omni_range = 5.0
	flash.position.y = 1.5
	monster.add_child(flash)
	message.emit("LE VOILÀ.", true)
	get_tree().create_timer(3.2).timeout.connect(func() -> void:
		if is_instance_valid(monster):
			monster.dissolve(1.3)
		get_tree().create_timer(2.2).timeout.connect(_finish_hunt))


func _finish_hunt() -> void:
	finished = true
	var destroyed := sandbox.destroyed_count if sandbox != null else 0
	var tokens := compute_tokens(broken_count, destroyed)
	if sandbox != null:
		sandbox.release_all()
	message.emit("…Il n'y a rien. Il n'y a jamais rien eu. Tu as détruit ton appartement pour rien.", true)
	hunt_finished.emit(broken_count, tokens)


static func compute_tokens(walls: int, destroyed_objects := 0) -> int:
	return TOKENS_BASE + TOKENS_PER_WALL * walls + destroyed_objects * TOKENS_PER_3_OBJECTS / 3


# ---------------------------------------------------------------------------
# Voix dans le mur : une voix au hasard parmi toutes celles du jeu, depuis la plaque
# qui cogne (même point que les coups : c'est là qu'il faut aller).
# ---------------------------------------------------------------------------
func _load_voices() -> void:
	voice_streams.clear()
	for i in range(1, VOICE_COUNT + 1):
		var stream := load("%sv%02d.wav" % [VOICE_DIR, i]) as AudioStream
		if stream != null:
			voice_streams.append(stream)


## Sac mélangé : toutes les voix sortent avant qu'une revienne, jamais deux fois de suite.
func _next_voice_index() -> int:
	if voice_streams.is_empty():
		return -1
	if _voice_bag.is_empty():
		for i in voice_streams.size():
			_voice_bag.append(i)
		_voice_bag.shuffle()
		if _voice_bag.size() > 1 and _voice_bag[_voice_bag.size() - 1] == _last_voice:
			_voice_bag.reverse()
	_last_voice = _voice_bag.pop_back()
	return _last_voice


func _play_wall_voice() -> void:
	var live := _live()
	if live.is_empty():
		return
	var idx := _next_voice_index()
	if idx < 0:
		return
	live.pick_random().play_voice(voice_streams[idx])
	voices_played += 1

# ---------------------------------------------------------------------------
# Indices et coups de poing
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if not started or finished:
		return
	_refresh_current()
	if current == null:
		return
	_voice_clock -= delta
	if _voice_clock <= 0.0:
		_voice_clock = randf_range(VOICE_GAP_MIN, VOICE_GAP_MAX)
		_play_wall_voice()
	_hint_clock += delta
	if _hint_clock >= HINT_PERIOD:
		_hint_clock = 0.0
		message.emit(_direction_hint(), false)

## « Ça cogne à ta gauche, assez loin » : relatif à la direction du regard.
func _direction_hint() -> String:
	var to := current.global_position - camera.global_position
	var local := camera.global_transform.basis.inverse() * to
	var dist := Vector2(to.x, to.z).length()
	var side := ""
	if absf(local.x) > absf(local.z):
		side = "à ta droite" if local.x > 0.0 else "à ta gauche"
	else:
		side = "devant toi" if local.z < 0.0 else "derrière toi"
	if absf(current.normal.y) > 0.5:
		side += ", au plafond"
	var far := "tout près" if dist < 2.5 else ("assez loin" if dist > 6.0 else "pas loin")
	return "Ça cogne %s, %s." % [side, far]


## Un tir : si le projectile passe tout près de la plaque qui cogne, elle encaisse.
func _on_shot(origin: Vector3, end: Vector3, power: float) -> void:
	if finished:
		return
	var seg := end - origin
	for p in _live():
		var t := clampf((p.global_position - origin).dot(seg) / maxf(seg.length_squared(), 0.0001), 0.0, 1.0)
		if (origin + seg * t).distance_to(p.global_position) < 0.4:
			p.hit(maxi(int(round(power * 0.8)), 1))

## Un coup du bac à sable (poing ou arme) : s'il touche la plaque qui cogne, elle encaisse.
func _on_swing(tip: Vector3, _prev: Vector3, _velocity: Vector3, power: float, hand: Node3D) -> void:
	if finished:
		return
	for p in _live():
		if tip.distance_to(p.global_position) < PUNCH_REACH:
			p.hit(maxi(int(round(power)), 1))
			var main := get_tree().get_first_node_in_group("main")
			if main != null and main.has_method(&"pulse_haptics"):
				main.pulse_haptics(0.8, 0.12, hand as XRController3D)
			return

## Pour le téléphone : angle de la flèche (0 = droit devant, + = à droite), distance et plafond.
func gps_info() -> Dictionary:
	if camera == null or current == null or not current.active or finished or nav == null:
		return {}
	return nav.gps_info(camera, current.global_position, 1 if absf(current.normal.y) > 0.5 else 0)
