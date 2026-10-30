class_name HuntSandbox
extends Node3D
## Bac à sable des objets de l'appartement.
##
## Mode Chasse (complet) : tout l'appartement devient du matériel à casser.
## - Meubles et objets deviennent des PropBody physiques : grip = attraper (rayon de 3 m ou au
##   contact), relâcher = lancer. On les frappe, on les fracasse.
## - Armes de la boutique (mode Chasse uniquement) : couteau, pistolet, revolver, fusil à pompe,
##   fusil d'assaut, grenade. Sans arme, les poings.
## - Murs et plafonds se percent à coups répétés (même trou noir que les plaques qui cognent).
## Mode Résistance (`light`) : seuls les petits objets libres (canettes, assiettes…) sont physiques,
## on peut les attraper et les jeter ; rien ne se casse et il n'y a pas d'arme.
## Le joueur reste un CharacterBody : pas de RigidBody pour lui.

signal swung(tip: Vector3, prev_tip: Vector3, velocity: Vector3, power: float, hand: Node3D)
signal shot(origin: Vector3, end: Vector3, power: float)
signal prop_destroyed(total: int)
signal weapon_changed(name: String)

const PROP_LAYER := PropBody.LAYER
const GRAB_RANGE := 3.0
const GRAB_SPHERE := 0.28
const FIST_SWING := 2.0 ## m/s : un vrai geste, pas un frôlement
const SWING_COOLDOWN := 0.28
const HOLE_HITS := 3.0 ## « points de coup » cumulés sur un mur avant qu'il cède
const MAX_HOLES := 14
const MAX_DECALS := 40
const MAX_THROW := 12.0
const LIGHT_MAX_MASS := 8.0

## Ce qui reste en place : plafonniers (lumières), tapis, porte d'entrée, voiture.
const SKIP_PREFIXES := ["Plafonnier", "Tapis", "Paillasson", "EntranceDoor", "Voiture", "rug"]

var apartment: MapBase = null
var camera: Node3D = null
var hands: Array[Node3D] = [] ## [gauche, droite]
var owned: Array = []
var light := false
var props: Array[PropBody] = []
var destroyed_count := 0
var weapon_id := "" ## "" = poings
var weapon_node: Node3D = null
var held := {} ## id de la main -> {prop, offset, hand}
var shots_fired := 0
var grenades_thrown := 0

var _prev_tip := {}
var _prev_hand := {}
var _hand_vel := {}
var _cool := {}
var _wall_hits := {}
var _holes: Array[KnockPatch] = []
var _decals: Array[Node3D] = []
var _sfx_cool := 0.0
var _fire_cd := 0.0
var _grenade_cd := 0.0
var _decal_mesh: QuadMesh = null
var _decal_mat: StandardMaterial3D = null


## L'arme est un enfant de la manette : elle ne doit pas rester en main quand la partie se termine.
func _exit_tree() -> void:
	if is_instance_valid(weapon_node):
		weapon_node.queue_free()
	weapon_node = null


func setup(p_apartment: MapBase, p_camera: Node3D, p_hands: Array[Node3D], p_owned: Array, p_light := false) -> void:
	apartment = p_apartment
	camera = p_camera
	hands = p_hands
	owned = p_owned
	light = p_light
	_build_limits()
	_convert_furniture()
	equip("" if light else best_weapon())


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
	# La collision fixe de ce meuble (joueur) : le meuble l'emporte avec lui quand on le déplace.
	var fixed_body: Node = null
	for child in apartment.get_children():
		if child is StaticBody3D and String(child.name) == "PlayerCollision" \
				and (child as Node3D).global_position.distance_to(bounds.get_center()) < 0.03:
			fixed_body = child
			break
	if light and (fixed_body != null or hanging or bounds.size.x * bounds.size.y * bounds.size.z * 140.0 > LIGHT_MAX_MASS):
		return # mode Résistance : meubles et décors restent en place, seuls les petits objets bougent
	var body := PropBody.new()
	body.name = "Prop_%s" % node.name
	add_child(body)
	body.global_transform = Transform3D(Basis.IDENTITY, bounds.get_center())
	node.reparent(body, true)
	body.configure(bounds.size, _tint_of(node), hanging)
	body.breakable = not light
	body.destroyed.connect(_on_prop_destroyed)
	props.append(body)
	if fixed_body != null:
		fixed_body.queue_free()


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
# Armes (mode Chasse seulement)
# ---------------------------------------------------------------------------
## Armes possédées, de la moins chère à la plus chère.
func owned_weapons() -> Array[String]:
	var ids: Array[String] = []
	for item in DecorCatalog.weapons():
		if String(item["id"]) in owned:
			ids.append(String(item["id"]))
	return ids


