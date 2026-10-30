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
const TOKENS_BASE := 8
const TOKENS_PER_WALL := 5
const APT_MIN := Vector2(-3.9, -4.7)
const APT_MAX := Vector2(14.2, 7.3)
const MIN_STEP_DISTANCE := 4.0 ## le prochain mur est au moins à 4 m du précédent
const HINT_PERIOD := 22.0
const PUNCH_SPEED := 2.0 ## m/s : un vrai geste, pas un frôlement
const PUNCH_REACH := 0.6
const CELL := 0.3 ## maille de la carte d'accessibilité (GPS et choix des murs)
const PLAYER_RADIUS := 0.3
const TOKENS_PER_3_OBJECTS := 1 ## +1 token tous les 3 objets cassés
const PUNCH_COOLDOWN := 0.4
const VOICE_DIR := "res://assets/voices/"
const VOICE_COUNT := 15 ## v01.wav … v15.wav : toutes les voix du jeu
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
var current: KnockPatch = null
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
var _reachable := {} ## Vector2i -> true : cases du sol où le joueur peut se tenir
var _dist_field := {} ## Vector2i -> pas jusqu'à la plaque qui cogne (GPS)
var _grid_origin := Vector2(-4.0, -4.8)


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
	await _compute_reachable()
	sandbox = HuntSandbox.new()
	sandbox.name = "Sandbox"
	add_child(sandbox)
	sandbox.setup(apartment, camera, hands, owned_items)
	sandbox.swung.connect(_on_swing)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_collect_candidates()
	started = true
	message.emit("Quelqu'un cogne dans les murs. Écoute. Casse là où ça cogne : gâchette, ou frappe du poing.", false)
	_activate_next()


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
	if not _reachable.is_empty() and not _reachable.has(_cell_of(front)):
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
	var c := _pick_candidate()
	if c.is_empty():
		_finish_hunt()
		return
	var patch := KnockPatch.new()
	patch.name = "Knock_%d" % patches.size()
	patch.wall_color = c["color"]
	add_child(patch)
	patch.place(c["pos"], c["normal"])
	patch.broken.connect(_on_patch_broken)
	patches.append(patch)
	current = patch
	_build_distance_field(patch)
	patch.activate()
	_hint_clock = 0.0
	_voice_clock = VOICE_FIRST_DELAY


func _on_patch_broken(patch: KnockPatch) -> void:
	broken_count += 1
	if broken_count >= target_count or candidates.is_empty():
		_reveal_monster(patch)
		return
	var lines := [
		"Rien. Un trou, de la poussière. Mais ça cogne encore…",
		"Pas là. Ça a bougé. Écoute.",
		"Il est passé de l'autre côté. Il se moque de toi.",
		"Encore rien. Il est plus rapide que toi.",
	]
	message.emit(lines[(broken_count - 1) % lines.size()], false)
	current = patch
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
	if current == null or not current.active or current.is_broken:
		return
	var idx := _next_voice_index()
	if idx < 0:
		return
	current.play_voice(voice_streams[idx])
	voices_played += 1


# ---------------------------------------------------------------------------
# Indices et coups de poing
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if not started or finished or current == null or not current.active:
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


## Un coup du bac à sable (poing ou arme) : s'il touche la plaque qui cogne, elle encaisse.
func _on_swing(tip: Vector3, _prev: Vector3, _velocity: Vector3, power: float, hand: Node3D) -> void:
	if current == null or not current.active or finished:
		return
	if tip.distance_to(current.global_position) < PUNCH_REACH:
		current.hit(maxi(int(round(power)), 1))
		var main := get_tree().get_first_node_in_group("main")
		if main != null and main.has_method(&"pulse_haptics"):
			main.pulse_haptics(0.8, 0.12, hand as XRController3D)


# ---------------------------------------------------------------------------
# Accessibilité et GPS : le sol praticable est quadrillé (maille CELL) ; le GPS suit le
# chemin le plus court depuis le joueur jusqu'à la plaque, portes et couloirs compris.
# ---------------------------------------------------------------------------
func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor((p.x - _grid_origin.x) / CELL)), int(floor((p.z - _grid_origin.y) / CELL)))


func _cell_center(c: Vector2i) -> Vector3:
	return Vector3(_grid_origin.x + (c.x + 0.5) * CELL, 0.0, _grid_origin.y + (c.y + 0.5) * CELL)


