class_name PlayerProfile
extends Node
## Profil du joueur : tokens gagnés et décorations achetées (sauvegarde locale).
##
## Les tokens sont gagnés dans les deux modes ; ils se dépensent dans la boutique
## du lobby (voir DecorCatalog).

signal tokens_changed(total: int)
signal decor_bought(id: String)

const SAVE_PATH := "user://profile.cfg"

const START_FOLLOWERS := 37 ## le compte démarre petit : « dont ta mère »

var tokens := 0
var owned: Array[String] = []
var followers := START_FOLLOWERS ## mode Réels : l'audience s'accumule d'une session à l'autre
var reels_posted := 0
var best_views := 0
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


## Un réel jugé : l'audience grandit, le meilleur score est retenu.
func register_reel(views: int, followers_gained: int) -> void:
	reels_posted += 1
	best_views = maxi(best_views, views)
	followers += maxi(followers_gained, 0)
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
	cfg.set_value("profile", "followers", followers)
	cfg.set_value("profile", "reels_posted", reels_posted)
	cfg.set_value("profile", "best_views", best_views)
	cfg.save(SAVE_PATH)


func load_profile() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	tokens = int(cfg.get_value("profile", "tokens", 0))
	followers = int(cfg.get_value("profile", "followers", START_FOLLOWERS))
	reels_posted = int(cfg.get_value("profile", "reels_posted", 0))
	best_views = int(cfg.get_value("profile", "best_views", 0))
	owned.clear()
	for id in cfg.get_value("profile", "owned", []):
		owned.append(String(id))
