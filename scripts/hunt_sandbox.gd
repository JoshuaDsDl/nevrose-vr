class_name HuntSandbox
extends Node3D
## Bac à sable du mode Chasse : tout l'appartement devient du matériel à casser.
##
## - Les meubles et objets deviennent des PropBody (physiques) : on les attrape avec la
##   gâchette de grip (rayon de 3 m ou au contact), on les lance, on les fracasse.
## - Les armes achetées à la boutique se tiennent dans la main droite ; sans arme, les poings.
## - Murs et plafonds se percent à coups répétés (même trou noir que les plaques qui cognent).
## Les murs et le sol restent des StaticBody3D : le joueur lui-même n'est pas un RigidBody.

signal swung(tip: Vector3, prev_tip: Vector3, velocity: Vector3, power: float, hand: Node3D)
signal prop_destroyed(total: int)
signal weapon_changed(name: String)

const PROP_LAYER := PropBody.LAYER
const GRAB_RANGE := 3.0
const GRAB_SPHERE := 0.28
const FIST_SWING := 2.0 ## m/s : un vrai geste, pas un frôlement
const FIST_REACH := 0.0
const SWING_COOLDOWN := 0.28
const HOLE_HITS := 3.0 ## « points de coup » cumulés sur un mur avant qu'il cède
const MAX_HOLES := 14
const MAX_THROW := 12.0

## Ce qui reste en place : plafonniers (lumières), tapis, porte d'entrée, voiture.
const SKIP_PREFIXES := ["Plafonnier", "Tapis", "Paillasson", "EntranceDoor", "Voiture", "rug"]

var apartment: MapBase = null
var camera: Node3D = null
var hands: Array[Node3D] = [] ## [gauche, droite]
var owned: Array = []
var props: Array[PropBody] = []
var destroyed_count := 0
var weapon_id := "" ## "" = poings
var weapon_node: Node3D = null
var held := {} ## id de la main -> {prop, offset, hand}

var _prev_tip := {}
var _prev_hand := {}
var _hand_vel := {}
var _cool := {}
var _wall_hits := {}
var _holes: Array[KnockPatch] = []
var _sfx_cool := 0.0


func setup(p_apartment: MapBase, p_camera: Node3D, p_hands: Array[Node3D], p_owned: Array) -> void:
	apartment = p_apartment
	camera = p_camera
	hands = p_hands
	owned = p_owned
	_build_limits()
	_convert_furniture()
	equip(best_weapon())


# ---------------------------------------------------------------------------
# Limites : sol et plafond invisibles pour que rien ne tombe dans le vide
# ---------------------------------------------------------------------------
func _build_limits() -> void:
	for spec in [["SolSandbox", -0.1], ["PlafondSandbox", 2.95]]:
		var body := StaticBody3D.new()
		body.name = spec[0]
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(60.0, 0.2, 60.0)
		cs.shape = box
		body.add_child(cs)
		add_child(body)
		body.global_position = Vector3(5.0, spec[1], 1.5)


# ---------------------------------------------------------------------------
# Meubles → objets physiques
# ---------------------------------------------------------------------------
func _convert_furniture() -> void:
	var shell := apartment.get_node_or_null("Shell")
	if shell == null:
		return
	var found: Array[Node3D] = []
	_collect_instances(shell, shell, found)
	for node in found:
		_make_prop(node)


func _collect_instances(node: Node, shell: Node, out: Array[Node3D]) -> void:
	for child in node.get_children():
		if child is Node3D and (child as Node3D).scene_file_path != "" and (child as Node3D).visible and not _skipped(String(child.name)):
			out.append(child as Node3D) # on ne descend pas : un meuble est un seul objet
		elif child is Node3D:
			_collect_instances(child, shell, out)


func _skipped(node_name: String) -> bool:
	for prefix in SKIP_PREFIXES:
		if node_name.begins_with(prefix):
			return true
	return false


