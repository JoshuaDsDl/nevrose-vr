class_name InteractiveContainer
extends Node3D
## Conteneur interactif (GDD §5.1/§5.6) : tiroir qui glisse ou porte de placard
## qui pivote sur charnière. Round 2 : système de verrous (clé / force).

enum Mode { SLIDE, ROTATE }
enum LockType { NONE, KEY, FORCEABLE }

const OPEN_TIME := 0.35
const FORCE_HITS_TO_BREAK := 3
const FORCE_NOISE_LEVEL := 0.8 ## 0.0..1.0 — attire les mimics

const KEY_USE_RADIUS := 1.2 ## Distance max clé→conteneur pour déverrouiller

signal lock_broken(container: Node3D, noise: float) ## Émis quand force-ouverte
signal unlocked_by_key(container: Node3D) ## Émis quand clé utilisée
signal force_progress(container: Node3D, hits: int, required: int)
signal key_required(container: Node3D)

var mode: Mode = Mode.SLIDE
var slide_axis := Vector3.BACK
var open_distance := 0.45
var rotate_angle := 115.0

var lock_type: LockType = LockType.NONE
var required_key: Node3D = null ## Référence à l'objet clé spécifique
var is_locked := false
var force_hits := 0
var is_open := false
var _tween: Tween
var _closed_pos: Vector3
var _closed_rot_y: float
var area: Area3D
var front_mesh: MeshInstance3D
var dose: Node3D = null
var content_offset := Vector3.ZERO
var _mat_normal: Material
var _mat_hover: Material
var _mat_locked: Material ## Surbrillance rouge (verrouillé)


func _init(p_mode: Mode = Mode.SLIDE, p_axis: Vector3 = Vector3.BACK,
			p_dist: float = 0.45, p_angle: float = 115.0,
			p_lock: LockType = LockType.NONE) -> void:
	mode = p_mode
	slide_axis = p_axis
	open_distance = p_dist
	rotate_angle = p_angle
	lock_type = p_lock
	is_locked = (p_lock != LockType.NONE)


func _ready() -> void:
	_closed_pos = position
	_closed_rot_y = rotation.y
	if is_locked:
		_mat_locked = _make_locked_mat()
		if front_mesh:
			front_mesh.material_overlay = _mat_locked


func _make_locked_mat() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.2, 0.1, 0.4)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## Raycast (main.gd) : la zone d'interaction est l'Area3D enfant.
func on_pointed(holding_key: Node3D = null) -> void:
	if front_mesh:
		if is_locked and _mat_locked:
			# Si le joueur tient la bonne clé → surbrillance verte
			if holding_key == required_key:
				front_mesh.material_overlay = _make_unlock_mat()
			else:
				front_mesh.material_overlay = _mat_locked
		elif _mat_hover:
			front_mesh.material_overlay = _mat_hover


func on_unpointed() -> void:
	if front_mesh:
		front_mesh.material_overlay = _mat_normal


## Interaction principale (grip / trigger).
## Si verrouillé → tentative de force-ouverture ou déverrouillage par clé.
## Si ouvert → open/close toggle.
func interact(holding_key: Node3D = null) -> void:
	if is_locked:
		_try_unlock(holding_key)
		return
	# Non verrouillé : open/close normal
	if _tween and _tween.is_valid():
		return
	is_open = not is_open
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if mode == Mode.SLIDE:
		var target := _closed_pos + slide_axis * (open_distance if is_open else 0.0)
		_tween.tween_property(self, "position", target, OPEN_TIME)
	else:
		var target_y := _closed_rot_y + deg_to_rad(rotate_angle if is_open else 0.0)
		_tween.tween_property(self, "rotation:y", target_y, OPEN_TIME)
	if dose:
		if is_open:
			_reveal_dose()
		else:
			_hide_dose()


## Fermeture déterministe pour le restart : aucune dépendance à un tween actif.
func close_now() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	is_open = false
	position = _closed_pos
	rotation.y = _closed_rot_y
	_hide_dose()


func _try_unlock(holding_key: Node3D) -> void:
	# Clé correcte ? (doit être fournie ET correspondre à la clé attendue)
	if lock_type == LockType.KEY and holding_key != null and holding_key == required_key:
		_unlock()
		unlocked_by_key.emit(self)
		return
	# Pas de clé → force (si forceable)
	if lock_type == LockType.FORCEABLE:
		force_hits += 1
		force_progress.emit(self, force_hits, FORCE_HITS_TO_BREAK)
		if force_hits >= FORCE_HITS_TO_BREAK:
			_unlock()
			lock_broken.emit(self, FORCE_NOISE_LEVEL)
		return
	# KEY lock sans clé → feedback visuel (flash rouge)
	key_required.emit(self)
	_flash_locked()


func _unlock() -> void:
	is_locked = false
	if front_mesh:
		front_mesh.material_overlay = _mat_normal
	is_open = false
	interact()


func _flash_locked() -> void:
	# Feedback visuel : flash rouge sur la face verrouillée.
	# On tween la couleur du matériau (pas self_modulate — inexistant sur
	# MeshInstance3D) pour signaler "verrouillé, il faut une clé".
	if not front_mesh or not _mat_locked:
		return
	var mat := front_mesh.material_overlay as StandardMaterial3D
	if mat == null:
		return
	var base: Color = mat.albedo_color
	var flash := base
	flash.a = 0.9
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color", flash, 0.05)
	tw.tween_property(mat, "albedo_color", base, 0.25)


func _make_unlock_mat() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.9, 0.2, 0.4)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _reveal_dose() -> void:
	if not dose:
		return
	dose.visible = true
	if dose is Area3D:
		dose.set_deferred("monitoring", true)
		dose.set_deferred("monitorable", true)


func _hide_dose() -> void:
	if not dose:
		return
	dose.visible = false
	if dose is Area3D:
		dose.set_deferred("monitoring", false)
		dose.set_deferred("monitorable", false)
