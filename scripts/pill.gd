class_name Dose
extends Area3D
## La pilule (cœur du jeu — GDD §5.1). Spawne dans un conteneur aléatoire.
## Capsule émissive cyan : visible de loin, coût graphique nul.
##
## Mécanique : gâchette près de la pilule (ou en la visant) → elle passe dans cette main →
## la porter à la bouche (rayon 0,28 m sous la caméra) l'avale tout de suite (main.gd).

const PILL_COLOR := Color(0.35, 1.0, 0.85)
const AURA_LOOP_SECONDS := 12.0
const AURA_MIX_RATE := 22050
const AURA_VOLUME_DB := -9.0 # audible à travers l'appartement : on la suit à l'oreille
const AURA_MAX_DISTANCE_M := 14.0
const BEAM_HEIGHT := 2.6 ## faisceau de repérage : la pilule se voit de loin
const BEAM_GAP := 0.3 ## le faisceau commence 30 cm au-dessus de la gélule
const AURA_UNIT_SIZE_M := 2.5

const HALO_FADE_NEAR := 1.8 ## m : en dessous (debout au-dessus d'elle), le halo disparaît
const HALO_FADE_FAR := 3.5 ## m : au-delà, halo à pleine intensité

var _spin := true
var _beam: MeshInstance3D = null
var _glow: OmniLight3D = null
var _halo: MeshInstance3D = null
var _halo_mat: StandardMaterial3D = null
var _aura_audio: AudioStreamPlayer3D = null
var _aura_consumed := false
var is_held := false
var _eat_zone_radius := 0.28 ## m — rayon autour de la "bouche"
var camera: Node3D = null ## XRCamera3D (résolu par main.gd)

## Point de la bouche : légèrement en dessous et devant le centre de la caméra.
func _get_mouth_position() -> Vector3:
	if camera == null or not is_instance_valid(camera):
		return global_transform.origin
	var cam_origin: Vector3 = camera.global_transform.origin
	var cam_down: Vector3 = camera.global_transform.basis.y
	var cam_forward: Vector3 = camera.global_transform.basis.z
	# Bouche = ~15 cm en dessous du centre de la caméra + 5 cm vers l'avant
	return cam_origin - cam_down * 0.15 + cam_forward * 0.05


## Vrai si la pilule (tenue dans la main) est dans la zone de la bouche.
func can_eat() -> bool:
	if not is_held or camera == null:
		return false
	var mouth := _get_mouth_position()
	return global_transform.origin.distance_to(mouth) < _eat_zone_radius


func _ready() -> void:
	# Gélule lisible dans le casque : 11 cm, cyan lumineux avec une bague blanche au milieu.
	var body := MeshInstance3D.new()
	body.name = "Gelule"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.032
	capsule.height = 0.11
	body.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.85, 0.75)
	mat.emission_enabled = true
	mat.emission = PILL_COLOR
	mat.emission_energy_multiplier = 0.55 # assez pour briller, pas au point de virer au blanc
	mat.roughness = 0.35
	body.material_override = mat
	body.rotation.z = PI / 2.0 # couchée : vue d'en haut on voit toute sa longueur
	add_child(body)
	var ring := MeshInstance3D.new()
	ring.name = "Bague"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.031
	torus.outer_radius = 0.037
	ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.97, 0.97, 1.0)
	ring_mat.roughness = 0.3
	ring.material_override = ring_mat
	ring.rotation.z = PI / 2.0 # bague autour de l'axe de la gélule couchée
	add_child(ring)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.16
	shape.shape = sphere
	add_child(shape)

	_create_beam()
	body_offset_y = 0.05 # après la création de tous les maillages : gélule, bague et halo ensemble
	_create_aura()