func _make_prop(node: Node3D) -> void:
	var bounds := _world_bounds(node)
	if bounds.size == Vector3.ZERO:
		return
	var lowered := String(node.name).to_lower()
	var hanging := lowered.contains("framed") or lowered.contains("tableau") or lowered.contains("cadre") or lowered.contains("miroir")
	var body := PropBody.new()
	body.name = "Prop_%s" % node.name
	add_child(body)
	body.global_transform = Transform3D(Basis.IDENTITY, bounds.get_center())
	node.reparent(body, true)
	body.configure(bounds.size, _tint_of(node), hanging)
	body.destroyed.connect(_on_prop_destroyed)
	props.append(body)
	# La collision fixe de ce meuble (joueur) disparaît : il en emporte une avec lui quand on le déplace.
	for child in apartment.get_children():
		if child is StaticBody3D and String(child.name) == "PlayerCollision" \
				and (child as Node3D).global_position.distance_to(bounds.get_center()) < 0.03:
			child.queue_free()


func _on_prop_destroyed(prop: PropBody) -> void:
	destroyed_count += 1
	props.erase(prop)
	for id in held.keys():
		if held[id]["prop"] == prop:
			held.erase(id)
	prop_destroyed.emit(destroyed_count)


func _world_bounds(node: Node3D) -> AABB:
	var minimum := Vector3(1e9, 1e9, 1e9)
	var maximum := Vector3(-1e9, -1e9, -1e9)
	var found := false
	for mi in _meshes(node):
		var box := mi.mesh.get_aabb()
		var xf := mi.global_transform
		for x in [box.position.x, box.end.x]:
			for y in [box.position.y, box.end.y]:
				for z in [box.position.z, box.end.z]:
					var p: Vector3 = xf * Vector3(x, y, z)
					minimum = minimum.min(p)
					maximum = maximum.max(p)
					found = true
	return AABB(minimum, maximum - minimum) if found else AABB()


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out


func _tint_of(node: Node3D) -> Color:
	for mi in _meshes(node):
		var mat := mi.get_active_material(0)
		if mat is StandardMaterial3D:
			return (mat as StandardMaterial3D).albedo_color
	return Color(0.72, 0.66, 0.6)


# ---------------------------------------------------------------------------
# Armes
# ---------------------------------------------------------------------------
## Armes possédées, de la moins chère à la plus chère.
func owned_weapons() -> Array[String]:
	var ids: Array[String] = []
	for item in DecorCatalog.weapons():
		if String(item["id"]) in owned:
			ids.append(String(item["id"]))
	return ids


## La plus puissante des armes possédées, « » (poings) sinon.
func best_weapon() -> String:
	var best := ""
	var best_power := 0.0
	for id in owned_weapons():
		var power := float(DecorCatalog.get_item(id)["damage"])
		if power > best_power:
			best_power = power
			best = id
	return best


## Arme suivante : poings → armes possédées → poings…
func cycle_weapon() -> void:
	var ids: Array[String] = [""]
	ids.append_array(owned_weapons())
	var next := (ids.find(weapon_id) + 1) % ids.size()
	equip(ids[next])


func equip(id: String) -> void:
	if is_instance_valid(weapon_node):
		weapon_node.queue_free()
	weapon_node = null
	weapon_id = id
	if id != "" and hands.size() > 1 and is_instance_valid(hands[1]):
		weapon_node = WeaponModel.build(id)
		hands[1].add_child(weapon_node)
	weapon_changed.emit(weapon_name())


func weapon_name() -> String:
	return "Poings" if weapon_id == "" else String(DecorCatalog.get_item(weapon_id)["name"])


func _weapon_power() -> float:
	return 1.0 if weapon_id == "" else float(DecorCatalog.get_item(weapon_id)["damage"])


func _weapon_reach() -> float:
	return FIST_REACH if weapon_id == "" else float(DecorCatalog.get_item(weapon_id)["reach"])


func _weapon_swing() -> float:
	return FIST_SWING if weapon_id == "" else float(DecorCatalog.get_item(weapon_id)["swing"])