## L'arme la plus chère possédée, « » (poings) sinon.
func best_weapon() -> String:
	var ids := owned_weapons()
	return ids[ids.size() - 1] if not ids.is_empty() else ""


## Arme suivante : poings → armes possédées → poings…
func cycle_weapon() -> void:
	if light:
		return
	var ids: Array[String] = [""]
	ids.append_array(owned_weapons())
	var next := (ids.find(weapon_id) + 1) % ids.size()
	equip(ids[next])


func equip(id: String) -> void:
	if is_instance_valid(weapon_node):
		weapon_node.queue_free()
	weapon_node = null
	weapon_id = id if not light else ""
	if weapon_id != "" and hands.size() > 1 and is_instance_valid(hands[1]):
		weapon_node = WeaponModel.build(weapon_id)
		hands[1].add_child(weapon_node)
	weapon_changed.emit(weapon_name())


func weapon_name() -> String:
	return "Poings" if weapon_id == "" else String(DecorCatalog.get_item(weapon_id)["name"])


func _cfg() -> Dictionary:
	return {} if weapon_id == "" else DecorCatalog.get_item(weapon_id)


func weapon_type() -> String:
	var cfg := _cfg()
	return String(cfg.get("type", "fists"))


## Vrai si la gâchette droite tire (arme à feu) ou lance (grenade) au lieu d'agir sur le décor.
func uses_trigger() -> bool:
	var t := weapon_type()
	return t == "gun" or t == "grenade"


func _weapon_power() -> float:
	return float(_cfg().get("damage", 1.0))


func _weapon_reach() -> float:
	if is_instance_valid(weapon_node) and weapon_node.has_meta("reach"):
		return float(weapon_node.get_meta("reach"))
	return 0.0


func _weapon_swing() -> float:
	return float(_cfg().get("swing", FIST_SWING))


## Bout de l'arme (ou de la main) d'une manette.
func tip_of(hand: Node3D) -> Vector3:
	if hands.size() > 1 and hand == hands[1] and is_instance_valid(weapon_node) and weapon_type() == "melee":
		return weapon_node.global_transform * Vector3(0, 0, -_weapon_reach())
	return hand.global_position


# ---------------------------------------------------------------------------
# Armes à feu et grenades
# ---------------------------------------------------------------------------
func _trigger_down() -> bool:
	return hands.size() > 1 and hands[1] is XRController3D and (hands[1] as XRController3D).get_float(&"trigger") > 0.6


## Gâchette pressée (appelée par Main) : tir ou jet de grenade. `hand` = main, ou la caméra au bureau.
func trigger_pressed(hand: Node3D) -> void:
	match weapon_type():
		"gun":
			fire(hand)
		"grenade":
			throw_grenade(hand)


