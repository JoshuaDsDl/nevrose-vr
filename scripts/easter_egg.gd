class_name EasterEgg
extends Node3D
## Easter egg : main derrière soi (au niveau des fesses) + gâchette maintenue 4 secondes
## → énorme « POP » de bouteille de champagne, un œuf surprise apparaît dans la main.
## Un deuxième appui sur la gâchette l'ouvre : dedans, un diplôme d'ingénieur IMT Nord Europe.

signal message(text: String)

enum State { IDLE, EGG, OPEN }

const HOLD_SECONDS := 4.0
const TRIGGER_ON := 0.7
const DIPLOMA_SECONDS := 10.0

var state: State = State.IDLE
var left: Node3D = null
var right: Node3D = null
var camera: Node3D = null

var _hold := {} ## id de la main -> secondes de maintien
var _ticks := {}
var _prev_pressed := {}
var _released_since_pop := false
var _egg: Node3D = null
var _diploma: Node3D = null


func setup(p_left: Node3D, p_right: Node3D, p_camera: Node3D) -> void:
	left = p_left
	right = p_right
	camera = p_camera


func _physics_process(delta: float) -> void:
	if camera == null:
		return
	for hand in [left, right]:
		if hand is XRController3D and is_instance_valid(hand) and (hand as XRController3D).get_is_active():
			var trigger := (hand as XRController3D).get_float(&"trigger")
			tick_hand(hand, at_butt(hand), trigger > TRIGGER_ON, delta)


## La main est-elle derrière le joueur, à hauteur de fesses ? Les proportions suivent sa taille.
func at_butt(hand: Node3D) -> bool:
	var height := camera.global_position.y # sol à y = 0 dans tous les décors
	if height < 0.5:
		return false
	var yaw := Basis(Vector3.UP, camera.global_rotation.y)
	var local := yaw.inverse() * (hand.global_position - camera.global_position)
	var drop := -local.y
	var flat := Vector2(local.x, local.z).length()
	return local.z > 0.08 and absf(local.x) < 0.5 and flat < 0.65 and drop > 0.3 * height and drop < 0.66 * height


## Un pas de temps pour une main. Séparé de la lecture des manettes pour être testable.
func tick_hand(hand: Node3D, butt: bool, pressed: bool, delta: float) -> void:
	var id := hand.get_instance_id()
	var was_pressed: bool = _prev_pressed.get(id, false)
	_prev_pressed[id] = pressed
	match state:
		State.IDLE:
			if butt and pressed:
				_hold[id] = float(_hold.get(id, 0.0)) + delta
				# Le contrôleur vibre de plus en plus fort : « il se passe quelque chose ».
				var ticks := int(float(_hold[id]))
				if ticks > int(_ticks.get(id, 0)) and ticks < int(HOLD_SECONDS):
					_ticks[id] = ticks
					_haptic(hand, 0.15 + 0.2 * ticks, 0.1)
				if float(_hold[id]) >= HOLD_SECONDS:
					pop(hand)
			else:
				_hold[id] = 0.0
				_ticks[id] = 0
		State.EGG:
			if not pressed:
				_released_since_pop = true
			elif not was_pressed and _released_since_pop:
				open_egg()


