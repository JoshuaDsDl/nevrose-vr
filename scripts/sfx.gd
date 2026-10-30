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


## Bip de compte à rebours ; `go` = bip final, plus aigu et plus long.
static func beep(go: bool = false) -> AudioStreamWAV:
	var key := "beep_go" if go else "beep"
	if not _cache.has(key):
		var f := 1318.5 if go else 880.0
		_cache[key] = _synth(0.4 if go else 0.16, func(t: float, _n: float) -> float:
			var env := minf(t / 0.005, 1.0) * exp(-t * (7.0 if go else 18.0))
			return sin(TAU * f * t) * env * 0.7)
	return _cache[key]


## Notification de téléphone : deux notes montantes.
static func ding() -> AudioStreamWAV:
	if not _cache.has("ding"):
		_cache["ding"] = _synth(0.55, func(t: float, _n: float) -> float:
			var a := sin(TAU * 988.0 * t) * exp(-t * 9.0)
			var tb := maxf(t - 0.11, 0.0)
			var b := sin(TAU * 1480.0 * tb) * exp(-tb * 8.0) * (1.0 if t >= 0.11 else 0.0)
			return (a * 0.5 + b * 0.6) * 0.8)
	return _cache["ding"]


## Petite bulle qui éclate : un commentaire qui arrive.
static func pop() -> AudioStreamWAV:
	if not _cache.has("pop"):
		_cache["pop"] = _synth(0.12, func(t: float, _n: float) -> float:
			var f := 520.0 + 900.0 * minf(t / 0.05, 1.0)
			return sin(TAU * f * t) * exp(-t * 40.0) * 0.8)
	return _cache["pop"]


## Pièces : les tokens tombent.
static func coins() -> AudioStreamWAV:
	if not _cache.has("coins"):
		_cache["coins"] = _synth(0.9, func(t: float, n: float) -> float:
			var s := 0.0
			for k in 4:
				var tk := t - 0.09 * k
				if tk > 0.0:
					s += (sin(TAU * 2093.0 * tk) + 0.5 * sin(TAU * 3136.0 * tk)) * exp(-tk * 11.0)
			return s * 0.22 + n * exp(-t * 60.0) * 0.1)
	return _cache["coins"]


## Montée de tension pendant l'analyse du réel.
static func whoosh() -> AudioStreamWAV:
	if not _cache.has("whoosh"):
		_cache["whoosh"] = _synth(0.9, func(t: float, n: float) -> float:
			var env := sin(PI * clampf(t / 0.9, 0.0, 1.0))
			return n * env * 0.5 + sin(TAU * (180.0 + 500.0 * t) * t) * env * 0.12)
	return _cache["whoosh"]


## Coup de feu : claquement sec + queue grave. `kind` : "pistolet", "revolver", "pompe", "fusil".
static func shot(kind: String) -> AudioStreamWAV:
	var key := "shot_" + kind
	if not _cache.has(key):
		var length := 0.35
		var body := 160.0
		var snap := 90.0
		var tail := 14.0
		match kind:
			"revolver":
				length = 0.55
				body = 95.0
				tail = 8.0
			"pompe":
				length = 0.7
				body = 70.0
				snap = 55.0
				tail = 6.0
			"fusil":
				length = 0.22
				body = 130.0
				snap = 120.0
				tail = 20.0
		_cache[key] = _synth(length, func(t: float, n: float) -> float:
			var crack := n * exp(-t * snap) * 0.95
			var boom := sin(TAU * body * t * exp(-t * 3.0)) * exp(-t * tail) * 0.9
			return crack + boom)
	return _cache[key]


## Explosion de grenade : grondement long et fracas.
static func boom() -> AudioStreamWAV:
	if not _cache.has("boom"):
		_cache["boom"] = _synth(1.8, func(t: float, n: float) -> float:
			var rumble := sin(TAU * 42.0 * t * exp(-t * 1.2)) * exp(-t * 2.4) * 1.0
			var blast := n * exp(-t * 5.0) * 0.9
			var debris := n * (0.5 + 0.5 * sin(TAU * 11.0 * t)) * exp(-(t - 0.5) * (t - 0.5) * 8.0) * 0.25
			return rumble + blast + debris)
	return _cache["boom"]


## Tic de grenade dégoupillée.
static func tick() -> AudioStreamWAV:
	if not _cache.has("tick"):
		_cache["tick"] = _synth(0.06, func(t: float, _n: float) -> float:
			return sin(TAU * 1800.0 * t) * exp(-t * 70.0) * 0.6)
	return _cache["tick"]


## « POP » de bouteille de champagne : claquement de bouchon, résonance du goulot, mousse.
static func champagne() -> AudioStreamWAV:
	if not _cache.has("champagne"):
		_cache["champagne"] = _synth(1.6, func(t: float, n: float) -> float:
			var pop := sin(TAU * (210.0 - 120.0 * minf(t / 0.12, 1.0)) * t) * exp(-t * 28.0) * 1.0
			var thump := sin(TAU * 62.0 * t) * exp(-t * 14.0) * 0.8
			var click := n * exp(-t * 160.0) * 0.9
			var hiss := n * exp(-t * 2.8) * 0.28 * smoothstep(0.03, 0.14, t)
			var neck := sin(TAU * 520.0 * t) * exp(-t * 9.0) * 0.25
			return pop + thump + click + hiss + neck)
	return _cache["champagne"]


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
