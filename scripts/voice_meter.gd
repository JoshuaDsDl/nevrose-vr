class_name VoiceMeter
extends Node
## Mesure la voix du joueur au micro du casque pendant une prise.
##
## Aucune reconnaissance vocale : le jeu ne sait pas CE QUE tu dis, mais COMMENT tu
## le dis (temps de parole, volume, variations d'intonation, silences). Ces mesures
## partent au jury avec l'idée choisie. Le micro n'est jamais écouté en haut-parleur :
## le bus "Micro" est coupé en volume mais l'effet de capture reste alimenté.

const BUS_NAME := "Micro"
const CHUNK_SEC := 0.05
const MIN_THRESHOLD := 0.012 ## RMS minimal pour parler (hors bruit de fond)

var available := false ## le micro a réellement fourni des échantillons
var permission_denied := false
var level := 0.0 ## 0..1, niveau instantané lissé (pour les jauges)
var speaking := false

var _capture: AudioEffectCapture = null
var _player: AudioStreamPlayer = null
var _bus := -1
var _mix_rate := 44100.0
var _recording := false
var _clock := 0.0
var _chunk_sum := 0.0
var _chunk_n := 0
var _noise_samples: Array[float] = []
var _threshold := MIN_THRESHOLD
var _db_values: Array[float] = [] ## dB des tronçons où l'on parle
var _speak_chunks := 0
var _total_chunks := 0
var _silence_run := 0
var _longest_silence := 0
var _bursts := 0
var _last_speaking := false
var _peak := 0.0
var _frames_seen := 0


func _ready() -> void:
	set_process(false)


## Prépare le bus de capture et demande la permission micro (Android / Quest).
func start() -> void:
	if OS.get_name() == "Android":
		if not OS.get_granted_permissions().has("android.permission.RECORD_AUDIO"):
			OS.request_permission("RECORD_AUDIO")
			get_tree().on_request_permissions_result.connect(_on_permission_result, CONNECT_ONE_SHOT)
	_bus = AudioServer.get_bus_index(BUS_NAME)
	if _bus < 0:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, BUS_NAME)
		AudioServer.set_bus_volume_db(_bus, -80.0)
		AudioServer.add_bus_effect(_bus, AudioEffectCapture.new())
	for i in AudioServer.get_bus_effect_count(_bus):
		if AudioServer.get_bus_effect(_bus, i) is AudioEffectCapture:
			_capture = AudioServer.get_bus_effect(_bus, i)
	if _capture == null:
		return
	_mix_rate = AudioServer.get_mix_rate()
	_player = AudioStreamPlayer.new()
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = BUS_NAME
	add_child(_player)
	_player.play()
	set_process(true)


func _on_permission_result(permission: String, granted: bool) -> void:
	if permission.ends_with("RECORD_AUDIO") and not granted:
		permission_denied = true


func stop() -> void:
	set_process(false)
	if _player != null:
		_player.stop()
		_player.queue_free()
		_player = null


## Début d'une prise : les 0,6 premières secondes servent à mesurer le bruit de fond.
func begin_take() -> void:
	_recording = true
	_clock = 0.0
	_noise_samples.clear()
	_threshold = MIN_THRESHOLD
	_db_values.clear()
	_speak_chunks = 0
	_total_chunks = 0
	_silence_run = 0
	_longest_silence = 0
	_bursts = 0
	_last_speaking = false
	_peak = 0.0


func end_take() -> Dictionary:
	_recording = false
	return stats()


func _process(delta: float) -> void:
	if _capture == null:
		return
	var frames := _capture.get_frames_available()
	if frames <= 0:
		level = lerpf(level, 0.0, minf(delta * 8.0, 1.0))
		return
	var buf := _capture.get_buffer(frames)
	_frames_seen += frames
	if _frames_seen > _mix_rate * 0.25:
		available = true
	var per_chunk := int(_mix_rate * CHUNK_SEC)
	for s in buf:
		var m := (s.x + s.y) * 0.5
		_chunk_sum += m * m
		_chunk_n += 1
		if _chunk_n >= per_chunk:
			_on_chunk(sqrt(_chunk_sum / float(_chunk_n)))
			_chunk_sum = 0.0
			_chunk_n = 0


func _on_chunk(rms: float) -> void:
	level = lerpf(level, clampf(rms * 9.0, 0.0, 1.0), 0.5)
	speaking = rms > _threshold
	if not _recording:
		return
	_clock += CHUNK_SEC
	if _clock < 0.6:
		_noise_samples.append(rms)
		if _clock + CHUNK_SEC >= 0.6 and not _noise_samples.is_empty():
			var sorted := _noise_samples.duplicate()
			sorted.sort()
			_threshold = maxf(MIN_THRESHOLD, sorted[sorted.size() / 2] * 3.0)
		return
	_total_chunks += 1
	_peak = maxf(_peak, rms)
	if rms > _threshold:
		_speak_chunks += 1
		_db_values.append(20.0 * log(maxf(rms, 0.00001)) / log(10.0))
		_silence_run = 0
		if not _last_speaking:
			_bursts += 1
		_last_speaking = true
	else:
		_silence_run += 1
		_longest_silence = maxi(_longest_silence, _silence_run)
		_last_speaking = false


## Résumé de la prise. `mic` = false si rien n'a été capté (micro absent ou refusé).
func stats() -> Dictionary:
	var duration := maxf(_clock - 0.6, 0.0)
	var mean := 0.0
	for v in _db_values:
		mean += v
	mean = mean / _db_values.size() if not _db_values.is_empty() else -60.0
	var variance := 0.0
	for v in _db_values:
		variance += (v - mean) * (v - mean)
	variance = sqrt(variance / _db_values.size()) if _db_values.size() > 1 else 0.0
	return {
		"mic": available and not permission_denied,
		"duration": duration,
		"speak_ratio": float(_speak_chunks) / float(maxi(_total_chunks, 1)),
		"avg_db": mean,
		"peak_db": 20.0 * log(maxf(_peak, 0.00001)) / log(10.0),
		"variation": variance,
		"longest_pause": _longest_silence * CHUNK_SEC,
		"bursts": _bursts,
	}