## « POP » : bruit de champagne, mousse, flash, et l'œuf surprise apparaît dans la main.
func pop(hand: Node3D) -> void:
	state = State.EGG
	_hold.clear()
	_ticks.clear()
	_released_since_pop = false
	var host := get_tree().current_scene if get_tree() != null and get_tree().current_scene != null else self
	var p := AudioStreamPlayer3D.new()
	p.stream = Sfx.champagne()
	p.volume_db = 10.0
	p.unit_size = 14.0
	host.add_child(p)
	p.global_position = hand.global_position
	p.play()
	p.finished.connect(p.queue_free)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.95, 0.75)
	flash.light_energy = 6.0
	flash.omni_range = 6.0
	host.add_child(flash)
	flash.global_position = hand.global_position
	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.25)
	tw.tween_callback(flash.queue_free)
	_foam(host, hand.global_position)
	_haptic(hand, 1.0, 0.3)
	_egg = _build_egg()
	hand.add_child(_egg)
	_egg.position = Vector3(0.0, 0.03, -0.1)
	_egg.scale = Vector3.ZERO
	var grow := _egg.create_tween()
	grow.tween_property(_egg, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	message.emit("POP ! Une surprise t'attend dans ta main. Appuie sur la gâchette pour l'ouvrir.")


## Œuf surprise : coque rouge dessus, blanche dessous, deux demi-sphères pour pouvoir l'ouvrir.
func _build_egg() -> Node3D:
	var egg := Node3D.new()
	egg.name = "OeufSurprise"
	for spec in [["Bas", Color(0.96, 0.94, 0.9), false], ["Haut", Color(0.85, 0.08, 0.1), true]]:
		var half := MeshInstance3D.new()
		half.name = spec[0]
		var sm := SphereMesh.new()
		sm.radius = 0.045
		sm.height = 0.09
		sm.is_hemisphere = true
		half.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = spec[1]
		mat.roughness = 0.35
		mat.metallic = 0.3
		half.material_override = mat
		half.scale = Vector3(1.0, 1.35, 1.0)
		if not bool(spec[2]):
			half.rotation_degrees.x = 180.0
		egg.add_child(half)
	var band := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.046
	cm.bottom_radius = 0.046
	cm.height = 0.006
	band.mesh = cm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(1.0, 0.8, 0.1)
	band.material_override = bmat
	egg.add_child(band)
	return egg


func _foam(host: Node, pos: Vector3) -> void:
	var foam := CPUParticles3D.new()
	foam.one_shot = true
	foam.emitting = true
	foam.amount = 90
	foam.lifetime = 1.4
	foam.explosiveness = 0.95
	foam.direction = Vector3(0, 1, -0.3)
	foam.spread = 45.0
	foam.initial_velocity_min = 1.5
	foam.initial_velocity_max = 3.5
	foam.gravity = Vector3(0, -3.0, 0)
	foam.local_coords = false
	foam.scale_amount_min = 0.5
	foam.scale_amount_max = 1.3
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 0.95, 0.85)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat
	foam.mesh = quad
	host.add_child(foam)
	foam.global_position = pos
	get_tree().create_timer(2.5).timeout.connect(foam.queue_free)


## Deuxième appui : l'œuf s'ouvre, un diplôme d'ingénieur se déroule devant le visage.
func open_egg() -> void:
	if state != State.EGG:
		return
	state = State.OPEN
	if is_instance_valid(_egg):
		var top := _egg.get_node_or_null("Haut") as Node3D
		if top != null:
			var tw := top.create_tween().set_parallel(true)
			tw.tween_property(top, "position", Vector3(0.02, 0.1, 0.0), 0.3)
			tw.tween_property(top, "rotation_degrees:z", 55.0, 0.3)
	_show_diploma()
	message.emit("Dans l'oeuf : un diplôme d'ingénieur IMT Nord Europe. Bravo !")
	get_tree().create_timer(DIPLOMA_SECONDS).timeout.connect(_close_diploma)


