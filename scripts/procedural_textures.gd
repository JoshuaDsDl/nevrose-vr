class_name ProceduralTextures
extends RefCounted
## Génère des textures procédurales légères (128 à 256 px) pour habiller les
## matériaux du studio. Aucune texture importée — tout est calculé au démarrage,
## coût unique négligeable pour le Quest 2 (GDD §7 "joli mais pas gourmand").

# Bruit de valeur déterministe (pas de RandomNumberGenerator global pour rester reproductible)
static func _hash(x: int, y: int, seed: int) -> float:
	var n := x * 374761393 + y * 668265263 + seed * 1442695041
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0x7FFFFFFF) / float(0x7FFFFFFF)


static func _value_noise(w: int, h: int, scale: float, seed: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(w * h)
	var gw := int(ceil(w / scale)) + 2
	var gh := int(ceil(h / scale)) + 2
	var grid := PackedFloat32Array()
	grid.resize(gw * gh)
	for gy in gh:
		for gx in gw:
			grid[gy * gw + gx] = _hash(gx, gy, seed)
	for y in h:
		for x in w:
			var gx := int(floor(x / scale))
			var gy := int(floor(y / scale))
			var fx := x / scale - gx
			var fy := y / scale - gy
			var sx := fx * fx * (3.0 - 2.0 * fx)
			var sy := fy * fy * (3.0 - 2.0 * fy)
			var v00 := grid[gy * gw + gx]
			var v10 := grid[gy * gw + gx + 1]
			var v01 := grid[(gy + 1) * gw + gx]
			var v11 := grid[(gy + 1) * gw + gx + 1]
			var top := lerpf(v00, v10, sx)
			var bot := lerpf(v01, v11, sx)
			out[y * w + x] = lerpf(top, bot, sy)
	return out


static func _fbm(w: int, h: int, base_scale: float, octaves: int, seed: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(w * h)
	for i in w * h:
		out[i] = 0.0
	var amp := 1.0
	var total := 0.0
	var scale := base_scale
	for o in octaves:
		var layer := _value_noise(w, h, scale, seed + o * 101)
		for i in w * h:
			out[i] += layer[i] * amp
		total += amp
		amp *= 0.5
		scale *= 0.5
	for i in w * h:
		out[i] /= total
	return out


static func _to_image(w: int, h: int, pixels: PackedColorArray) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, pixels[y * w + x])
	return img


# --- Textures spécifiques ----------------------------------------------------

# Plâtre / peinture murale : bruit doux, quasi unie.
static func plaster(base: Color, w := 256, h := 256, seed := 7) -> ImageTexture:
	var noise := _fbm(w, h, 24.0, 3, seed)
	var px := PackedColorArray()
	px.resize(w * h)
	for i in w * h:
		var v := 0.92 + noise[i] * 0.12
		px[i] = Color(base.r * v, base.g * v, base.b * v)
	return ImageTexture.create_from_image(_to_image(w, h, px))


# Bois : stries horizontales sinusoïdales + bruit.
static func wood(base: Color, w := 256, h := 256, seed := 21) -> ImageTexture:
	var noise := _fbm(w, h, 10.0, 3, seed)
	var px := PackedColorArray()
	px.resize(w * h)
	for y in h:
		for x in w:
			var stripe := 0.5 + 0.5 * sin(y * 0.32 + noise[y * w + x] * 9.0)
			var v := 0.78 + stripe * 0.22 + (noise[y * w + x] - 0.5) * 0.15
			px[y * w + x] = Color(base.r * v, base.g * v, base.b * v)
	return ImageTexture.create_from_image(_to_image(w, h, px))


# Tissu : trame de petits carreaux + bruit fin.
static func fabric(base: Color, w := 128, h := 128, seed := 33) -> ImageTexture:
	var noise := _fbm(w, h, 6.0, 2, seed)
	var px := PackedColorArray()
	px.resize(w * h)
	for y in h:
		for x in w:
			var weave := ((x + y) % 2) * 0.05
			var v := 0.86 + weave + (noise[y * w + x] - 0.5) * 0.2
			px[y * w + x] = Color(base.r * v, base.g * v, base.b * v)
	return ImageTexture.create_from_image(_to_image(w, h, px))


# Carrelage / parquet : damier + joints sombres.
static func tiles(base: Color, w := 256, h := 256, cells := 4, seed := 44) -> ImageTexture:
	var noise := _fbm(w, h, 32.0, 2, seed)
	var px := PackedColorArray()
	px.resize(w * h)
	var cell: int = int(w / cells)
	var joint: int = max(1, int(cell / 16))
	for y in h:
		for x in w:
			var cx: int = x % cell
			var cy: int = y % cell
			var in_joint: bool = cx < joint or cy < joint
			var v: float = 0.82 + noise[y * w + x] * 0.2
			var col := base
			if in_joint:
				col = base * 0.45
			px[y * w + x] = Color(col.r * v, col.g * v, col.b * v)
	return ImageTexture.create_from_image(_to_image(w, h, px))


# Métal brossé : stries fines verticales.
static func metal(base: Color, w := 128, h := 128, seed := 55) -> ImageTexture:
	var noise := _fbm(w, h, 4.0, 2, seed)
	var px := PackedColorArray()
	px.resize(w * h)
	for y in h:
		for x in w:
			var v := 0.85 + (noise[y * w + x] - 0.5) * 0.25
			px[y * w + x] = Color(base.r * v, base.g * v, base.b * v)
	return ImageTexture.create_from_image(_to_image(w, h, px))
