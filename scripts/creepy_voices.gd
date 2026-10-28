extends Node
## Voix dans les murs (GDD §5.2/§7) : AudioStreamPlayer3D HRTF placées
## autour de la pièce. Déclenchées à fréquence croissante selon la schizo.
##
## 15 voix conspirationnistes (CIA, Linky, 5G, chemtrails, etc.) chargées
## depuis assets/voices/. Chaque emplacement spatial = un mur, le plafond
## ou le sol. Plus la schizo monte, plus elles sont fréquentes et proches.
##
## Godot 4 utilise HRTF par défaut pour AudioStreamPlayer3D → audio binaural
## natif sur casque VR (Quest 2, Vive Pro via SteamVR).

const VOICE_DIR := "res://assets/voices/"
const VOICE_COUNT := 15

## Emplacements spatiaux : murs (4), plafond (2), sol (2), coin (2).
## Valeurs par défaut = map 1 (studio 6x4.5). configure_room() les recale
## pour une autre map (ex. salon+cuisine 8x6).
var PLACEMENTS: Array[Vector3] = [
	Vector3(2.65, 1.4, 0.0),   ## mur est (mi-hauteur)
	Vector3(-2.65, 1.4, 0.0),  ## mur ouest
	Vector3(0.0, 1.4, 2.65),   ## mur sud
	Vector3(0.0, 1.4, -2.65),  ## mur nord
	Vector3(0.5, 2.6, 0.3),    ## plafond droit
	Vector3(-0.8, 2.6, -0.5),  ## plafond gauche
	Vector3(1.0, 0.05, 0.8),   ## sol avant-droit
	Vector3(-1.2, 0.05, -0.6), ## sol arrière-gauche
	Vector3(2.5, 0.5, 2.5),    ## coin SE bas
	Vector3(-2.5, 0.5, -2.5),  ## coin NO bas
	Vector3(0.0, 2.6, 0.0),    ## plafond centre
	Vector3(2.65, 2.2, 0.5),   ## mur est haut
	Vector3(-2.65, 2.2, -0.5), ## mur ouest haut
	Vector3(0.5, 0.05, 2.65),  ## sol mur sud
	Vector3(0.0, 1.2, -2.65),  ## mur nord (hauteur yeux)
]


## Recale les emplacements pour une pièce de `w` x `d` mètres, hauteur `h`.
## Appelé par main.gd après _build_world() avec les dims de la map courante.
func configure_room(w: float, d: float, h: float) -> void:
	PLACEMENTS = [
		Vector3(w / 2 - 0.35, 1.4, 0.0),
		Vector3(-w / 2 + 0.35, 1.4, 0.0),
		Vector3(0.0, 1.4, d / 2 - 0.35),
		Vector3(0.0, 1.4, -d / 2 + 0.35),
		Vector3(0.5, h - 0.1, 0.3),
		Vector3(-0.8, h - 0.1, -0.5),
		Vector3(1.0, 0.05, 0.8),
		Vector3(-1.2, 0.05, -0.6),
		Vector3(w / 2 - 0.5, 0.5, d / 2 - 0.5),
		Vector3(-w / 2 + 0.5, 0.5, -d / 2 + 0.5),
		Vector3(0.0, h - 0.1, 0.0),
		Vector3(w / 2 - 0.35, 2.2, 0.5),
		Vector3(-w / 2 + 0.35, 2.2, -0.5),
		Vector3(0.5, 0.05, d / 2 - 0.35),
		Vector3(0.0, 1.2, -d / 2 + 0.35),
	]

var _players: Array[AudioStreamPlayer3D] = []
var _streams: Array[AudioStream] = []
var _notif_player: AudioStreamPlayer = null
var _notif_stream: AudioStream = null
var _cooldown := 0.0
var _voice_idx := 0
var enabled := true

## Fréquence de base (s) entre deux voix — réduite quand la schizo monte.
const BASE_COOLDOWN := 12.0 ## ~12 s à sanity=0
const MIN_COOLDOWN := 3.0   ## ~3 s à sanity=100

## Volume max (dB) — ajusté pour petits haut-parleurs Quest 2 (-10.0 à -2.0 dB)
const MAX_VOLUME_DB := -2.0
const MIN_VOLUME_DB := -10.0


func _ready() -> void:
	_load_voices()
	_create_players()


