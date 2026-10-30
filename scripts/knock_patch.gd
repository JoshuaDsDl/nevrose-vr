class_name KnockPatch
extends Node3D
## Plaque de plâtre sur un mur ou le plafond : c'est là que ça cogne.
##
## Active, elle répète « toc toc toc » et laisse de toutes petites traces
## (fissures, poussière, léger tremblement). Quatre coups la font céder.
## L'axe local +Z pointe toujours vers l'intérieur de la pièce.

signal broken(patch: KnockPatch)

const SIZE := 0.7
const HITS_TO_BREAK := 4
const KNOCK_PERIOD := 4.6 ## secondes entre deux séries de coups
const KNOCK_GAPS := [0.0, 0.38, 0.76]

var normal := Vector3.BACK ## normale monde, vers la pièce
var wall_color := Color(0.75, 0.7, 0.62)
var hits := 0
var active := false
var is_broken := false

var area: Area3D
var _plaster: MeshInstance3D
var _plaster_mat: StandardMaterial3D
var _cracks: Array[MeshInstance3D] = []
var _audio: AudioStreamPlayer3D
var _voice: AudioStreamPlayer3D
var voices_played := 0 ## voix sorties de ce mur (diagnostic / tests)
var _dust: CPUParticles3D
var _clock := 0.0
var _knock_index := 0
var _hover := false


func _ready() -> void:
	_build()


## Pose la plaque sur la surface : `pos` monde, `p_normal` vers la pièce.
func place(pos: Vector3, p_normal: Vector3) -> void:
	normal = p_normal.normalized()
	position = pos
	if absf(normal.y) > 0.9:
		rotation = Vector3(PI / 2.0 * -signf(normal.y), 0.0, 0.0)
	else:
		rotation = Vector3(0.0, atan2(normal.x, normal.z), 0.0)


func _build() -> void:
	_plaster = MeshInstance3D.new()
	_plaster.name = "Platre"
	var box := BoxMesh.new()
	box.size = Vector3(SIZE, SIZE, 0.03)
	_plaster.mesh = box
	_plaster_mat = StandardMaterial3D.new()
	_plaster_mat.albedo_color = wall_color.lerp(Color(0.85, 0.82, 0.76), 0.12)
	_plaster_mat.roughness = 0.95
	_plaster.material_override = _plaster_mat
	_plaster.position.z = 0.012
	add_child(_plaster)

	# Fissures : invisibles tant que la plaque dort, l'une apparaît à chaque coup.
	var crack_mat := StandardMaterial3D.new()
	crack_mat.albedo_color = Color(0.1, 0.08, 0.07)
	crack_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var crack_defs := [
		[Vector3(-0.05, 0.12, 0.0), 0.34, 18.0],
		[Vector3(0.1, -0.1, 0.0), 0.3, -32.0],
		[Vector3(-0.15, -0.18, 0.0), 0.26, 70.0],
		[Vector3(0.18, 0.2, 0.0), 0.22, -75.0],
		[Vector3(0.0, 0.0, 0.0), 0.4, 100.0],
	]
	for def in crack_defs:
		var c := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(def[1], 0.006, 0.004)
		c.mesh = cb
		c.material_override = crack_mat
		c.position = Vector3((def[0] as Vector3).x, (def[0] as Vector3).y, 0.03)
		c.rotation.z = deg_to_rad(def[2])
		c.visible = false
		add_child(c)
		_cracks.append(c)

	area = Area3D.new()
	area.name = "area"
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var bs := BoxShape3D.new()
	bs.size = Vector3(SIZE + 0.2, SIZE + 0.2, 0.5)
	cs.shape = bs
	cs.position.z = 0.2
	cs.disabled = true
	area.add_child(cs)
	add_child(area)

	_audio = AudioStreamPlayer3D.new()
	_audio.name = "Toc"
	_audio.stream = Sfx.knock()
	_audio.unit_size = 4.0
	_audio.max_distance = 40.0
	_audio.volume_db = 4.0
	_audio.position.z = -0.05
	add_child(_audio)

	# Voix qui sort du mur, au même endroit que les coups.
	_voice = AudioStreamPlayer3D.new()
	_voice.name = "Voix"
	_voice.unit_size = 5.0
	_voice.max_distance = 40.0
	_voice.volume_db = 4.0
	_voice.attenuation_filter_cutoff_hz = 7000.0 # étouffée par la distance, comme à travers une cloison
	_voice.position.z = -0.08
	add_child(_voice)

	_dust = CPUParticles3D.new()
	_dust.name = "Poussiere"
	_dust.one_shot = true
	_dust.emitting = false
	_dust.amount = 16
	_dust.lifetime = 1.1
	_dust.explosiveness = 0.9
	_dust.direction = Vector3(0, 0.2, 1)
	_dust.spread = 55.0
	_dust.initial_velocity_min = 0.1
	_dust.initial_velocity_max = 0.35
	_dust.gravity = Vector3(0, -0.35, 0)
	_dust.local_coords = false
	_dust.scale_amount_min = 0.6
	_dust.scale_amount_max = 1.2
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.025)
	var dust_mat := StandardMaterial3D.new()
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mat.albedo_color = Color(0.85, 0.82, 0.74, 0.7)
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = dust_mat
	_dust.mesh = quad
	_dust.position.z = 0.05
	add_child(_dust)


func activate() -> void:
	if is_broken:
		return
	active = true
	_clock = KNOCK_PERIOD - 0.6 ## premier toc presque tout de suite
	_knock_index = 0
	_set_area_enabled(true)
	if not _cracks.is_empty():
		_cracks[0].visible = true