## Un tir (ou une salve de plombs) si la cadence le permet. Retourne vrai si le coup est parti.
func fire(hand: Node3D) -> bool:
	if weapon_type() != "gun" or _fire_cd > 0.0:
		return false
	var cfg := _cfg()
	_fire_cd = float(cfg["rate"])
	var aim: Transform3D
	var muzzle: Vector3
	if hands.size() > 1 and hand == hands[1] and is_instance_valid(weapon_node):
		aim = weapon_node.global_transform
		muzzle = aim * Vector3(0, 0.02, -_weapon_reach())
	else: # bureau : on tire depuis la caméra
		aim = hand.global_transform
		muzzle = hand.global_position + (-aim.basis.z) * 0.45
	var dir := -aim.basis.z
	var right := dir.cross(Vector3.UP).normalized()
	var up := right.cross(dir).normalized()
	var spread := tan(deg_to_rad(float(cfg["spread"])))
	for i in int(cfg["pellets"]):
		var d := (dir + (right * randf_range(-1.0, 1.0) + up * randf_range(-1.0, 1.0)) * spread).normalized() if i > 0 or spread > 0.01 else dir
		_shoot(muzzle, d, float(cfg["damage"]))
	shots_fired += 1
	_muzzle_flash(muzzle, String(cfg["sound"]))
	_recoil(String(cfg["sound"]))
	if hand is XRController3D:
		_pulse(hand, 0.9 if String(cfg["sound"]) in ["revolver", "pompe"] else 0.55)
	return true


## Un projectile : le premier objet ou mur touché encaisse ; la plaque qui cogne est prévenue.
func _shoot(origin: Vector3, dir: Vector3, damage: float) -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 40.0)
	query.collision_mask = 1 | PROP_LAYER
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	var end: Vector3 = hit["position"] if not hit.is_empty() else origin + dir * 40.0
	shot.emit(origin, end, damage)
	_tracer(origin, end)
	if hit.is_empty():
		return
	var collider: Object = hit["collider"]
	if collider is PropBody:
		(collider as PropBody).damage(damage, end, dir * damage * clampf((collider as PropBody).mass, 0.3, 8.0) * 0.8)
		_sound(end, 0.0)
	else:
		_wall_hit(end, hit["normal"], damage * 0.35)
		_bullet_hole(end, hit["normal"])


func _tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.2:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.006, 0.006, length)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.5, 0.8)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = mat
	add_child(mi)
	mi.global_position = (from + to) * 0.5
	mi.look_at(to, Vector3.UP)
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.07)
	tw.tween_callback(mi.queue_free)


func _muzzle_flash(pos: Vector3, kind: String) -> void:
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.8, 0.45)
	flash.light_energy = 5.0 if kind != "pistolet" else 3.5
	flash.omni_range = 5.0
	add_child(flash)
	flash.global_position = pos
	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.07)
	tw.tween_callback(flash.queue_free)
	var p := AudioStreamPlayer3D.new()
	p.stream = Sfx.shot(kind)
	p.volume_db = 6.0
	p.unit_size = 10.0
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


## Recul : l'arme se cabre puis revient.
func _recoil(kind: String) -> void:
	if not is_instance_valid(weapon_node):
		return
	var kick := 12.0 if kind in ["revolver", "pompe"] else 6.0
	var tw := weapon_node.create_tween()
	tw.tween_property(weapon_node, "rotation_degrees:x", kick, 0.04)
	tw.parallel().tween_property(weapon_node, "position:z", 0.05, 0.04)
	tw.tween_property(weapon_node, "rotation_degrees:x", 0.0, 0.14)
	tw.parallel().tween_property(weapon_node, "position:z", 0.0, 0.14)


## Impact de balle : petite tache sombre collée au mur.
func _bullet_hole(pos: Vector3, normal: Vector3) -> void:
	if _decal_mesh == null:
		_decal_mesh = QuadMesh.new()
		_decal_mesh.size = Vector2(0.06, 0.06)
		_decal_mat = StandardMaterial3D.new()
		_decal_mat.albedo_color = Color(0.03, 0.03, 0.03)
		_decal_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if _decals.size() >= MAX_DECALS:
		var old: Node3D = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var mi := MeshInstance3D.new()
	mi.mesh = _decal_mesh
	mi.material_override = _decal_mat
	add_child(mi)
	mi.global_position = pos + normal * 0.006
	mi.look_at(pos + normal, Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT)
	_decals.append(mi)


