extends SceneTree
## Test de marche : chaque point libre de l'appartement doit Ãªtre atteignable depuis le
## point de dÃ©part, avec la capsule du joueur (rayon 0,28 m, hauteur 1,7 m), sans traverser
## de mur ni de meuble. Une case libre inaccessible = le joueur serait bloquÃ©.
##
## Usage : Godot --headless --path . --script res://tests/walk_test.gd

const CELL := 0.25
const CAPSULE_RADIUS := 0.28
const CAPSULE_HEIGHT := 1.7
const LIFT := 0.05 # la capsule flotte de 5 cm : ne touche pas le sol (y = 0)
const START := Vector2(-1.0, 0.0) # APARTMENT_SPAWN de main.gd

# PiÃ¨ces : x0, x1, z0, z1 (intÃ©rieur, en mÃ¨tres)
const ROOMS := {
	"Salon": [-4.2, 4.2, -3.1, 3.1],
	"Chambre": [4.3, 9.5, -4.8, 1.1],
	"Dressing": [9.5, 11.7, -4.8, -1.4],
	"SDB": [9.5, 13.2, -1.4, 1.1],
	"WC": [11.7, 13.2, -4.8, -1.4],
	"Couloir": [4.3, 10.7, 1.1, 3.15],
	"Garage": [4.3, 9.5, 3.15, 7.6],
	"Voiture": [9.5, 14.5, 3.15, 7.6],
}

# Points qui doivent Ãªtre accessibles : centres de piÃ¨ces et lieux utiles
const MUST_REACH := {
	"centre salon": Vector2(-1.0, 0.0),
	"centre chambre": Vector2(6.8, -2.0),
	"dressing": Vector2(10.6, -3.1),
	"SDB": Vector2(10.3, 0.5),
	"couloir": Vector2(8.5, 2.5),
	"garage": Vector2(6.0, 4.5),
	"garage voiture": Vector2(13.0, 3.8),
	"toilettes": Vector2(12.45, -3.0),
	"accÃ¨s WC": Vector2(11.2, -2.75),
}

var _apartment: Node = null
var _shape := CapsuleShape3D.new()
var _failures := 0


func _init() -> void:
	_shape.radius = CAPSULE_RADIUS
	_shape.height = CAPSULE_HEIGHT
	_run.call_deferred()


