class_name LlmClient
extends Node
## Client du LLM (Qwen 3.8 27B servi par llama.cpp sur imt-hpc, joint via Tailscale).
##
## Le serveur génère lentement (~2 tokens/s) : la réponse est donc lue en flux (SSE)
## et chaque ligne complète est émise dès qu'elle arrive, pour que le jeu réagisse
## au fur et à mesure (compteurs, commentaires qui tombent un par un) au lieu
## d'attendre la fin. Sans réseau, `finished` arrive vite avec ok = false et le jeu
## bascule sur son juge local (voir ReelData.heuristic).
##
## Fournisseur : voir resolve_config (OpenRouter si une clé est présente).

signal line_received(text: String)
signal finished(ok: bool, full_text: String)

const DEFAULT_URL := "http://100.113.199.15:8081"
const CONFIG_PATH := "user://llm.cfg"
const LOCAL_CONFIG_PATH := "res://llm.local.cfg"
const OPENROUTER_MODEL := "google/gemini-2.5-flash-lite" ## économique, vision, rapide
const CONNECT_TIMEOUT := 8.0
const FIRST_TOKEN_TIMEOUT := 75.0 ## le prompt (image comprise) doit être digéré
const TOTAL_TIMEOUT := 200.0

## Les tests mettent ceci à true : aucun appel réseau.
static var force_offline := false

var busy := false
var last_error := ""
var provider_name := ""

var _http := HTTPClient.new()
var _body := ""
var _path := ""
var _headers: PackedStringArray = []
var _sent := false
var _raw := PackedByteArray()
var _line_buffer := ""
var _full := ""
var _elapsed := 0.0
var _got_token := false
var _response_code := 0


## Configuration du fournisseur. Priorité : clé OpenRouter (variable d'environnement
## OPENROUTER_API_KEY, ou « key » dans llm.local.cfg / user://llm.cfg), sinon le
## serveur local llama.cpp. llm.local.cfg est ignoré par git : la clé n'est jamais commitée.
static func resolve_config() -> Dictionary:
	var key := OS.get_environment("OPENROUTER_API_KEY")
	var model := OPENROUTER_MODEL
	var url := OS.get_environment("NEVROSE_LLM_URL")
	for path in [LOCAL_CONFIG_PATH, CONFIG_PATH]:
		var cfg := ConfigFile.new()
		if cfg.load(path) == OK:
			if key == "":
				key = String(cfg.get_value("llm", "key", ""))
			model = String(cfg.get_value("llm", "model", model))
			if url == "":
				url = String(cfg.get_value("llm", "url", ""))
	if key != "" and url == "":
		return {"name": "OpenRouter · " + model, "host": "openrouter.ai", "port": 443, "tls": true,
			"path": "/api/v1/chat/completions", "key": key, "model": model}
	if url == "":
		url = DEFAULT_URL
	var clean := url.trim_prefix("http://")
	return {"name": "Qwen3.8-27B", "host": clean.get_slice(":", 0),
		"port": int(clean.get_slice(":", 1)) if clean.contains(":") else 80, "tls": false,
		"path": "/v1/chat/completions", "key": key, "model": ""}


static func is_available() -> bool:
	return not force_offline and OS.get_environment("NEVROSE_OFFLINE") != "1"