## Bout de l'arme (ou de la main) d'une manette.
func tip_of(hand: Node3D) -> Vector3:
	if hands.size() > 1 and hand == hands[1] and is_instance_valid(weapon_node):
		return weapon_node.global_transform * Vector3(0, 0, -_weapon_reach())
	return hand.global_position


# ---------------------------------------------------------------------------
# Attraper et lancer
# ---------------------------------------------------------------------------
func is_holding(hand: Node3D) -> bool:
	return held.has(hand.get_instance_id())


## Attrape l'objet touché ou visé au rayon (3 m). Faux s'il n'y a rien à attraper.
func grab(hand: Node3D) -> bool:
	if is_holding(hand):
		return false
	var space := get_world_3d().direct_space_state
	var best: PropBody = null
	var sphere := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = GRAB_SPHERE
	sphere.shape = shape
	sphere.transform = Transform3D(Basis.IDENTITY, hand.global_position)
	sphere.collision_mask = PROP_LAYER
	var best_d := 1e9
	for hit in space.intersect_shape(sphere, 8):
		var prop := hit["collider"] as PropBody
		if prop != null and not _is_held(prop):
			var d := prop.global_position.distance_to(hand.global_position)
			if d < best_d:
				best_d = d
				best = prop
	if best == null:
		var dir := -hand.global_transform.basis.z
		var query := PhysicsRayQueryParameters3D.create(hand.global_position, hand.global_position + dir * GRAB_RANGE)
		query.collision_mask = PROP_LAYER
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and hit["collider"] is PropBody and not _is_held(hit["collider"]):
			best = hit["collider"]
	if best == null:
		return false
	best.wake()
	best.gravity_scale = 0.0
	held[hand.get_instance_id()] = {
		"prop": best,
		"offset": hand.global_transform.affine_inverse() * best.global_transform,
		"hand": hand,
	}
	_pulse(hand, 0.35)
	return true


func release(hand: Node3D) -> void:
	var id := hand.get_instance_id()
	if not held.has(id):
		return
	var prop: PropBody = held[id]["prop"]
	held.erase(id)
	if is_instance_valid(prop):
		prop.gravity_scale = 1.0
		prop.wake()
		# On garde l'élan de la main : c'est ce qui fait voler l'objet quand on le lance.
		var throw: Vector3 = _hand_vel.get(id, Vector3.ZERO) * 1.15
		prop.linear_velocity = throw.limit_length(MAX_THROW)


func release_all() -> void:
	for id in held.keys():
		var hand: Node3D = held[id]["hand"]
		if is_instance_valid(hand):
			release(hand)
	held.clear()


func _is_held(prop: PropBody) -> bool:
	for id in held:
		if held[id]["prop"] == prop:
			return true
	return false


func _hold_step(delta: float) -> void:
	for id in held.keys():
		var entry: Dictionary = held[id]
		var prop: PropBody = entry["prop"]
		var hand: Node3D = entry["hand"]
		if not is_instance_valid(prop) or not is_instance_valid(hand):
			held.erase(id)
			continue
		var target: Transform3D = hand.global_transform * (entry["offset"] as Transform3D)
		# Les objets lourds suivent plus lentement la main : un frigo ne se brandit pas comme un verre.
		var vmax := 14.0 / (1.0 + prop.mass / 14.0)
		prop.linear_velocity = ((target.origin - prop.global_position) * 18.0).limit_length(vmax)
		var error := target.basis * prop.global_transform.basis.inverse()
		var q := error.get_rotation_quaternion()
		var angle := q.get_angle()
		if angle > PI:
			angle -= TAU
		prop.angular_velocity = (q.get_axis() * angle * 12.0).limit_length(vmax * 1.5)
		prop.sleeping = false


# ---------------------------------------------------------------------------
# Frapper : objets et murs
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if apartment == null or delta <= 0.0:
		return
	_sfx_cool = maxf(_sfx_cool - delta, 0.0)
	for hand in hands:
		if not is_instance_valid(hand):
			continue
		var id := hand.get_instance_id()
		var pos := hand.global_position
		if _prev_hand.has(id):
			var v := (pos - (_prev_hand[id] as Vector3)) / delta
			_hand_vel[id] = (_hand_vel.get(id, Vector3.ZERO) as Vector3).lerp(v, 0.4)
		_prev_hand[id] = pos
	_hold_step(delta)
	_poll_swings(delta)


