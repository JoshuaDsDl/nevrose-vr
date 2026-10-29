class_name PlayerProfile
extends Node
## Profil du joueur : tokens gagnés et décorations achetées (sauvegarde locale).
##
## Les tokens sont gagnés dans les deux modes ; ils se dépensent dans la boutique
## du lobby (voir DecorCatalog).

signal tokens_changed(total: int)
signal decor_bought(id: String)

const SAVE_PATH := "user://profile.cfg"

var tokens := 0
var owned: Array[String] = []
## Désactivé en headless : les tests ne doivent pas toucher au vrai profil.
var persist := true


func _ready() -> void:
	persist = DisplayServer.get_name() != "headless"
	load_profile()


func add_tokens(amount: int) -> void:
	if amount <= 0:
		return
	tokens += amount
	tokens_changed.emit(tokens)
	save_profile()


func owns(id: String) -> bool:
	return id in owned


## Achète une décoration : faux si déjà possédée, inconnue ou trop chère.
func buy(id: String) -> bool:
	var item := DecorCatalog.get_item(id)
	if item.is_empty() or owns(id) or tokens < int(item["price"]):
		return false
	tokens -= int(item["price"])
	owned.append(id)
	tokens_changed.emit(tokens)
	decor_bought.emit(id)
	save_profile()
	return true


func save_profile() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "tokens", tokens)
	cfg.set_value("profile", "owned", owned)
	cfg.save(SAVE_PATH)


func load_profile() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	tokens = int(cfg.get_value("profile", "tokens", 0))
	owned.clear()
	for id in cfg.get_value("profile", "owned", []):
		owned.append(String(id))