## Colonne de lumière cyan et petite lueur : repère visuel intuitif en VR.
func _create_beam() -> void:
	_beam = MeshInstance3D.new()
	_beam.name = "Faisceau"
	# Le faisceau part au-dessus de la gélule (sinon sa base l'englobe et on ne voit qu'une
	# colonne blanche), fin et discret : il indique l'endroit, la gélule reste à voir.
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.035
	cyl.height = BEAM_HEIGHT - BEAM_GAP
	cyl.radial_segments = 8
	cyl.rings = 1
	_beam.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.25, 0.95, 0.85, 0.22)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam.material_override = mat
	_beam.position.y = BEAM_GAP + (BEAM_HEIGHT - BEAM_GAP) * 0.5
	add_child(_beam)
	var glow := OmniLight3D.new()
	glow.name = "Lueur"
	glow.light_color = PILL_COLOR
	glow.light_energy = 1.5
	glow.omni_range = 3.2
	glow.position.y = 0.15
	add_child(glow)
	_glow = glow
	# Halo : un anneau qui fait toujours face au joueur, visible de loin (le faisceau fin se
	# perd dans la résolution du casque). Centre transparent : la gélule reste visible
	# dedans, et il s'efface quand on s'approche (voir _process).
	var halo := MeshInstance3D.new()
	halo.name = "Halo"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	halo.mesh = quad
	var hmat := StandardMaterial3D.new()
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hmat.albedo_texture = _halo_texture()
	hmat.no_depth_test = false
	halo.material_override = hmat
	add_child(halo)
	_halo = halo
	_halo_mat = hmat


static var _halo_tex: ImageTexture = null


## Anneau lumineux (64 px) : creux au centre pour ne pas noyer la gélule, généré une fois.
static func _halo_texture() -> ImageTexture:
	if _halo_tex == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
				var a := clampf(1.0 - absf(d - 0.62) / 0.38, 0.0, 1.0)
				a = a * a * 0.85
				img.set_pixel(x, y, Color(0.35, 1.0, 0.9, a))
		_halo_tex = ImageTexture.create_from_image(img)
	return _halo_tex


## Reprend après un reparentage (notamment vers la main), une fois les enfants
## eux aussi réintégrés à l'arbre. À la première entrée, _ready() crée le son.
func _enter_tree() -> void:
	if is_instance_valid(_aura_audio) and not _aura_consumed:
		call_deferred(&"_resume_aura")


func _exit_tree() -> void:
	_stop_aura()


## Carillon divin très discret : nappe continue et deux cloches par boucle de 12 s.
## Le flux reste mono pour laisser le moteur spatialiser naturellement la source.
func _create_aura() -> void:
	_aura_audio = AudioStreamPlayer3D.new()
	_aura_audio.name = "CarillonDoux"
	_aura_audio.stream = _synthesize_aura()
	_aura_audio.volume_db = AURA_VOLUME_DB
	_aura_audio.max_db = -12.0 # Aucun renfort agressif quand on colle la pilule.
	_aura_audio.panning_strength = 1.0 # Spatialisation/HRTF natifs du Player3D.
	_aura_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_aura_audio.unit_size = AURA_UNIT_SIZE_M
	_aura_audio.max_distance = AURA_MAX_DISTANCE_M
	_aura_audio.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(_aura_audio)
	_aura_audio.play()


func _resume_aura() -> void:
	if _aura_consumed or not is_inside_tree():
		return
	if not is_instance_valid(_aura_audio) or not _aura_audio.is_inside_tree():
		return
	if not _aura_audio.playing:
		_aura_audio.play()


func _stop_aura() -> void:
	if is_instance_valid(_aura_audio):
		_aura_audio.stop()