func _cell_free(space: PhysicsDirectSpaceState3D, params: PhysicsShapeQueryParameters3D, c: Vector2i) -> bool:
	var center := _cell_center(c)
	for h in [0.45, 1.2]:
		params.transform = Transform3D(Basis.IDENTITY, Vector3(center.x, h, center.z))
		if not space.intersect_shape(params, 1).is_empty():
			return false
	return true


func _compute_reachable() -> void:
	_reachable.clear()
	var space := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = PLAYER_RADIUS
	params.shape = shape
	params.collision_mask = 1
	var min_cell := _cell_of(Vector3(APT_MIN.x - 0.3, 0.0, APT_MIN.y - 0.3))
	var max_cell := _cell_of(Vector3(APT_MAX.x + 0.3, 0.0, APT_MAX.y + 0.3))
	var start := _cell_of(camera.global_position)
	# Départ : la case libre la plus proche du joueur.
	for radius in range(0, 6):
		var picked := false
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var c := Vector2i(start.x + dx, start.y + dy)
				if _cell_free(space, params, c):
					start = c
					picked = true
					break
			if picked:
				break
		if picked:
			break
	var queue: Array[Vector2i] = [start]
	_reachable[start] = true
	var head := 0
	var budget := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = cell + d
			if nxt.x < min_cell.x or nxt.y < min_cell.y or nxt.x > max_cell.x or nxt.y > max_cell.y:
				continue
			if _reachable.has(nxt):
				continue
			_reachable[nxt] = false # vu (évite de re-tester)
			if _cell_free(space, params, nxt):
				_reachable[nxt] = true
				queue.append(nxt)
			budget += 1
			if budget % 400 == 0:
				await get_tree().physics_frame # on étale le coût sur plusieurs images (casque)
	# On ne garde que les cases libres.
	for key in _reachable.keys():
		if not _reachable[key]:
			_reachable.erase(key)


## Distance (en pas) de chaque case praticable jusqu'à la plaque, par parcours en largeur.
func _build_distance_field(patch: KnockPatch) -> void:
	_dist_field.clear()
	if _reachable.is_empty():
		return
	var goal := _cell_of(patch.global_position + patch.normal * 0.7)
	if not _reachable.has(goal):
		var best := Vector2i.ZERO
		var best_d := 1e9
		for c in _reachable:
			var d := (Vector2(c) - Vector2(goal)).length()
			if d < best_d:
				best_d = d
				best = c
		goal = best
	var queue: Array[Vector2i] = [goal]
	_dist_field[goal] = 0
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
			var nxt: Vector2i = cell + d
			if _dist_field.has(nxt) or not _reachable.has(nxt):
				continue
			_dist_field[nxt] = int(_dist_field[cell]) + 1
			queue.append(nxt)


## Pour le téléphone : angle de la flèche (0 = droit devant, + = à droite), distance et plafond.
func gps_info() -> Dictionary:
	if camera == null or current == null or not current.active or finished:
		return {}
	var cam_pos := camera.global_position
	var target := current.global_position
	var distance := Vector2(target.x - cam_pos.x, target.z - cam_pos.z).length()
	var cell := _cell_of(cam_pos)
	# Si le joueur est dans une case non cartographiée (seuil de porte), on cherche la plus proche.
	if not _dist_field.has(cell):
		var best_d := 99.0
		var found := cell
		for dx in range(-3, 4):
			for dy in range(-3, 4):
				var c := Vector2i(cell.x + dx, cell.y + dy)
				if _dist_field.has(c) and Vector2(dx, dy).length() < best_d:
					best_d = Vector2(dx, dy).length()
					found = c
		cell = found
	if _dist_field.has(cell) and int(_dist_field[cell]) > 3:
		distance = float(_dist_field[cell]) * CELL
		# On suit le gradient sur quelques cases pour lisser les virages.
		var walk := cell
		for i in 5:
			var best_n := walk
			var best_v := int(_dist_field[walk])
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
				var n: Vector2i = walk + d
				if _dist_field.has(n) and int(_dist_field[n]) < best_v:
					best_v = int(_dist_field[n])
					best_n = n
			if best_n == walk:
				break
			walk = best_n
		target = _cell_center(walk)
	var to := target - cam_pos
	to.y = 0.0
	if to.length() < 0.05:
		to = current.global_position - cam_pos
		to.y = 0.0
	var local := camera.global_transform.basis.inverse() * to
	return {
		"angle": atan2(local.x, -local.z),
		"distance": distance,
		"vertical": 1 if absf(current.normal.y) > 0.5 else 0,
	}
