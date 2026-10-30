class_name NavGrid
extends Node3D
## Carte d'accessibilité de l'appartement : le sol est quadrillé (maille de 0,3 m) et on garde
## les cases où le joueur peut vraiment se tenir (capsule de collision libre), en partant de
## sa position. Sert à deux choses :
##   - ne placer aucune plaque (Chasse) derrière la porte verrouillée ou dehors ;
##   - le GPS du téléphone : flèche qui suit le plus court chemin à pied vers une cible.

const CELL := 0.3
const PLAYER_RADIUS := 0.3

var reachable := {} ## Vector2i -> true
var _done := false ## vrai seulement une fois le calcul entièrement terminé
var origin := Vector2(-4.0, -4.8)

var _dist := {} ## Vector2i -> nombre de pas jusqu'à la cible du GPS


func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor((p.x - origin.x) / CELL)), int(floor((p.z - origin.y) / CELL)))


func cell_center(c: Vector2i) -> Vector3:
	return Vector3(origin.x + (c.x + 0.5) * CELL, 0.0, origin.y + (c.y + 0.5) * CELL)


func is_ready() -> bool:
	return _done and not reachable.is_empty()


func has_point(p: Vector3) -> bool:
	return reachable.has(cell_of(p))


func _cell_free(space: PhysicsDirectSpaceState3D, params: PhysicsShapeQueryParameters3D, c: Vector2i) -> bool:
	var center := cell_center(c)
	for h in [0.45, 1.2]:
		params.transform = Transform3D(Basis.IDENTITY, Vector3(center.x, h, center.z))
		if not space.intersect_shape(params, 1).is_empty():
			return false
	return true


## Coroutine : étale le calcul sur plusieurs images physiques (casque).
func compute_reachable(from_pos: Vector3, bounds_min: Vector2, bounds_max: Vector2) -> void:
	reachable.clear()
	_done = false
	var space := get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = PLAYER_RADIUS
	params.shape = shape
	params.collision_mask = 1
	var min_cell := cell_of(Vector3(bounds_min.x - 0.3, 0.0, bounds_min.y - 0.3))
	var max_cell := cell_of(Vector3(bounds_max.x + 0.3, 0.0, bounds_max.y + 0.3))
	var start := cell_of(from_pos)
	for radius in range(0, 6): # départ : la case libre la plus proche du joueur
		var picked := false
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var c := Vector2i(start.x + dx, start.y + dy)
				if _cell_free(space, params, c):
					start = c
					picked = true
					break
			if picked:
				break
		if picked:
			break
	var queue: Array[Vector2i] = [start]
	var seen := {start: true}
	reachable[start] = true
	var head := 0
	var budget := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = cell + d
			if nxt.x < min_cell.x or nxt.y < min_cell.y or nxt.x > max_cell.x or nxt.y > max_cell.y:
				continue
			if seen.has(nxt):
				continue
			seen[nxt] = true
			if _cell_free(space, params, nxt):
				reachable[nxt] = true
				queue.append(nxt)
			budget += 1
			if budget % 400 == 0:
				await get_tree().physics_frame
	_done = true


## Distance (en pas) de chaque case praticable jusqu'à `goal`, par parcours en largeur.
func build_distance_field(goal_pos: Vector3) -> void:
	_dist.clear()
	if reachable.is_empty():
		return
	var goal := cell_of(goal_pos)
	if not reachable.has(goal):
		var best := Vector2i.ZERO
		var best_d := 1e9
		for c in reachable:
			var d := (Vector2(c) - Vector2(goal)).length()
			if d < best_d:
				best_d = d
				best = c
		goal = best
	var queue: Array[Vector2i] = [goal]
	_dist[goal] = 0
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for d in _NEIGHBORS:
			var nxt: Vector2i = cell + d
			if _dist.has(nxt) or not reachable.has(nxt):
				continue
			_dist[nxt] = int(_dist[cell]) + 1
			queue.append(nxt)


const _NEIGHBORS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]


## Pour le téléphone : angle de la flèche (0 = droit devant, + = à droite), distance, plafond.
## `target` : la cible réelle (pour la direction à vol d'oiseau quand on est tout près).
func gps_info(camera: Node3D, target: Vector3, vertical := 0) -> Dictionary:
	if camera == null:
		return {}
	var cam_pos := camera.global_position
	var aim := target
	var distance := Vector2(target.x - cam_pos.x, target.z - cam_pos.z).length()
	var cell := cell_of(cam_pos)
	if not _dist.has(cell): # seuil de porte ou case non cartographiée : la plus proche
		var best_d := 99.0
		var found := cell
		for dx in range(-3, 4):
			for dy in range(-3, 4):
				var c := Vector2i(cell.x + dx, cell.y + dy)
				if _dist.has(c) and Vector2(dx, dy).length() < best_d:
					best_d = Vector2(dx, dy).length()
					found = c
		cell = found
	if _dist.has(cell) and int(_dist[cell]) > 3:
		distance = float(_dist[cell]) * CELL
		var walk := cell # on suit le gradient quelques cases plus loin : virages lissés
		for i in 5:
			var best_n := walk
			var best_v := int(_dist[walk])
			for d in _NEIGHBORS:
				var n: Vector2i = walk + d
				if _dist.has(n) and int(_dist[n]) < best_v:
					best_v = int(_dist[n])
					best_n = n
			if best_n == walk:
				break
			walk = best_n
		aim = cell_center(walk)
	var to := aim - cam_pos
	to.y = 0.0
	if to.length() < 0.05:
		to = target - cam_pos
		to.y = 0.0
	var local := camera.global_transform.basis.inverse() * to
	return {"angle": atan2(local.x, -local.z), "distance": distance, "vertical": vertical}
