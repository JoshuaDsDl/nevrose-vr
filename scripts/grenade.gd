class_name Grenade
extends RigidBody3D
## Grenade lancée : elle rebondit, tictaque, puis explose (HuntSandbox.explode).
## Modèle : la vraie grenade de assets/Gun&Knife.

const FUSE := 2.4

var _sandbox: HuntSandbox = null
var _radius := 3.8
var _damage := 16.0
var _time := 0.0
var _ticks := 0


func launch(velocity: Vector3, sandbox: HuntSandbox, radius: float, damage: float) -> void:
	_sandbox = sandbox
	_radius = radius
	_damage = damage
	mass = 0.5
	collision_layer = 0 # ne gêne ni le joueur ni les objets : elle ne fait que rebondir sur le décor
	collision_mask = 1
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.35
	mat.friction = 0.8
	physics_material_override = mat
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.05
	cs.shape = shape
	add_child(cs)
	var model := WeaponModel.build("arme_grenade")
	add_child(model)
	linear_velocity = velocity
	angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))


func _physics_process(delta: float) -> void:
	_time += delta
	# Un tic par demi-seconde, de plus en plus rapide à l'approche de l'explosion.
	var next_tick := 0.5 + _ticks * (0.5 - _ticks * 0.04)
	if _time >= next_tick and _time < FUSE:
		_ticks += 1
		var p := AudioStreamPlayer3D.new()
		p.stream = Sfx.tick()
		p.volume_db = 0.0
		get_parent().add_child(p)
		p.global_position = global_position
		p.play()
		p.finished.connect(p.queue_free)
	if _time >= FUSE:
		if is_instance_valid(_sandbox):
			_sandbox.explode(global_position, _radius, _damage)
		queue_free()