func _run() -> void:
	var script: GDScript = load("res://scripts/map2_extended.gd")
	_apartment = script.new()
	_apartment.name = "Map2Extended"
	root.add_child(_apartment)
	_apartment.build()
	# Laisse la physique enregistrer les collisions des meubles et des murs.
	for i in 3:
		await physics_frame

	var free := _free_cells()
	var reached := _flood(free)
	print("cases libres : %d, atteignables : %d" % [free.size(), reached.size()])
	# Zones libres fermÃ©es : une zone de plus de 1 mÂ² (16 cases) est un vrai passage bloquÃ©.
	# Les petites poches entre deux meubles sont signalÃ©es sans faire Ã©chouer le test.
	var pockets := _unreached_components(free, reached)
	for pocket in pockets:
		var room := _room_of(pocket[0])
		var size: int = pocket.size()
		if size >= 16:
			_failures += 1
			print("  BLOQUÃ‰  %-9s zone de %d cases (%.1f mÂ²) ex. %s" % [room, size, size * CELL * CELL, str(_center(pocket[0]))])
		else:
			print("  poche   %-9s %d case(s) entre meubles ex. %s" % [room, size, str(_center(pocket[0]))])
	if pockets.is_empty():
		print("  aucune zone libre fermÃ©e")

	# Diagnostic : le passage entre le couloir et le garage (porte x 5.6-6.5, z 2.9-3.15).
	for p in [Vector2(3.9, 2.0), Vector2(4.6, 2.0), Vector2(6.3, 1.0), Vector2(6.3, 0.2), Vector2(5.0, -1.0)]:
		var cell := _snap(p)
		print("  diag %s libre=%s atteignable=%s touche=%s" % [str(p), free.has(cell), reached.has(cell), str(_hits_at(p))])

	for label in MUST_REACH:
		var cell := _snap(MUST_REACH[label])
		var p := _center(cell)
		if not free.has(cell):
			print("  OCCUPÃ‰ %-15s %s : touche %s" % [label, str(p), str(_hits_at(p))])
			_failures += 1
		elif not reached.has(cell):
			print("  KO     %-15s %s : inaccessible" % [label, str(p)])
			_failures += 1
		else:
			print("  OK     %s" % label)

	_apartment.queue_free()
	print("=== RESULTAT MARCHE: %s (%d Ã©chec(s)) ===" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


## Un point de la grille est libre si la capsule du joueur n'y touche aucun obstacle.
func _free_cells() -> Dictionary:
	var cells := {}
	for room in ROOMS:
		var r: Array = ROOMS[room]
		var x: float = snappedf(r[0], CELL)
		while x <= r[1]:
			var z: float = snappedf(r[2], CELL)
			while z <= r[3]:
				var cell := _snap(Vector2(x, z))
				if _is_free(_center(cell)):
					cells[cell] = true
				z += CELL
			x += CELL
	return cells


## Noms des obstacles touchÃ©s Ã  un point (diagnostic des cases occupÃ©es ou fermÃ©es).
func _hits_at(p: Vector2) -> Array:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape
	q.transform = Transform3D(Basis(), Vector3(p.x, CAPSULE_HEIGHT * 0.5 + LIFT, p.y))
	q.collision_mask = 1
	q.collide_with_areas = false
	var names := []
	for hit in get_root().get_world_3d().direct_space_state.intersect_shape(q, 8):
		var owner: Node3D = hit["collider"]
		var shape := owner.get_child(0) as CollisionShape3D
		names.append("%s (x %.2f..%.2f, z %.2f..%.2f)" % [owner.name, owner.global_position.x - shape.shape.size.x / 2.0,
			owner.global_position.x + shape.shape.size.x / 2.0, owner.global_position.z - shape.shape.size.z / 2.0,
			owner.global_position.z + shape.shape.size.z / 2.0])
	return names


func _is_free(p: Vector2) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape
	q.transform = Transform3D(Basis(), Vector3(p.x, CAPSULE_HEIGHT * 0.5 + LIFT, p.y))
	q.collision_mask = 1
	q.collide_with_areas = false
	return get_root().get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## Parcours en largeur depuis le dÃ©part ; un pas est valide si la capsule peut glisser
## de la case A Ã  la case B sans toucher d'obstacle.
func _flood(free: Dictionary) -> Dictionary:
	var start := _snap(START)
	var reached := {start: true}
	var queue: Array[Vector2i] = [start]
	var space := get_root().get_world_3d().direct_space_state
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var next: Vector2i = cell + d
			if reached.has(next) or not free.has(next):
				continue
			if _can_step(space, _center(cell), _center(next)):
				reached[next] = true
				queue.append(next)
	return reached


func _can_step(space: PhysicsDirectSpaceState3D, a: Vector2, b: Vector2) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape
	q.transform = Transform3D(Basis(), Vector3(a.x, CAPSULE_HEIGHT * 0.5 + LIFT, a.y))
	q.motion = Vector3(b.x - a.x, 0.0, b.y - a.y)
	q.collision_mask = 1
	q.collide_with_areas = false
	var fractions := space.cast_motion(q)
	return fractions[1] >= 1.0


## Regroupe les cases libres non atteignables en zones connexes (quatre directions).
func _unreached_components(free: Dictionary, reached: Dictionary) -> Array:
	var seen := {}
	var result := []
	for cell in free:
		if reached.has(cell) or seen.has(cell):
			continue
		var comp := []
		var stack: Array[Vector2i] = [cell]
		seen[cell] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			comp.append(c)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if free.has(n) and not reached.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
		result.append(comp)
	return result


func _center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * CELL, cell.y * CELL)


func _snap(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x / CELL), roundi(p.y / CELL))


func _room_of(cell: Vector2i) -> String:
	var p := _center(cell)
	for room in ROOMS:
		var r: Array = ROOMS[room]
		if p.x >= r[0] and p.x <= r[1] and p.y >= r[2] and p.y <= r[3]:
			return room
	return "hors piÃ¨ces"

