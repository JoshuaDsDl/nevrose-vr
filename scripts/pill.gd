class_name Dose
extends Area3D
## La pilule (cœur du jeu — GDD §5.1). Spawne dans un conteneur aléatoire.
## Capsule émissive cyan : visible de loin, coût graphique nul.
##
## Mécanique (2026-10) : GRAB à la main → PORTER À LA BOUCHE → MANGER.
## La pilule suit la main droite une fois saisie. Quand la main entre dans
## la zone "bouche" (rayon 0.25 m du point bas de la caméra), un indicateur
## s'allume et la gâchette = avaler.

const PILL_COLOR := Color(0.35, 1.0, 0.85)
const AURA_LOOP_SECONDS := 12.0
const AURA_MIX_RATE := 22050
const AURA_VOLUME_DB := -18.0
const AURA_MAX_DISTANCE_M := 5.0
const AURA_UNIT_SIZE_M := 1.5

var _spin := true
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
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.028
	capsule.height = 0.08
	body.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PILL_COLOR
	mat.emission_enabled = true
	mat.emission = PILL_COLOR
	mat.emission_energy_multiplier = 2.2
	mat.roughness = 0.35
	body.material_override = mat
	add_child(body)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.09
	shape.shape = sphere
	add_child(shape)

	body_offset_y = 0.05
	_create_aura()


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
			if c is MeshInstance3D:
				c.position.y = v


func _process(delta: float) -> void:
	if is_held:
		# Suivre la main — position offset fix par main.gd
		return
	if not _spin or not visible:
		return
	rotate_y(delta * 1.6)
	for c in get_children():
		if c is MeshInstance3D:
			c.position.y = body_offset_y + sin(Time.get_ticks_msec() / 1000.0 * 2.4) * 0.012


func on_pointed() -> void:
	pass


func on_unpointed() -> void:
	pass


## Gâchette quand la pilule est dans la main :
# - Si pas encore dans la bouche → rien (le joueur doit la rapprocher).
# - Si dans la bouche → avaler.
func interact() -> void:
	if not visible:
		return
	if is_held:
		if can_eat():
			_consume()
		return
	# Pas encore tenue : on la ramasse (main.gd gère le reparent)
	_spin = false
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method(&"pickup_pill"):
		main.pickup_pill(self)


## Appelé quand la pilule est avalée.
func _consume() -> void:
	_aura_consumed = true
	_stop_aura()
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method(&"on_dose_taken"):
		main.on_dose_taken()
	queue_free()
