class_name LobbyWorld
extends Node3D
## Salon d'accueil : aucune mécanique de folie, seulement le tutoriel et le départ.

signal play_requested

@onready var computer: LobbyComputer = $Computer


func _ready() -> void:
	computer.start_requested.connect(_on_computer_start)


func _on_computer_start() -> void:
	play_requested.emit()