## Message utilisateur avec image : format « vision » de l'API OpenAI.
static func image_content(text: String, jpeg: PackedByteArray) -> Array:
	return [
		{"type": "text", "text": text},
		{"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + Marshalls.raw_to_base64(jpeg)}},
	]


func _init() -> void:
	set_process(false)


## Lance une requête en flux. Une seule à la fois par client.
func ask(messages: Array, max_tokens := 200, temperature := 0.9) -> void:
	if busy:
		push_warning("LlmClient: requête déjà en cours")
		return
	_reset()
	busy = true
	if not is_available():
		_fail("hors ligne")
		return
	var conf := resolve_config()
	provider_name = conf["name"]
	var payload := {
		"messages": messages,
		"stream": true,
		"max_tokens": max_tokens,
		"temperature": temperature,
	}
	if conf["model"] != "":
		payload["model"] = conf["model"]
	else:
		payload["cache_prompt"] = true
		payload["chat_template_kwargs"] = {"enable_thinking": false}
	_body = JSON.stringify(payload)
	_path = conf["path"]
	_headers = ["Content-Type: application/json", "Accept: text/event-stream"]
	if conf["key"] != "":
		_headers.append("Authorization: Bearer " + String(conf["key"]))
		_headers.append("X-Title: NEVROSE")
	var err := _http.connect_to_host(conf["host"], conf["port"], TLSOptions.client() if conf["tls"] else null)
	if err != OK:
		_fail("connexion impossible (%d)" % err)
		return
	set_process(true)


func cancel() -> void:
	if busy:
		busy = false
		set_process(false)
		_http.close()


func _reset() -> void:
	_http.close()
	_sent = false
	_raw = PackedByteArray()
	_line_buffer = ""
	_full = ""
	_elapsed = 0.0
	_got_token = false
	_response_code = 0
	last_error = ""


func _process(delta: float) -> void:
	if not busy:
		set_process(false)
		return
	_elapsed += delta
	_http.poll()
	match _http.get_status():
		HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT, \
		HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			# llama.cpp ferme la connexion une fois le flux terminé : ce n'est pas une panne.
			if _got_token:
				_finish_stream()
			else:
				_fail("serveur injoignable")
			return
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING:
			if _elapsed > CONNECT_TIMEOUT:
				_fail("délai de connexion dépassé")
				return
		HTTPClient.STATUS_CONNECTED:
			if not _sent:
				_sent = true
				if _http.request(HTTPClient.METHOD_POST, _path, _headers, _body) != OK:
					_fail("envoi impossible")
					return
			else:
				_finish_stream()
				return
		HTTPClient.STATUS_BODY:
			_response_code = _http.get_response_code()
			var chunk := _http.read_response_body_chunk()
			if chunk.size() > 0:
				_raw.append_array(chunk)
				_consume_raw()
		HTTPClient.STATUS_DISCONNECTED:
			if _sent:
				_finish_stream()
				return
	if not _got_token and _elapsed > FIRST_TOKEN_TIMEOUT:
		_fail("le serveur ne répond pas")
	elif _elapsed > TOTAL_TIMEOUT:
		_finish_stream()


## Découpe le flux brut ligne par ligne (en octets : un caractère UTF-8 peut être
## coupé entre deux paquets) et lit les évènements SSE `data: {...}`.
func _consume_raw() -> void:
	while true:
		var nl := _raw.find(10)
		if nl < 0:
			return
		var raw_line := _raw.slice(0, nl).get_string_from_utf8().strip_edges()
		_raw = _raw.slice(nl + 1)
		if not raw_line.begins_with("data:"):
			continue
		var payload := raw_line.substr(5).strip_edges()
		if payload == "[DONE]" or payload == "":
			continue
		var parsed: Variant = JSON.parse_string(payload)
		if not (parsed is Dictionary):
			continue
		var choices: Array = parsed.get("choices", [])
		if choices.is_empty():
			continue
		var delta: Dictionary = choices[0].get("delta", {})
		var piece: Variant = delta.get("content", null)
		if piece is String and piece != "":
			_got_token = true
			_push_text(piece)


func _push_text(piece: String) -> void:
	_full += piece
	_line_buffer += piece
	while _line_buffer.contains("\n"):
		var idx := _line_buffer.find("\n")
		var line := _line_buffer.substr(0, idx).strip_edges()
		_line_buffer = _line_buffer.substr(idx + 1)
		if line != "":
			line_received.emit(line)


func _finish_stream() -> void:
	if not busy:
		return
	_consume_raw()
	var tail := _line_buffer.strip_edges()
	_line_buffer = ""
	if tail != "":
		line_received.emit(tail)
	busy = false
	set_process(false)
	var ok := _got_token and (_response_code == 0 or _response_code == 200)
	if not ok and last_error == "":
		last_error = "réponse vide (HTTP %d)" % _response_code
	_http.close()
	finished.emit(ok, _full)


func _fail(reason: String) -> void:
	last_error = reason
	busy = false
	set_process(false)
	_http.close()
	finished.emit(false, _full)