func _poll_swings(delta: float) -> void:
	for hand in hands:
		if not is_instance_valid(hand):
			continue
		var id := hand.get_instance_id()
		var tip := tip_of(hand)
		var prev: Vector3 = _prev_tip.get(id, tip)
		_prev_tip[id] = tip
		_cool[id] = maxf(float(_cool.get(id, 0.0)) - delta, 0.0)
		if is_holding(hand):
			continue
		var velocity := (tip - prev) / delta
		var is_weapon_hand := hands.size() > 1 and hand == hands[1]
		var threshold := _weapon_swing() if is_weapon_hand else FIST_SWING
		var power := _weapon_power() if is_weapon_hand else 1.0
		if velocity.length() > threshold and float(_cool[id]) <= 0.0:
			_cool[id] = SWING_COOLDOWN
			swung.emit(tip, prev, velocity, power, hand)
			_resolve_swing(hand, tip, prev, velocity, power)


## Un coup : dégâts sur les objets au bout de l'arme, puis sur le mur touché.
func _resolve_swing(hand: Node3D, tip: Vector3, prev: Vector3, velocity: Vector3, power: float) -> void:
	var space := get_world_3d().direct_space_state
	var dir := velocity.normalized()
	var speed := velocity.length()
	var hit_something := false
	var sphere := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.17
	sphere.shape = shape
	sphere.collision_mask = PROP_LAYER
	sphere.transform = Transform3D(Basis.IDENTITY, tip.lerp(prev, 0.25))
	var seen := {}
	for hit in space.intersect_shape(sphere, 8):
		var prop := hit["collider"] as PropBody
		if prop == null or seen.has(prop) or _is_held(prop):
			continue
		seen[prop] = true
		var push := dir * minf(speed, 9.0) * clampf(prop.mass, 0.3, 8.0) * 0.9
		prop.damage(power * clampf(speed / 3.0, 0.7, 2.0), tip, push)
		hit_something = true
	if hit_something:
		_sound(tip, 4.0)
		_pulse(hand, 0.7)
		return
	var query := PhysicsRayQueryParameters3D.create(prev, tip + dir * 0.1)
	query.collision_mask = 1
	query.collide_with_areas = false
	var wall := space.intersect_ray(query)
	if not wall.is_empty():
		_wall_hit(wall["position"], wall["normal"], power)
		_pulse(hand, 0.6)


func _wall_hit(pos: Vector3, normal: Vector3, power: float) -> void:
	if normal.y > 0.6:
		return # le sol ne se perce pas
	_sound(pos, 2.0)
	var key := Vector3i((pos / 0.7).round())
	var total: float = float(_wall_hits.get(key, 0.0)) + power
	_wall_hits[key] = total
	if total >= HOLE_HITS:
		_wall_hits.erase(key)
		_make_hole(pos, normal)


func _make_hole(pos: Vector3, normal: Vector3) -> void:
	if _holes.size() >= MAX_HOLES:
		var oldest: KnockPatch = _holes.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var patch := KnockPatch.new()
	patch.name = "Trou_%d" % _holes.size()
	add_child(patch)
	patch.place(pos + normal * 0.004, normal)
	patch.break_now()
	_holes.append(patch)


func _sound(pos: Vector3, volume_db: float) -> void:
	if _sfx_cool > 0.0:
		return
	_sfx_cool = 0.08
	var p := AudioStreamPlayer3D.new()
	p.stream = Sfx.hit()
	p.volume_db = volume_db
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


func _pulse(hand: Node3D, amplitude: float) -> void:
	var main := get_tree().get_first_node_in_group("main")
	if main != null and main.has_method(&"pulse_haptics") and hand is XRController3D:
		main.pulse_haptics(amplitude, 0.1, hand)
