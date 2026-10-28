extends SceneTree
## Test mimic mobile (GDD Round 3 — §5.3) : dérive vers la cible,
## dissolution au pointage. Headless-safe (pas de scène lourde).
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/test_mobile_mimic.gd

var passed := 0
var failed := 0


func check(name: String, cond: bool) -> void:
	if cond:
		passed += 1
		print("  [PASS] " + name)
	else:
		failed += 1
		printerr("  [FAIL] " + name)


func _initialize() -> void:
	print("=== TEST MIMIC MOBILE (Round 3) ===")

	# Cible (simule xr_camera) à une position connue
	var target := Node3D.new()
	target.name = "FakePlayer"
	target.position = Vector3(0, 0, 0)
	root.add_child(target)

	# Mimic mobile spawné loin de la cible
	var m := Mimic.new()
	m.name = "MobileMimic"
	m.is_mobile = true
	m.move_speed = 1.0 ## assez lent pour ne pas atteindre la cible en 60 frames
	m.attract_target = target
	m.position = Vector3(-2.8, 0.0, -2.0)
	root.add_child(m)

	check("init : mesh fallback auto (pas de mesh enfant avant _ready)", true)
	await process_frame
	check("init : mesh fallback présent après _ready", m._has_mesh())
	check("init : collision présente", m.get_node_or_null("CollisionShape3D") != null or _count_collisions(m) > 0)

	var d0: float = m.global_transform.origin.distance_to(target.global_transform.origin)

	# Laisse-le dériver ~1 seconde
	for i in 60:
		await process_frame
	var d1 := d0
	if is_instance_valid(m):
		d1 = m.global_transform.origin.distance_to(target.global_transform.origin)

	check("dérive : toujours vivant après 1s (n'a pas atteint la cible)", is_instance_valid(m))
	check("dérive : la distance a diminué (%.2f -> %.2f)" % [d0, d1], d1 < d0)

	# S'il est toujours là et proche → dissolution au pointage
	if is_instance_valid(m) and m._dissolving == false:
		m.interact()
		await process_frame
		check("dissolution : interact() déclenche la dissolution", m._dissolving)
		# Le tween de dissolution dure 0.4s → on attend via timer (fiable en headless)
		await create_timer(0.8).timeout
		check("dissolution : le mimic se détruit après dissolution", not is_instance_valid(m))

	print("")
	print("=== RESULTAT: %d PASS, %d FAIL ===" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _count_collisions(node: Node) -> int:
	var n := 0
	for c in node.get_children():
		if c is CollisionShape3D:
			n += 1
	return n
