class_name LobbyComputer
extends Area3D
## Ordinateur du lobby : survol au rayon VR, puis gâchette pour lancer le jeu.

signal start_requested

@onready var play_prompt: Label3D = $PlayPrompt
@onready var screen_highlight: MeshInstance3D = $ScreenHighlight
@onready var screen_model: Node3D = $ScreenModel
@onready var screen_panel: MeshInstance3D = $ScreenPanel
@onready var screen_text: Label3D = $ScreenText

var _activated := false


func _ready() -> void:
	_layout_screen()
	play_prompt.visible = false
	screen_highlight.visible = false


## Ancre les textes sur le moniteur réel, même après édition du lobby.
func _layout_screen() -> void:
	var bounds := _world_bounds(screen_model)
	var normal: Vector3 = screen_model.global_transform.basis.z
	normal.y = 0.0
	normal = normal.normalized()
	var depth := absf(normal.x) * bounds.size.x + absf(normal.z) * bounds.size.z
	var front_center := bounds.get_center() + normal * (depth * 0.5)
	for item in [screen_panel, screen_highlight, screen_text, play_prompt]:
		item.global_rotation = screen_model.global_rotation
	screen_panel.global_position = front_center + normal * 0.006
	screen_highlight.global_position = front_center + normal * 0.010
	screen_text.global_position = front_center + normal * 0.014
	play_prompt.global_position = front_center + normal * 0.04 + Vector3(0.0, bounds.size.y * 0.5 + 0.12, 0.0)


func _world_bounds(node: Node3D) -> AABB:
	var minimum := Vector3(1e9, 1e9, 1e9)
	var maximum := Vector3(-1e9, -1e9, -1e9)
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D and current.mesh != null:
			var local_box: AABB = current.mesh.get_aabb()
			var world_transform: Transform3D = current.global_transform
			for x in [local_box.position.x, local_box.end.x]:
				for y in [local_box.position.y, local_box.end.y]:
					for z in [local_box.position.z, local_box.end.z]:
						var point: Vector3 = world_transform * Vector3(x, y, z)
						minimum = Vector3(minf(minimum.x, point.x), minf(minimum.y, point.y), minf(minimum.z, point.z))
						maximum = Vector3(maxf(maximum.x, point.x), maxf(maximum.y, point.y), maxf(maximum.z, point.z))
		for child in current.get_children():
			stack.append(child)
	return AABB(minimum, maximum - minimum)


func on_pointed() -> void:
	if _activated:
		return
	play_prompt.visible = true
	screen_highlight.visible = true


func on_unpointed() -> void:
	if _activated:
		return
	play_prompt.visible = false
	screen_highlight.visible = false


## Main transmet toujours la clé tenue (nulle ici) aux objets interactifs.
func interact(_holding_key: Node3D = null) -> void:
	if _activated:
		return
	_activated = true
	play_prompt.text = "CHARGEMENT..."
	play_prompt.visible = true
	screen_highlight.visible = true
	start_requested.emit()