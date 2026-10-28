class_name GameLogger
extends Node
## Journal de session horodaté en .txt — diagnostique de première main, pensé
## pour l'écran noir / les plantages sur Meta Quest 2.
##
## Chemins :
##   - Android (Quest 2) : /sdcard/Android/data/com.noirlab.nevrose/files/logs/nevrose.log
##     → dossier externe privé de l'app : aucune permission requise, récupérable
##       via `adb pull` sans root.
##   - Bureau / tests headless : user://logs/nevrose.log
##
## Chaque ligne est aussi renvoyée vers print() (donc vers godot.log et logcat).

const PKG := "com.noirlab.nevrose"
const FILE_NAME := "nevrose.log"
const ANDROID_DIR := "/sdcard/Android/data/com.noirlab.nevrose/files/logs"
const DESKTOP_DIR := "user://logs"

var _file: FileAccess
var path := ""


func _ready() -> void:
	var dir := ANDROID_DIR if OS.get_name() == "Android" else ProjectSettings.globalize_path(DESKTOP_DIR)
	path = dir + "/" + FILE_NAME
	DirAccess.make_dir_recursive_absolute(dir)
	_file = FileAccess.open(path, FileAccess.WRITE) # une session = un fichier
	if _file == null:
		push_error("[GameLogger] ouverture impossible : %s (err %d)" % [path, FileAccess.get_open_error()])
		return
	log_line("BOOT", "=== session %s ===" % Time.get_datetime_string_from_system())
	log_line("BOOT", "moteur=%s OS=%s" % [Engine.get_version_info().get("string", "?"), OS.get_name()])
	log_line("BOOT", "renderer=%s | display=%s" % [
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"),
		DisplayServer.get_name()])
	log_line("BOOT", "viewport.use_xr=%s" % str(get_viewport().use_xr))


## Écrit une ligne horodatée `[HH:MM:SS] [CAT] message` dans le fichier + stdout.
## Nommé log_line (et pas log) : `log()` existe déjà en global math GDScript.
func log_line(cat: String, msg: String) -> void:
	var line := "[%s] [%-5s] %s" % [Time.get_time_string_from_system(), cat, msg]
	print(line)
	if _file:
		_file.store_line(line)
		_file.flush()


func _exit_tree() -> void:
	if _file:
		log_line("BOOT", "fin de session")
		_file.close()
		_file = null
