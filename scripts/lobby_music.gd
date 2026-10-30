class_name LobbyMusic
extends Node
## Musique d'ambiance du lobby : boucle en continu, à faible volume.
## Le lecteur vit dans Main (et non dans le lobby, recréé à chaque retour) : quand on part
## en partie la musique s'arrête à sa position, et reprend exactement là au retour.
## Piste : assets/music/lobby.ogg si elle existe ; sinon une nappe synthétique de secours.

const TRACK_PATH := "res://assets/music/lobby.ogg"
const VOLUME_DB := -20.0 ## faible : c'est l'ambiance, pas le premier plan
const RATE := 11025
const FALLBACK_SEC := 16.0 ## durée de la nappe de secours

var _player: AudioStreamPlayer = null
var _resume_at := 0.0 ## position mémorisée au moment où l'on quitte le lobby


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "Player"
	_player.volume_db = VOLUME_DB
	_player.stream = _load_track()
	add_child(_player)


## Reprend là où la musique s'était arrêtée (ou démarre au premier lancement).
func resume() -> void:
	if _player == null or _player.playing:
		return
	_player.play(_resume_at)


## Mémorise la position puis arrête : le prochain resume reprend au même endroit.
func pause() -> void:
	if _player == null or not _player.playing:
		return
	_resume_at = _player.get_playback_position()
	_player.stop()


func _load_track() -> AudioStream:
	if ResourceLoader.exists(TRACK_PATH):
		var ogg := load(TRACK_PATH) as AudioStreamOggVorbis
		if ogg != null:
			ogg.loop = true
			return ogg
	return _fallback_pad()


## Nappe de secours : somme de sinusoïdes dont les fréquences tiennent un nombre entier de
## périodes dans la boucle (multiples de 1/16 Hz), donc la boucle se raccorde sans clic.
func _fallback_pad() -> AudioStreamWAV:
	var frames := int(RATE * FALLBACK_SEC)
	var freqs := [55.0, 82.5, 110.0, 165.0, 220.5]
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t := float(i) / RATE
		var v := 0.0
		for f in freqs:
			v += sin(TAU * f * t)
		# Respiration lente (0,125 Hz = 2 périodes dans la boucle).
		v *= 0.12 * (0.7 + 0.3 * sin(TAU * 0.125 * t))
		data.encode_s16(i * 2, clampi(int(v * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frames
	return wav