## Génère un WAV 16 bits sans asset externe. Les fréquences de la nappe sont
## quantifiées sur un nombre entier de périodes : la boucle ne produit pas de clic.
func _synthesize_aura() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = AURA_MIX_RATE
	stream.stereo = false

	var frame_count := int(AURA_LOOP_SECONDS * AURA_MIX_RATE)
	var samples := PackedByteArray()
	samples.resize(frame_count * 2)
	var pad_frequencies := PackedFloat32Array([261.626, 391.995, 523.251, 659.255])
	var pad_amplitudes := PackedFloat32Array([0.025, 0.018, 0.014, 0.010])
	for note in pad_frequencies.size():
		pad_frequencies[note] = roundf(pad_frequencies[note] * AURA_LOOP_SECONDS) / AURA_LOOP_SECONDS

	for i in frame_count:
		var t := float(i) / float(AURA_MIX_RATE)
		var breathing := 0.88 + 0.12 * sin(TAU * t / AURA_LOOP_SECONDS)
		var sample := 0.0
		for note in pad_frequencies.size():
			var phase := TAU * pad_frequencies[note] * t + float(note) * 0.63
			sample += sin(phase) * pad_amplitudes[note] * breathing
		# Deux tintements doux, séparés par six secondes de respiration.
		sample += _aura_bell(t, 1046.502, 0.065)
		sample += _aura_bell(t - AURA_LOOP_SECONDS * 0.5, 1318.510, 0.050)
		var value := int(clampf(sample, -0.95, 0.95) * 32767.0)
		samples.encode_s16(i * 2, value)

	stream.data = samples
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frame_count
	return stream


## Attaque et relâchement adoucis ; harmoniques légères pour un timbre cristallin.
func _aura_bell(local_time: float, frequency: float, amplitude: float) -> float:
	if local_time < 0.0 or local_time >= 3.5:
		return 0.0
	var attack := smoothstep(0.0, 0.08, local_time)
	var release := 1.0 - smoothstep(2.6, 3.5, local_time)
	var envelope := attack * release * exp(-local_time * 1.35)
	var tone := sin(TAU * frequency * local_time)
	tone += 0.28 * sin(TAU * frequency * 2.0 * local_time)
	tone += 0.09 * sin(TAU * frequency * 3.0 * local_time)
	return tone * envelope * amplitude


var body_offset_y := 0.0:
	set(v):
		body_offset_y = v
		for c in get_children():
			if c is MeshInstance3D and c != _beam:
				c.position.y = v


func _process(delta: float) -> void:
	if is_held:
		# En main : ni faisceau, ni lueur, ni halo devant les yeux (main.gd tient la position).
		for n in [_beam, _glow, _halo]:
			if n != null and (n as Node3D).visible:
				(n as Node3D).visible = false
		return
	if not visible:
		return
	_fade_halo()
	if not _spin:
		return
	rotate_y(delta * 1.6)
	for c in get_children():
		if c is MeshInstance3D and c != _beam:
			c.position.y = body_offset_y + sin(Time.get_ticks_msec() / 1000.0 * 2.4) * 0.012


## Le halo sert à repérer la pilule de loin ; de près il s'efface pour laisser voir la gélule.
func _fade_halo() -> void:
	if _halo_mat == null:
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	var t := 1.0
	if cam != null:
		t = clampf((cam.global_position.distance_to(global_position) - HALO_FADE_NEAR) / (HALO_FADE_FAR - HALO_FADE_NEAR), 0.0, 1.0)
	_halo_mat.albedo_color = Color(1.0, 1.0, 1.0, t)
	_halo.visible = t > 0.01


func on_pointed() -> void:
	pass


func on_unpointed() -> void:
	pass


## Gâchette quand la pilule est dans la main :
# - Si pas encore dans la bouche → rien (le joueur doit la rapprocher).
# - Si dans la bouche → avaler.
## `_key` : signature commune aux interactables (main.gd passe la clé tenue).
func interact(_key: Node3D = null) -> void:
	if not visible:
		return
	if is_held:
		if can_eat():
			_consume()
		return
	# Pas encore tenue : on la ramasse (main.gd gère le reparent et coupe la rotation).
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method(&"pickup_pill"):
		main.pickup_pill(self)


## Saisie par une main : plus de rotation, plus de repères lumineux.
func on_picked(p_camera: Node3D) -> void:
	is_held = true
	_spin = false
	camera = p_camera
	rotation = Vector3.ZERO


## Appelé quand la pilule est avalée.
func _consume() -> void:
	_aura_consumed = true
	_stop_aura()
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method(&"on_dose_taken"):
		main.on_dose_taken()
	queue_free()