func throw_grenade(hand: Node3D) -> bool:
	if weapon_type() != "grenade" or _grenade_cd > 0.0:
		return false
	_grenade_cd = 1.3
	var aim := hand.global_transform
	var origin := aim.origin + (-aim.basis.z) * 0.15
	var velocity: Vector3 = (_hand_vel.get(hand.get_instance_id(), Vector3.ZERO) as Vector3) * 1.4 + (-aim.basis.z) * 3.0
	var grenade := Grenade.new()
	grenade.name = "Grenade"
	add_child(grenade)
	grenade.global_position = origin
	grenade.launch(velocity.limit_length(MAX_THROW), self, float(_cfg()["radius"]), float(_cfg()["damage"]))
	grenades_thrown += 1
	if is_instance_valid(weapon_node): # la main est vide un instant, puis une nouvelle grenade apparaît
		weapon_node.visible = false
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			if is_instance_valid(weapon_node):
				weapon_node.visible = true)
	if hand is XRController3D:
		_pulse(hand, 0.5)
	return true


## Explosion : dégâts et souffle sur les objets, trous dans les murs et le plafond alentour.
func explode(pos: Vector3, radius: float, damage: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = Sfx.boom()
	p.volume_db = 8.0
	p.unit_size = 12.0
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.65, 0.25)
	flash.light_energy = 9.0
	flash.omni_range = 9.0
	add_child(flash)
	flash.global_position = pos
	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.4)
	tw.tween_callback(flash.queue_free)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	ball.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.2, 0.8)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ball.material_override = mat
	add_child(ball)
	ball.global_position = pos
	var tb := ball.create_tween().set_parallel(true)
	tb.tween_property(ball, "scale", Vector3.ONE * radius * 1.2, 0.3)
	tb.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tb.chain().tween_callback(ball.queue_free)
	for any_prop in props.duplicate():
		var prop := any_prop as PropBody
		if prop == null or not is_instance_valid(prop):
			continue
		var offset := prop.global_position - pos
		var d := offset.length()
		if d < radius:
			var falloff := 1.0 - d / radius
			prop.damage(damage * falloff + 1.0, pos, offset.normalized() * clampf(prop.mass, 0.3, 10.0) * 14.0 * falloff)
	var holes := 0
	var space := get_world_3d().direct_space_state
	for dir in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3.UP, Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]:
		if holes >= 4:
			break
		var query := PhysicsRayQueryParameters3D.create(pos, pos + (dir as Vector3).normalized() * (radius * 0.75))
		query.collision_mask = 1
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and (hit["normal"] as Vector3).y < 0.6:
			_wall_hit(hit["position"], hit["normal"], HOLE_HITS)
			holes += 1
	for h in hands:
		if is_instance_valid(h):
			_pulse(h, 1.0)


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
	_fire_cd = maxf(_fire_cd - delta, 0.0)
	_grenade_cd = maxf(_grenade_cd - delta, 0.0)
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
	if light:
		return
	# Arme automatique : gâchette maintenue = rafale.
	if weapon_type() == "gun" and bool(_cfg().get("auto", false)) and _trigger_down():
		fire(hands[1])
	_poll_swings(delta)


func _poll_swings(delta: float) -> void:
	for hand in hands:
		if not is_instance_valid(hand):
			continue
		var id := hand.get_instance_id()
		var is_weapon_hand := hands.size() > 1 and hand == hands[1]
		var tip := tip_of(hand)
		var prev: Vector3 = _prev_tip.get(id, tip)
		_prev_tip[id] = tip
		_cool[id] = maxf(float(_cool.get(id, 0.0)) - delta, 0.0)
		if is_holding(hand):
			continue
		# Un pistolet ou une grenade ne servent pas de massue : seules les mains nues et le couteau frappent.
		if is_weapon_hand and uses_trigger():
			continue
		var velocity := (tip - prev) / delta
		var threshold := _weapon_swing() if is_weapon_hand else FIST_SWING
		var power := _weapon_power() if (is_weapon_hand and weapon_type() == "melee") else 1.0
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