func _load_voices() -> void:
	_streams.clear()
	for i in range(1, VOICE_COUNT + 1):
		var path := "%sv%02d.wav" % [VOICE_DIR, i]
		if ResourceLoader.exists(path):
			var s = load(path)
			if s is AudioStream:
				if s is AudioStreamWAV:
					(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
				_streams.append(s)
	print("[AUDIO] Voix : %d fichiers chargés" % _streams.size())
	_log("AUDIO", "Voix : %d fichiers chargés" % _streams.size())


func _create_players() -> void:
	for i in 6: ## 6 lecteurs HRTF réutilisés, jamais simultanés
		var p := AudioStreamPlayer3D.new()
		p.name = "WallVoice_%d" % i
		p.bus = "Master"
		p.max_distance = 8.0
		p.position = PLACEMENTS[i % PLACEMENTS.size()]
		add_child(p)
		_players.append(p)
	_create_notification_player()


func _create_notification_player() -> void:
	if _notif_player != null:
		return
	_notif_player = AudioStreamPlayer.new()
	_notif_player.name = "NotificationPlayer"
	_notif_player.bus = "Master"
	_notif_player.volume_db = -4.0
	_notif_stream = _synthesize_notification_sound()
	_notif_player.stream = _notif_stream
	add_child(_notif_player)


func _synthesize_notification_sound() -> AudioStreamWAV:
	# Synthèse d'un carillon Messenger clair à deux tons (880Hz -> 1174Hz)
	var sample_rate := 22050
	var duration := 0.25 # 250 ms
	var total_frames := int(sample_rate * duration)
	var half_frames := total_frames / 2
	var data := PackedByteArray()
	data.resize(total_frames * 2)

	for i in total_frames:
		var freq: float = 880.0 if i < half_frames else 1174.66
		var env: float = 1.0 - float(i % half_frames) / float(half_frames)
		var sample: float = sin(TAU * freq * (float(i) / float(sample_rate))) * env * 0.45
		var val: int = clampi(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, val)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = data
	return wav


## Appelé par main.gd à chaque frame (ou tick).
## `t` = sanity / 100.0 (0.0 à 1.0)
func tick(t: float, delta: float) -> void:
	if not enabled or _streams.is_empty():
		return
	# Pendant un clip, ignorer les déclenchements et geler le cooldown.
	# Le délai minimal ne commence donc qu'après la fin réelle de la voix.
	if _is_voice_playing():
		_cooldown = maxf(_cooldown, MIN_COOLDOWN)
		return
	# Le cooldown diminue quand la schizo monte
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	# Seuil : murmure possible dès 5% de schizo (au lieu de 20%)
	if t < 0.05:
		_cooldown = BASE_COOLDOWN * (1.0 - t)
		return
	# Jouer une voix
	_play_random_voice(t)
	# Nouveau cooldown (plus court = plus fou)
	var cooldown_range := lerpf(BASE_COOLDOWN, MIN_COOLDOWN, t)
	_cooldown = cooldown_range * randf_range(0.7, 1.3)


func _is_voice_playing() -> bool:
	for p in _players:
		if is_instance_valid(p) and p.playing:
			return true
	return false


func _play_random_voice(t: float) -> void:
	# L'intro et les voix aléatoires partagent le même verrou, sans file d'attente.
	if _is_voice_playing():
		return
	# Trouver un player libre
	var free_player: AudioStreamPlayer3D = null
	for p in _players:
		if not p.playing:
			free_player = p
			break
	if free_player == null:
		return

	# Choisir une voix aléatoire (pas la même deux fois de suite)
	var idx := randi_range(0, _streams.size() - 1)
	while idx == _voice_idx and _streams.size() > 1:
		idx = randi_range(0, _streams.size() - 1)
	_voice_idx = idx
	var stream: AudioStream = _streams[idx]
	if stream == null:
		return

	# Position spatiale aléatoire (varie pour la surprise)
	var pos_idx := randi_range(0, PLACEMENTS.size() - 1)
	free_player.position = PLACEMENTS[pos_idx]

	# Volume : plus la schizo monte, plus c'est fort (-10.0 à -2.0 dB)
	free_player.volume_db = lerpf(MIN_VOLUME_DB, MAX_VOLUME_DB, t)

	# Pitch : légèrement aléatoire (varie entre lectures)
	free_player.pitch_scale = randf_range(0.85, 1.15)

	free_player.stream = stream
	free_player.play()
	_log("VOIX", "voix #%d jouée à %s (sanity=%.0f)" % [idx + 1, str(PLACEMENTS[pos_idx]), t * 100.0])


## Joue un premier murmure discret dès le démarrage pour confirmer l'audio
func play_intro_whisper() -> void:
	if not enabled or _streams.is_empty() or _players.is_empty() or _is_voice_playing():
		return
	var p: AudioStreamPlayer3D = _players[0]
	p.stream = _streams[0]
	p.volume_db = MIN_VOLUME_DB
	p.position = PLACEMENTS[0]
	p.play()
	_log("AUDIO", "Murmure d'introduction joué")


## Joue un son de notification Messenger clair (téléphone / message reçu)
func play_notification() -> void:
	if not enabled:
		return
	if _notif_player == null and is_inside_tree():
		_create_notification_player()
	if _notif_player != null and _notif_player.is_inside_tree():
		_notif_player.play()
		_log("AUDIO", "Notification Messenger jouée")


func _log(cat: String, msg: String) -> void:
	var logger = get_node_or_null("/root/GameLog")
	if logger:
		logger.log_line(cat, msg)
	else:
		print("[%s] %s" % [cat, msg])
