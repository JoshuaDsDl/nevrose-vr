extends SceneTree
## Captures de contrôle de l'appartement (à lancer en fenêtre, pas en headless) :
## Godot --path . --script res://tools/shots.gd -- <dossier de sortie>
## Chaque vue est une caméra à 1,6 m placée dans la pièce.

const VIEWS := {
	"couloir_entree": [Vector3(10.4, 1.6, 2.0), Vector3(4.6, 1.5, 2.0)],
	"couloir_porte_manteau": [Vector3(8.6, 1.6, 2.6), Vector3(7.5, 1.2, 1.35)],
	"chambre": [Vector3(4.7, 1.6, 0.2), Vector3(8.6, 1.3, -3.6)],
	"dressing": [Vector3(9.9, 1.6, -1.6), Vector3(10.6, 1.3, -4.2)],
	"sdb": [Vector3(9.8, 1.6, 0.1), Vector3(12.6, 1.2, -0.3)],
	"garage": [Vector3(5.0, 1.6, 6.8), Vector3(9.0, 1.3, 4.0)],
	"garage_voiture": [Vector3(9.8, 1.6, 4.4), Vector3(12.2, 1.1, 5.25)],
	"dessus": [Vector3(9.0, 26.0, 2.0), Vector3(9.0, 0.0, 2.0)],
}


func _init() -> void:
	var out_dir := "user://shots"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var packed: PackedScene = load("res://scenes/map2_extended.tscn")
	var map := packed.instantiate()
	root.add_child(map)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.03, 0.025, 0.04)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.32, 0.28, 0.3)
	env.environment.ambient_light_energy = 0.7
	root.add_child(env)
	var cam := Camera3D.new()
	cam.fov = 75.0
	root.add_child(cam)
	await process_frame
	for name in VIEWS:
		var pose: Array = VIEWS[name]
		cam.position = pose[0]
		cam.look_at(pose[1], Vector3.UP)
		cam.make_current()
		for i in 3:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		var path := out_dir.path_join(name + ".png")
		img.save_png(path)
		print("CAPTURE ", ProjectSettings.globalize_path(path))
	quit()
