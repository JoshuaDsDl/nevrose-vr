class_name WeaponModel
extends RefCounted
## Modèles des armes du mode Chasse : de vrais assets low poly déjà dans le projet
## (pack « Ultimate Gun Pack » de Quaternius, licence CC0, et le couteau / la grenade
## de assets/Gun&Knife), normalisés à la taille d'une vraie arme tenue en main.
## Origine du modèle retourné = la poignée ; le canon / la lame part vers -Z.

const GUNS := "res://assets/Gun&Knife/Ultimate Gun Pack by Quaternius/FBX/"
const LOW := "res://assets/Gun&Knife/Guns Low Poly/"

## `scale` ramène l'asset à sa taille réelle ; `rot` tourne le canon vers -Z
## (les canons Quaternius pointent vers +X, la lame du couteau vers +Y).
const MODELS := {
	"arme_couteau": {"path": "res://assets/Gun&Knife/low_poly_knife.glb", "scale": 0.08, "rot": Vector3(-90, 0, 0)},
	"arme_pistolet": {"path": GUNS + "Pistol_1.fbx", "scale": 0.11, "rot": Vector3(0, 90, 0)},
	"arme_revolver": {"path": GUNS + "Revolver_1.fbx", "scale": 0.12, "rot": Vector3(0, 90, 0)},
	"arme_pompe": {"path": GUNS + "Shotgun_1.fbx", "scale": 0.17, "rot": Vector3(0, 90, 0)},
	"arme_fusil": {"path": GUNS + "AssaultRifle_1.fbx", "scale": 0.27, "rot": Vector3(0, 90, 0)},
	"arme_grenade": {"path": LOW + "granada.blend", "scale": 0.17, "rot": Vector3(0, 0, 0)},
}


## Retourne le nœud de l'arme (vide si l'identifiant est inconnu). La portée utile
## (distance de la poignée au bout du canon / de la lame) est dans la méta « reach ».
static func build(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Arme_" + id
	if not MODELS.has(id):
		return root
	var cfg: Dictionary = MODELS[id]
	var packed := load(String(cfg["path"])) as PackedScene
	if packed == null:
		push_warning("WeaponModel: asset introuvable %s" % cfg["path"])
		return root
	var model: Node3D = packed.instantiate()
	model.name = "Modele"
	model.rotation_degrees = cfg["rot"]
	model.scale = Vector3.ONE * float(cfg["scale"])
	root.add_child(model)
	var box := _bounds(model, Transform3D(model.transform.basis, Vector3.ZERO))
	root.set_meta("reach", maxf(-box.position.z, 0.05))
	return root


## Emprise du modèle (dans le repère de son parent), pour connaître sa longueur.
static func _bounds(n: Node3D, acc: Transform3D) -> AABB:
	var box := AABB()
	var has := false
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		box = acc * (n as MeshInstance3D).mesh.get_aabb()
		has = true
	for c in n.get_children():
		if c is Node3D:
			var sub := _bounds(c as Node3D, acc * (c as Node3D).transform)
			if sub.size != Vector3.ZERO:
				box = sub if not has else box.merge(sub)
				has = true
	return box
