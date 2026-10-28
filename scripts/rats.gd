extends Node3D
## Rats du jardin — des rats traversent le jardin de temps en temps.
## Modèle : res://assets/rats/rat.glb (Quaternius, CC0, animations incluses).

const RAT_SCENE: PackedScene = preload("res://assets/rats/rat.glb")

## Zone de course (limites intérieures du jardin, sur l'herbe)
const BORD_MIN := Vector3(-9.2, -0.06, -3.7)
const BORD_MAX := Vector3(-4.4, -0.06, 3.7)

@export var delai_min := 6.0 ## pause minimale entre deux courses (s)
@export var delai_max := 18.0 ## pause maximale entre deux courses (s)
@export var duree_course := 2.5 ## durée d'une traversée (s)
@export var max_rats := 2 ## rats simultanés au maximum
@export var echelle := 0.18 ## taille des rats (le GLB Quaternius est géant à l'import)

var _rats_en_course := 0


func _ready() -> void:
	_planifie_course()


func _planifie_course() -> void:
	await get_tree().create_timer(randf_range(delai_min, delai_max)).timeout
	if _rats_en_course < max_rats:
		_lance_rat()
	_planifie_course()


func _lance_rat() -> void:
	_rats_en_course += 1
	var rat: Node3D = RAT_SCENE.instantiate()
	rat.scale = Vector3(echelle, echelle, echelle)
	add_child(rat)
	var depart := _point_aleatoire()
	var arrivee := _point_aleatoire()
	rat.global_position = depart
	rat.look_at(arrivee, Vector3.UP)
	rat.rotate_y(PI) # les modèles Quaternius regardent vers +Z
	_joue_course(rat)
	var tween := create_tween()
	tween.tween_property(rat, "global_position", arrivee, duree_course)
	await tween.finished
	rat.queue_free()
	_rats_en_course -= 1


func _point_aleatoire() -> Vector3:
	return Vector3(
		randf_range(BORD_MIN.x, BORD_MAX.x),
		BORD_MIN.y,
		randf_range(BORD_MIN.z, BORD_MAX.z)
	)


func _joue_course(rat: Node) -> void:
	var joueur := rat.get_node_or_null("AnimationPlayer")
	if joueur == null:
		return
	for nom in joueur.get_animation_list():
		if String(nom).to_lower().contains("run"):
			_boucle(joueur, nom)
			return
	for nom in joueur.get_animation_list():
		if String(nom).to_lower().contains("walk"):
			_boucle(joueur, nom)
			return


func _boucle(joueur: AnimationPlayer, nom: StringName) -> void:
	## Force la boucle : les animations GLB Quaternius n'ont pas de loop à l'import.
	var anim := joueur.get_animation(nom)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
	joueur.play(nom)
