class_name Mimic
extends Area3D
## Mimic (GDD §5.3/§6). Round 1 : objet statique qui tremble.
## Round 3 : mode mobile — attiré par le bruit (verrou forcé), il dérive
## lentement vers le joueur. Pointé → se dissout (le doute coûte cher).

@export var tremble_strength := 0.012

# --- Round 3 : mobilité (attiré par le bruit) ---
var is_mobile := false
var move_speed := 0.35 ## m/s — lent, inquiétant
var attract_target: Node3D = null ## ex : xr_camera
var _base_rot := Vector3.ZERO
var _dissolving := false


func _ready() -> void:
	_base_rot = rotation
	# Round 3 : un mimic mobile spawné par le code n'a pas de mesh enfant
	# (contrairement au mimic tasse posé par apartment). On lui donne un
	# corps sombre flou pour qu'il soit "là" sans être identifiable.
	if is_mobile and not _has_mesh():
		_add_fallback_mesh()


func _has_mesh() -> bool:
	for c in get_children():
		if c is MeshInstance3D:
			return true
	return false


func _add_fallback_mesh() -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.12
	s.height = 0.4
	mi.mesh = s
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.06)
	mat.roughness = 1.0
	mat.metallic = 0.0
	mi.material_override = mat
	mi.position = Vector3(0, 0.2, 0)
	add_child(mi)
	# Zone d'interaction (raycast)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.3, 0.5, 0.3)
	cs.shape = bs
	cs.position = Vector3(0, 0.2, 0)
	add_child(cs)


func _process(delta: float) -> void:
	if _dissolving:
		return
	# Tremblement (static ou mobile).
	rotation = _base_rot + Vector3(
		sin(Time.get_ticks_msec() / 61.0) * tremble_strength,
		0.0,
		cos(Time.get_ticks_msec() / 47.0) * tremble_strength
	)
	# Round 3 : dérive vers la cible (le joueur) — lentement.
	# GDD §5.3 : les mimics mobiles bougent QUAND TU NE LES REGARDES PAS.
	if is_mobile and attract_target and is_instance_valid(attract_target):
		# Check "est-ce que le joueur me regarde ?"
		var cam_pos: Vector3 = attract_target.global_transform.origin
		var cam_fwd: Vector3 = -attract_target.global_transform.basis.z
		var to_me: Vector3 = global_transform.origin - cam_pos
		to_me.y = 0.0
		var looking_at_me: bool = cam_fwd.dot(to_me.normalized()) > 0.7 # ~45° de vision
		if not looking_at_me and to_me.length() > 0.7:
			position += -to_me.normalized() * (move_speed * delta)
		elif to_me.length() <= 0.7:
			# Arrivé trop près : la schizo monte un peu (présence oppressante)
			var main := get_tree().get_first_node_in_group("main")
			if main and main.has_method(&"on_mimic_close"):
				main.on_mimic_close()
			queue_free()


func on_pointed() -> void:
	pass


func on_unpointed() -> void:
	pass


func interact(_holding_key: Node3D = null) -> void:
	if _dissolving:
		return
	_dissolving = true
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method(&"on_mimic_purged"):
		main.on_mimic_purged()
	var tw := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw.tween_property(self, "scale", Vector3.ONE * 0.001, 0.4)
	tw.tween_callback(queue_free)
