class_name Sfx
extends RefCounted
## Sons synthétisés au démarrage (aucun fichier audio à embarquer) : toc dans le
## mur, coups de plâtre, fracas, apparition du monstre. Mono 16 bits, mis en cache.

const RATE := 22050

static var _cache := {}


static func knock() -> AudioStreamWAV:
	if not _cache.has("knock"):
		_cache["knock"] = _synth(0.22, func(t: float, n: float) -> float:
			# Coup sourd dans une cloison : grave qui descend + claquement de bois.
			var f := 105.0 - 55.0 * minf(t / 0.2, 1.0)
			return sin(TAU * f * t) * exp(-t * 24.0) * 0.9 + n * exp(-t * 110.0) * 0.45)
	return _cache["knock"]


static func hit() -> AudioStreamWAV:
	if not _cache.has("hit"):
		_cache["hit"] = _synth(0.35, func(t: float, n: float) -> float:
			# Coup de poing dans le plâtre : choc + éclats.
			return sin(TAU * 70.0 * t) * exp(-t * 18.0) * 0.8 + n * exp(-t * 26.0) * 0.55)
	return _cache["hit"]


static func crash() -> AudioStreamWAV:
	if not _cache.has("crash"):
		_cache["crash"] = _synth(1.1, func(t: float, n: float) -> float:
			# Effondrement du plâtre : grosse explosion de bruit puis gravats qui tombent.
			var rubble := n * exp(-t * 4.0) * 0.7
			var thud := sin(TAU * 52.0 * t) * exp(-t * 9.0) * 0.9
			var clatter := n * (0.5 + 0.5 * sin(TAU * 17.0 * t)) * exp(-(t - 0.45) * (t - 0.45) * 60.0) * 0.3
			return rubble + thud + clatter)
	return _cache["crash"]


static func sting() -> AudioStreamWAV:
	if not _cache.has("sting"):
		_cache["sting"] = _synth(2.2, func(t: float, n: float) -> float:
			# Accord dissonant qui enfle puis s'écroule : le monstre apparaît.
			var env := smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(1.2, 2.2, t))
			var s := sin(TAU * 146.8 * t) + sin(TAU * 155.6 * t) + 0.6 * sin(TAU * 311.0 * t * (1.0 + 0.02 * sin(t * 9.0)))
			return (s * 0.28 + n * 0.12) * env)
	return _cache["sting"]


## Génère un flux : `shape.call(t, bruit)` renvoie l'échantillon (-1..1).
static func _synth(duration: float, shape: Callable) -> AudioStreamWAV:
	var frames := int(RATE * duration)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var low := 0.0
	for i in frames:
		var t := float(i) / RATE
		# Bruit adouci (filtre passe-bas) pour un son de plâtre plutôt que de souffle.
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.35)
		var v: float = shape.call(t, low)
		data.encode_s16(i * 2, clampi(int(v * 32767.0 * 0.9), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
