class_name PropBody
extends RigidBody3D
## Un objet de l'appartement devenu physique dans le mode Chasse : on peut
## l'attraper, le lancer, le frapper, et le casser. Les gros meubles sont lourds,
## les petits objets volent. Les tableaux restent accrochés jusqu'au premier coup.

signal destroyed(prop: PropBody)

const LAYER := 8 ## couche « objets » : ni le sol ni les murs (couche 1), ni le joueur (couche 2)
const IMPACT_SPEED := 4.5 ## m/s : en dessous, un choc ne casse rien

var hp := 3.0
var size := Vector3.ONE ## emprise monde de l'objet
var tint := Color(0.72, 0.66, 0.6)
var hanging := false ## accroché au mur : fige jusqu'au premier coup
var is_dead := false
var breakable := true ## faux en mode Résistance : on peut jeter les objets, pas les casser

var _last_speed := 0.0
var _flash := 0.0
var _grace := 0.0 ## secondes sans casse après le réveil (les voisins qui chevauchent poussent fort au premier tour)


## Prépare la physique d'après l'emprise : masse proportionnelle au volume, PV à l'avenant.
func configure(p_size: Vector3, p_tint: Color, p_hanging: bool) -> void:
	size = p_size
	tint = p_tint
	hanging = p_hanging
	var volume := p_size.x * p_size.y * p_size.z
	mass = clampf(volume * 140.0, 0.3, 120.0)
	hp = clampf(1.0 + mass * 0.11, 1.0, 12.0)
	collision_layer = LAYER
	collision_mask = 1 | LAYER
	contact_monitor = true
	max_contacts_reported = 2
	linear_damp = 0.15
	angular_damp = 0.6
	var mat := PhysicsMaterial.new()
	mat.friction = 0.8
	mat.bounce = 0.12
	physics_material_override = mat
	var cs := CollisionShape3D.new()
	cs.name = "Forme"
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(p_size.x, 0.04), maxf(p_size.y, 0.04), maxf(p_size.z, 0.04))
	cs.shape = box
	add_child(cs)
	body_entered.connect(_on_body_entered)
	# Figé au départ : sans ça, les boîtes de collision qui chevauchent le sol ou les autres
	# meubles projetaient toute la pièce au démarrage. Il redevient physique au premier contact.
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC


func _physics_process(_delta: float) -> void:
	_grace = maxf(_grace - _delta, 0.0)
	_last_speed = linear_velocity.length()
	if _flash > 0.0:
		_flash = maxf(_flash - _delta, 0.0)


## Réveille l'objet (décroche un tableau, sort du sommeil).
func wake() -> void:
	if freeze:
		_grace = 0.6
	freeze = false
	hanging = false
	sleeping = false

func _on_body_entered(_other: Node) -> void:
	if is_dead or not breakable or _grace > 0.0:
		return
	var impact := _last_speed
	if impact > IMPACT_SPEED:
		# Un objet lourd lancé fait plus de dégâts ; les petits se brisent au moindre choc fort.
		damage((impact - IMPACT_SPEED + 1.0) * (0.6 + mass * 0.02))


## Dégâts d'un coup (poing, arme, choc). `impulse` pousse l'objet dans le sens du coup.
func damage(amount: float, at := Vector3.ZERO, impulse := Vector3.ZERO) -> void:
	if is_dead:
		return
	wake()
	if impulse != Vector3.ZERO:
		var arm := (at - global_position) if at != Vector3.ZERO else Vector3.ZERO
		apply_impulse(impulse, arm)
	if not breakable:
		return
	hp -= amount
	_flash = 0.15
	if hp <= 0.0:
		shatter()


## Casse l'objet : éclats qui tombent puis s'effacent, fracas, l'objet disparaît.
func shatter() -> void:
	if is_dead:
		return
	is_dead = true
	var host := get_parent()
	var origin := global_position
	var extent := size
	var color := tint
	if host != null:
		var crash := AudioStreamPlayer3D.new()
		crash.stream = Sfx.crash()
		crash.volume_db = clampf(-4.0 + mass * 0.08, -4.0, 6.0)
		crash.unit_size = 6.0
		host.add_child(crash)
		crash.global_position = origin
		crash.play()
		crash.finished.connect(crash.queue_free)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.9
		var count := clampi(int(4.0 + mass * 0.25), 5, 12)
		for i in count:
			var piece := MeshInstance3D.new()
			var pm := BoxMesh.new()
			var s := clampf(maxf(extent.x, extent.z) * randf_range(0.1, 0.28), 0.03, 0.2)
			pm.size = Vector3(s, s * randf_range(0.4, 0.9), s * randf_range(0.5, 1.1))
			piece.mesh = pm
			piece.material_override = mat
			host.add_child(piece)
			piece.global_position = origin + Vector3(randf_range(-0.5, 0.5) * extent.x, randf_range(0.0, 0.5) * extent.y, randf_range(-0.5, 0.5) * extent.z)
			piece.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
			var floor_pos := Vector3(piece.global_position.x + randf_range(-0.4, 0.4), 0.03, piece.global_position.z + randf_range(-0.4, 0.4))
			var tw := piece.create_tween()
			tw.tween_property(piece, "global_position", floor_pos, randf_range(0.3, 0.65)).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tw.tween_interval(6.0)
			tw.tween_property(piece, "scale", Vector3.ZERO, 1.0)
			tw.tween_callback(piece.queue_free)
	destroyed.emit(self)
	queue_free()