## Une voix sort du mur (flux choisi par HuntMode). Sans effet une fois la plaque brisée.
func play_voice(stream: AudioStream) -> void:
	if is_broken or stream == null or _voice == null:
		return
	_voice.stream = stream
	_voice.play()
	voices_played += 1


func stop_voice() -> void:
	if _voice != null:
		_voice.stop()


func deactivate() -> void:
	active = false
	_set_area_enabled(false)


func _set_area_enabled(on: bool) -> void:
	var cs := area.get_node_or_null("Shape") as CollisionShape3D
	if cs != null:
		cs.set_deferred("disabled", not on)


func _process(delta: float) -> void:
	if not active:
		return
	_clock += delta
	if _clock >= KNOCK_PERIOD:
		_clock = 0.0
		_knock_index = 0
	if _knock_index < KNOCK_GAPS.size() and _clock >= KNOCK_GAPS[_knock_index]:
		_knock_index += 1
		_knock()


## Un « toc » : son dans le mur + petit nuage de poussière + tressaillement.
func _knock() -> void:
	_audio.play()
	_dust.restart()
	_dust.emitting = true
	var tw := create_tween()
	tw.tween_property(_plaster, "position:z", 0.02, 0.04)
	tw.tween_property(_plaster, "position:z", 0.012, 0.12)


# --- Interface du rayon (main.gd) ---
func on_pointed() -> void:
	_hover = true
	_plaster_mat.emission_enabled = true
	_plaster_mat.emission = Color(0.35, 0.3, 0.2)
	_plaster_mat.emission_energy_multiplier = 0.6


func on_unpointed() -> void:
	_hover = false
	_plaster_mat.emission_enabled = false


## Gâchette ou coup de poing.
func interact(_holding: Node3D = null) -> void:
	hit()


## Un coup ; une arme lourde compte pour plusieurs (`power`).
func hit(power: int = 1) -> void:
	if not active or is_broken:
		return
	hits += maxi(power, 1)
	var player := AudioStreamPlayer3D.new()
	player.stream = Sfx.hit()
	player.volume_db = 6.0
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
	_dust.amount = 28
	_dust.restart()
	_dust.emitting = true
	for i in mini(hits + 1, _cracks.size()):
		_cracks[i].visible = true
	var tw := create_tween()
	tw.tween_property(_plaster, "scale", Vector3(0.96, 0.96, 1.0), 0.05)
	tw.tween_property(_plaster, "scale", Vector3.ONE, 0.15)
	if hits >= HITS_TO_BREAK:
		_break_open()


## Défonce la plaque d'un coup (trou fait par le joueur, hors objectif de la chasse).
func break_now() -> void:
	if is_broken:
		return
	active = true
	hits = HITS_TO_BREAK
	_break_open()


func _break_open() -> void:
	is_broken = true
	active = false
	stop_voice()
	_set_area_enabled(false)
	var crash := AudioStreamPlayer3D.new()
	crash.stream = Sfx.crash()
	crash.volume_db = 8.0
	crash.unit_size = 6.0
	add_child(crash)
	crash.play()
	_plaster.queue_free()
	for c in _cracks:
		c.queue_free()
	_cracks.clear()
	_build_hole()
	_spawn_debris()
	_dust.amount = 60
	_dust.restart()
	_dust.emitting = true
	broken.emit(self)


## Trou noir irrégulier : quelques rectangles noirs qui se chevauchent.
func _build_hole() -> void:
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.0, 0.0, 0.0)
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 10:
		var m := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(rng.randf_range(0.14, 0.42), rng.randf_range(0.14, 0.42))
		m.mesh = qm
		m.material_override = black
		m.position = Vector3(rng.randf_range(-0.16, 0.16), rng.randf_range(-0.16, 0.16), 0.014 + i * 0.0005)
		m.rotation.z = rng.randf_range(0.0, PI)
		add_child(m)
	# Éclats de plâtre sur le pourtour.
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color(0.82, 0.78, 0.7)
	edge.roughness = 1.0
	for i in 9:
		var s := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(rng.randf_range(0.04, 0.1), rng.randf_range(0.02, 0.06), 0.03)
		s.mesh = sb
		s.material_override = edge
		var a := rng.randf() * TAU
		s.position = Vector3(cos(a) * 0.36, sin(a) * 0.36, 0.02)
		s.rotation.z = a + rng.randf_range(-0.5, 0.5)
		add_child(s)


## Gravats qui tombent au sol et y restent.
func _spawn_debris() -> void:
	var host := get_parent()
	if host == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.68, 0.6)
	mat.roughness = 1.0
	for i in 14:
		var piece := MeshInstance3D.new()
		var pm := BoxMesh.new()
		var sz := randf_range(0.03, 0.11)
		pm.size = Vector3(sz, sz * randf_range(0.4, 0.9), sz * randf_range(0.6, 1.2))
		piece.mesh = pm
		piece.material_override = mat
		host.add_child(piece)
		var start := global_position + normal * 0.1
		piece.global_position = start
		var floor_pos := Vector3(start.x, 0.03, start.z) + normal * randf_range(0.1, 0.6)
		floor_pos += Vector3(randf_range(-0.5, 0.5), 0.0, randf_range(-0.5, 0.5)) * (1.0 - absf(normal.y) * 0.0)
		piece.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var tw := piece.create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(piece, "global_position", floor_pos, randf_range(0.35, 0.7))
