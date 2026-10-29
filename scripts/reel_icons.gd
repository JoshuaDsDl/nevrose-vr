class_name ReelIcons
extends RefCounted
## Icônes de l'interface « réels » dessinées au démarrage (aucune image importée) :
## cœur, bulle de commentaire, avion en papier. Polygones rastérisés en 64×64 avec
## un petit anticrénelage, mis en cache.

const SIZE := 64

static var _cache := {}


static func heart(color: Color = Color(1.0, 0.27, 0.42)) -> Texture2D:
	return _icon("heart", color, [_heart_polygon()])


static func bubble(color: Color = Color(0.95, 0.95, 0.95)) -> Texture2D:
	var body := PackedVector2Array()
	for i in 29:
		var a := TAU * i / 28.0
		body.append(Vector2(32.0 + cos(a) * 27.0, 27.0 + sin(a) * 21.0))
	var tail := PackedVector2Array([Vector2(12, 40), Vector2(10, 60), Vector2(32, 46)])
	return _icon("bubble", color, [body, tail])


static func plane(color: Color = Color(0.95, 0.95, 0.95)) -> Texture2D:
	return _icon("plane", color, [
		PackedVector2Array([Vector2(5, 28), Vector2(59, 6), Vector2(34, 58), Vector2(27, 36)])])


static func _heart_polygon() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 64:
		var t := TAU * i / 64.0
		var x := 16.0 * pow(sin(t), 3.0)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		pts.append(Vector2(32.0 + x * 1.85, 30.0 - y * 1.75))
	return pts


static func _icon(key: String, color: Color, polys: Array) -> Texture2D:
	var id := "%s_%s" % [key, color.to_html()]
	if _cache.has(id):
		return _cache[id]
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(color.r, color.g, color.b, 0.0))
	for y in SIZE:
		for x in SIZE:
			var covered := 0
			for sy in 3:
				for sx in 3:
					var p := Vector2(x + (sx + 0.5) / 3.0, y + (sy + 0.5) / 3.0)
					for poly in polys:
						if Geometry2D.is_point_in_polygon(p, poly):
							covered += 1
							break
			if covered > 0:
				img.set_pixel(x, y, Color(color.r, color.g, color.b, covered / 9.0))
	var tex := ImageTexture.create_from_image(img)
	_cache[id] = tex
	return tex
