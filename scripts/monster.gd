class_name Monster
extends Node3D
## Le monstre qui cogne dans les murs. Modèle animé (mannequin riggé, 7 animations)
## repeint en silhouette noire aux yeux de braise ; il n'existe pas vraiment : il
## apparaît quelques secondes puis se dissout.

const MODEL := "res://assets/monster/entity.glb"
const HEIGHT := 2.15 ## un peu plus grand qu'un humain

var _player: AnimationPlayer = null
var _materials: Array[StandardMaterial3D] = []
var _model: Node3D = null


func _ready() -> void:
	var packed: PackedScene = load(MODEL)
	if packed == null:
		push_warning("Monster: modèle introuvable " + MODEL)
		return
	_model = packed.instantiate()
	_model.name = "Model"
	# Le mannequin fait ~1,8 m : on l'étire en hauteur pour une silhouette décharnée.
	_model.scale = Vector3(0.95, HEIGHT / 1.8, 0.95)
	add_child(_model)
	_paint(_model)
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_player = players[0] as AnimationPlayer
		for anim_name in _player.get_animation_list():
			_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		play(&"sneak_pose")


func play(anim: StringName, blend := 0.3) -> void:
	if _player != null and _player.has_animation(anim):
		_player.play(anim, blend)


## Noir mat, liseré rouge sombre : se découpe sur les murs même dans le noir.
func _paint(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.03, 0.025, 0.03)
			mat.roughness = 0.35
			mat.rim_enabled = true
			mat.rim = 1.0
			mat.rim_tint = 0.3
			mat.emission_enabled = true
			mat.emission = Color(0.55, 0.02, 0.02)
			mat.emission_energy_multiplier = 0.35
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mi.set_surface_override_material(s, mat)
			_materials.append(mat)
	for c in node.get_children():
		_paint(c)


## Se fond dans l'air : il n'a jamais été là.
func dissolve(duration := 1.2) -> void:
	if _player != null:
		play(&"headShake", 0.15)
	var tw := create_tween().set_parallel(true)
	for m in _materials:
		tw.tween_property(m, "albedo_color:a", 0.0, duration)
		tw.tween_property(m, "emission_energy_multiplier", 3.0, duration * 0.4)
	tw.chain().tween_callback(queue_free)