func _show_diploma() -> void:
	var host := get_tree().current_scene if get_tree() != null and get_tree().current_scene != null else self
	_diploma = Node3D.new()
	_diploma.name = "Diplome"
	host.add_child(_diploma)
	var yaw := Basis(Vector3.UP, camera.global_rotation.y)
	_diploma.global_position = camera.global_position + yaw * Vector3(0.0, -0.05, -0.95)
	_diploma.look_at(camera.global_position, Vector3.UP)
	_diploma.rotate_object_local(Vector3.UP, PI) # le recto fait face au joueur
	var frame := LobbyButton.make_panel(Vector2(0.78, 0.56), Color(0.95, 0.78, 0.3), 0.02, 0.5,
		Color(1.0, 0.96, 0.84), Color(0.93, 0.88, 0.72), 0.014, 1.0, 0)
	_diploma.add_child(frame)
	# Tailles calculées pour que chaque ligne tienne dans le cadre de 0,78 m (largeur utile ~0,62 m).
	var lines := [
		["DIPLÔME D'INGÉNIEUR", 0.19, 0.00112, Color(0.5, 0.08, 0.1)],
		["IMT Nord Europe", 0.1, 0.00145, Color(0.1, 0.12, 0.35)],
		["décerné à ce(tte) brillant(e)", -0.01, 0.0009, Color(0.15, 0.15, 0.18)],
		["joueur·se pour avoir tenu", -0.075, 0.0009, Color(0.15, 0.15, 0.18)],
		["4 secondes sur la gâchette.", -0.14, 0.0009, Color(0.15, 0.15, 0.18)],
		["Félicitations !", -0.205, 0.0011, Color(0.5, 0.08, 0.1)],
	]
	for spec in lines:
		var label := Label3D.new()
		label.text = spec[0]
		label.font = LobbyButton.bold_font()
		label.font_size = 48
		label.pixel_size = spec[2]
		label.modulate = spec[3]
		label.outline_size = 0
		label.shaded = false
		label.double_sided = true
		label.position = Vector3(0.0, spec[1], 0.012)
		label.render_priority = 3
		_diploma.add_child(label)
	var seal := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.04
	sm.bottom_radius = 0.04
	sm.height = 0.004
	seal.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.75, 0.08, 0.1)
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	seal.material_override = smat
	seal.rotation_degrees.x = 90.0
	seal.position = Vector3(0.29, -0.22, 0.014)
	_diploma.add_child(seal)
	_diploma.scale = Vector3(0.05, 0.05, 0.05)
	var tw := _diploma.create_tween()
	tw.tween_property(_diploma, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var ding := AudioStreamPlayer3D.new()
	ding.stream = Sfx.coins()
	ding.volume_db = 2.0
	host.add_child(ding)
	ding.global_position = _diploma.global_position
	ding.play()
	ding.finished.connect(ding.queue_free)
	_foam_confetti(host, _diploma.global_position)
	_haptic(left, 0.6, 0.2)
	_haptic(right, 0.6, 0.2)


func _foam_confetti(host: Node, pos: Vector3) -> void:
	var c := CPUParticles3D.new()
	c.one_shot = true
	c.emitting = true
	c.amount = 70
	c.lifetime = 2.4
	c.explosiveness = 0.9
	c.direction = Vector3(0, 1, 0)
	c.spread = 80.0
	c.initial_velocity_min = 1.0
	c.initial_velocity_max = 2.6
	c.gravity = Vector3(0, -2.0, 0)
	c.local_coords = false
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.03)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat
	c.mesh = quad
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 0.3, 0.4), Color(0.3, 0.8, 1), Color(1, 0.85, 0.2), Color(0.5, 1, 0.5)])
	grad.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	c.color_initial_ramp = grad
	host.add_child(c)
	c.global_position = pos + Vector3(0, 0.3, 0)
	get_tree().create_timer(3.5).timeout.connect(c.queue_free)


func _close_diploma() -> void:
	if is_instance_valid(_diploma):
		var d := _diploma
		var tw := d.create_tween()
		tw.tween_property(d, "scale", Vector3.ZERO, 0.4)
		tw.tween_callback(d.queue_free)
	if is_instance_valid(_egg):
		_egg.queue_free()
	_egg = null
	_diploma = null
	state = State.IDLE # on peut recommencer


func _haptic(hand: Node3D, amplitude: float, duration: float) -> void:
	var main := get_tree().get_first_node_in_group("main") if get_tree() != null else null
	if main != null and main.has_method(&"pulse_haptics") and hand is XRController3D:
		main.pulse_haptics(amplitude, duration, hand)
