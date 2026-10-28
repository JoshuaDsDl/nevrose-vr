extends SceneTree
## Test du système de verrous (GDD §5.6) : clé, force, signaux.
## Headless-safe : conteneurs nus (pas de mesh), états vérifiés immédiatement.
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/test_locks.gd

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
	print("=== TEST VERROUS (GDD §5.6) ===")

	# --- 1) Conteneur libre (aucun verrou) : s'ouvre au 1er interact ---
	var free_c := InteractiveContainer.new(InteractiveContainer.Mode.SLIDE, Vector3.BACK, 0.45, 115.0, InteractiveContainer.LockType.NONE)
	free_c.name = "FreeDrawer"
	root.add_child(free_c)
	check("libre : initialisé non verrouillé", not free_c.is_locked)
	free_c.interact()
	check("libre : ouvert après 1 interact", free_c.is_open)

	# --- 2) Conteneur KEY : sans clé → reste fermé ---
	var key_c := InteractiveContainer.new(InteractiveContainer.Mode.SLIDE, Vector3.BACK, 0.45, 115.0, InteractiveContainer.LockType.KEY)
	key_c.name = "KeyDrawer"
	root.add_child(key_c)
	check("KEY : initialisé verrouillé", key_c.is_locked)
	var kflag := {"unlocked": false} ## dict = capture fiable par référence
	key_c.unlocked_by_key.connect(func(_c): kflag["unlocked"] = true)
	key_c.interact() # sans clé (null)
	check("KEY : resté fermé sans clé", (not key_c.is_open) and key_c.is_locked)
	check("KEY : pas de signal unlocked sans clé", not kflag["unlocked"])

	# Clé FAUSSE (pas celle attendue) → reste fermé
	var wrong_key := KeyObject.new()
	key_c.interact(wrong_key)
	check("KEY : resté fermé avec mauvaise clé", key_c.is_locked and not key_c.is_open)

	# Clé CORRECTE → déverrouille + ouvre + signal
	var good_key := KeyObject.new()
	key_c.required_key = good_key
	key_c.interact(good_key)
	check("KEY : déverrouillé + ouvert avec bonne clé", (not key_c.is_locked) and key_c.is_open)
	check("KEY : signal unlocked_by_key émis", kflag["unlocked"])

	# --- 3) Conteneur FORCEABLE : 3 frappes → cède + signal lock_broken ---
	var force_c := InteractiveContainer.new(InteractiveContainer.Mode.ROTATE, Vector3.ZERO, 0.0, 115.0, InteractiveContainer.LockType.FORCEABLE)
	force_c.name = "ForceDoor"
	root.add_child(force_c)
	check("FORCE : initialisé verrouillé", force_c.is_locked)
	var fflag := {"broken": false, "noise": -1.0}
	force_c.lock_broken.connect(func(_c, n):
		fflag["broken"] = true
		fflag["noise"] = n)
	force_c.interact()
	check("FORCE : fermé après 1 frappe (1/3)", force_c.is_locked and force_c.force_hits == 1)
	force_c.interact()
	check("FORCE : fermé après 2 frappes (2/3)", force_c.is_locked and force_c.force_hits == 2)
	force_c.interact()
	check("FORCE : cédé après 3 frappes (3/3)", (not force_c.is_locked) and force_c.is_open)
	check("FORCE : signal lock_broken émis", fflag["broken"])
	check("FORCE : bruit porté par le signal", fflag["noise"] > 0.0)

	print("")
	print("=== RESULTAT: %d PASS, %d FAIL ===" % [passed, failed])
	quit(1 if failed > 0 else 0)
