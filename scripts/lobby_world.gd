class_name LobbyWorld
extends Node3D
## Salon d'accueil : aucune mécanique de folie. Deux grandes cartes face au joueur
## pour choisir le mode (viser + gâchette lance la partie), une boutique de
## décorations derrière lui, et l'ordinateur qui affiche les tokens.

signal play_requested(mode: int)

const MODE_RESIST := 1 # = Main.Mode.RESIST
const MODE_HUNT := 2 # = Main.Mode.HUNT

@onready var computer: LobbyComputer = $Computer

var profile: PlayerProfile = null
var card_resist: LobbyButton
var card_hunt: LobbyButton
var shop_cards: Dictionary = {} # id -> LobbyButton
var interactables: Array[Node3D] = []
var tokens_label: Label3D
var _starting := false


func _ready() -> void:
	computer.start_requested.connect(_refresh_tokens)
	_build_mode_cards()


## Appelé par Main : branche le profil (tokens, achats) et construit la boutique.
func setup(p_profile: PlayerProfile) -> void:
	profile = p_profile
	profile.tokens_changed.connect(func(_t: int) -> void: _refresh_tokens())
	_build_shop()
	_refresh_tokens()
	var mission := get_node_or_null("Tutorial/MissionPanel/Text") as Label3D
	if mission != null:
		mission.text = "NÉVROSE\nChoisis ton mode en visant une carte.\nGâchette = jouer.\nLes tokens gagnés s'achètent derrière toi."


# ---------------------------------------------------------------------------
# Choix du mode : deux cartes géantes devant le joueur
# ---------------------------------------------------------------------------
func _build_mode_cards() -> void:
	var holder := Node3D.new()
	holder.name = "Modes"
	add_child(holder)

	card_resist = LobbyButton.new()
	card_resist.name = "CarteResistance"
	holder.add_child(card_resist)
	card_resist.setup(Vector2(0.8, 1.0), "RÉSISTER",
		"Tu es déjà fou. Les voix montent.\nTrouve les pilules cyan avant d'être assimilé.\nPlus tu tiens, plus tu gagnes de tokens.",
		Color(0.3, 0.95, 0.85), 0.0027, 0.0015)
	card_resist.position = Vector3(-0.45, 1.45, -0.2)
	card_resist.rotation.y = deg_to_rad(14.0)
	card_resist.set_state("◆ MODE RÉSISTANCE", Color(0.3, 0.95, 0.85), true)
	card_resist.pressed.connect(func() -> void: _choose(MODE_RESIST))

	card_hunt = LobbyButton.new()
	card_hunt.name = "CarteChasse"
	holder.add_child(card_hunt)
	card_hunt.setup(Vector2(0.8, 1.0), "CHASSER",
		"Ça cogne dans les murs et le plafond.\nDéfonce où ça cogne pour trouver le monstre.\nTu gagnes des tokens… et un appart en ruines.",
		Color(1.0, 0.3, 0.25), 0.0027, 0.0015)
	card_hunt.position = Vector3(1.65, 1.45, -0.2)
	card_hunt.rotation.y = deg_to_rad(-14.0)
	card_hunt.set_state("◆ MODE CHASSE", Color(1.0, 0.3, 0.25), true)
	card_hunt.pressed.connect(func() -> void: _choose(MODE_HUNT))

	# Petits pieds lumineux au sol pour ancrer les cartes.
	for card in [card_resist, card_hunt]:
		interactables.append(card)
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.02
		pm.bottom_radius = 0.02
		pm.height = (card as Node3D).position.y - 0.52
		post.mesh = pm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.12, 0.12, 0.14)
		post.material_override = mat
		post.position = Vector3((card as Node3D).position.x, pm.height * 0.5, (card as Node3D).position.z - 0.02)
		holder.add_child(post)

	tokens_label = Label3D.new()
	tokens_label.name = "Tokens"
	tokens_label.pixel_size = 0.003
	tokens_label.font_size = 56
	tokens_label.outline_size = 8
	tokens_label.modulate = Color(1.0, 0.85, 0.35)
	tokens_label.position = Vector3(0.6, 2.2, -0.2)
	holder.add_child(tokens_label)


func _choose(p_mode: int) -> void:
	if _starting:
		return
	_starting = true
	card_resist.set_state("CHARGEMENT…", card_resist.accent, false)
	card_hunt.set_state("CHARGEMENT…", card_hunt.accent, false)
	play_requested.emit(p_mode)


# ---------------------------------------------------------------------------
# Boutique : mur sud, derrière le joueur
# ---------------------------------------------------------------------------
func _build_shop() -> void:
	var board := Node3D.new()
	board.name = "Boutique"
	board.position = Vector3(-0.2, 0.0, 2.5)
	board.rotation.y = PI # regarde vers -Z, donc vers le salon
	add_child(board)

	var header := Label3D.new()
	header.text = "BOUTIQUE — décorations de l'appartement"
	header.pixel_size = 0.0035
	header.font_size = 48
	header.outline_size = 6
	header.modulate = Color(1.0, 0.85, 0.35)
	header.position = Vector3(0.0, 2.52, 0.01)
	board.add_child(header)

	var cols := 4
	for i in DecorCatalog.ITEMS.size():
		var item: Dictionary = DecorCatalog.ITEMS[i]
		var card := LobbyButton.new()
		card.name = "Achat_%s" % item["id"]
		board.add_child(card)
		card.setup(Vector2(0.62, 0.46), String(item["name"]), "", Color(0.9, 0.75, 0.3), 0.0021, 0.0015)
		card.title_label.position.y = 0.08
		card.title_label.font_size = 38
		card.tag_label.font_size = 30
		var col := i % cols
		var row := i / cols
		card.position = Vector3((col - (cols - 1) * 0.5) * 0.7, 2.05 - row * 0.54, 0.02)
		card.pressed.connect(_on_shop_pressed.bind(String(item["id"])))
		shop_cards[item["id"]] = card
		interactables.append(card)


func _on_shop_pressed(id: String) -> void:
	if profile != null and profile.buy(id):
		_refresh_tokens()


func _refresh_tokens() -> void:
	if profile == null:
		return
	var txt := "◆ %d tokens" % profile.tokens
	if tokens_label != null:
		tokens_label.text = txt
	computer.play_prompt.text = "Ton solde de tokens"
	var screen := get_node_or_null("Computer/ScreenText") as Label3D
	if screen != null:
		screen.text = "NÉVROSE\n%d TOKENS" % profile.tokens
	for id in shop_cards:
		var card: LobbyButton = shop_cards[id]
		var item := DecorCatalog.get_item(id)
		var price := int(item["price"])
		if profile.owns(id):
			card.set_state("✔ POSSÉDÉ", Color(0.3, 0.95, 0.85), false)
		elif profile.tokens >= price:
			card.set_state("ACHETER %d ◆" % price, Color(0.5, 1.0, 0.4), true)
		else:
			card.set_state("%d ◆" % price, Color(0.85, 0.3, 0.25), false)
