class_name KeyObject
extends Node3D
## Clé cachée dans la maison (GDD §5.6) — déverrouille un conteneur
## spécifique quand le joueur la tient (main animée = grip serré).
## Visuel : petit objet métallique (cylindre + entaille), couleur dorée.

var target_container: Node3D = null ## Le conteneur qu'elle déverrouille
var is_held := false

const COLOR := Color(1.0, 0.85, 0.2)


func _ready() -> void:
	_build_mesh()


func _build_mesh() -> void:
	var root := Node3D.new()
	root.name = "KeyMesh"
	add_child(root)

	# Tige
	var tige := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.012
	cyl.height = 0.12
	tige.mesh = cyl
	tige.position = Vector3(0, 0, 0)
	root.add_child(tige)

	# Tête (anneau)
	var tete := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.02
	torus.outer_radius = 0.035
	torus.ring_segments = 12
	torus.rings = 12
	tete.mesh = torus
	tete.position = Vector3(0, 0.07, 0)
	tete.rotation.x = PI / 2
	root.add_child(tete)

	# Dent
	var dent := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.008, 0.03, 0.025)
	dent.mesh = box
	dent.position = Vector3(0.008, -0.05, 0)
	root.add_child(dent)

	# Matériau
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR
	mat.metallic = 0.8
	mat.roughness = 0.3
	for child in root.get_children():
		if child is MeshInstance3D:
			child.material_override = mat

	# Zone de pickup (Area3D)
	var area := Area3D.new()
	area.name = "pickup_area"
	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.06
	col.shape = sph
	area.add_child(col)
	add_child(area)
	area.body_entered.connect(_on_pickup_area_entered)


func _on_pickup_area_entered(_body: Node) -> void:
	# Le pickup est géré par main.gd (raycast) — cet Area3D sert
	# uniquement de zone de proximité pour l'affichage "prêt à prendre"
	pass


func can_unlock(container: Node3D) -> bool:
	return container == target_container


# --- Interface raycast (main.gd) ---
func on_pointed() -> void:
	if get_node_or_null("KeyMesh"):
		get_node("KeyMesh").scale = Vector3.ONE * 1.3


func on_unpointed() -> void:
	if get_node_or_null("KeyMesh"):
		get_node("KeyMesh").scale = Vector3.ONE
