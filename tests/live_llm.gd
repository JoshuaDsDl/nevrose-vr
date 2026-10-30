extends SceneTree
## Essai manuel contre le LLM (OpenRouter ou serveur local) : jugement d'un
## réel, avec l'image jointe si un PNG est donné en argument (--image=chemin).
##   Godot --headless --path . --script res://tests/live_llm.gd
## Pas dans la suite automatique : dépend du réseau et du serveur.

func _initialize() -> void:
	print("LLM : ", LlmClient.resolve_config()["name"])
	var client := LlmClient.new()
	root.add_child(client)
	var t0 := Time.get_ticks_msec()
	client.line_received.connect(func(l: String) -> void:
		print("  [%5.1fs] %s" % [(Time.get_ticks_msec() - t0) / 1000.0, l]))

	var res: Array = []
	var jpeg := PackedByteArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--image="):
			var img := Image.load_from_file(a.trim_prefix("--image="))
			if img != null:
				img.resize(224, 392, Image.INTERPOLATE_BILINEAR)
				img.convert(Image.FORMAT_RGB8)
				jpeg = img.save_jpg_to_buffer(0.82)
				print("image jointe : %d octets" % jpeg.size())
	var ctx := {
		"premise": ReelData.local_premise(0), "tone": ReelData.TONES[1],
		"voice": {"mic": true, "duration": 22.0, "speak_ratio": 0.78, "avg_db": -22.0, "peak_db": -11.0, "variation": 6.5, "longest_pause": 1.6, "bursts": 9},
		"followers": 37, "previous": [], "decor": ["Mayo Zedong", "Lampadaire"],
	}
	print("--- jugement ---")
	t0 = Time.get_ticks_msec()
	var result := {}
	client.line_received.connect(func(l: String) -> void: ReelData.parse_line(result, l))
	client.ask(ReelData.judge_messages(ctx, jpeg), 320, 0.9)
	res = await client.finished
	print("jugement : ok=%s (%s) en %.1f s" % [res[0], client.last_error, (Time.get_ticks_msec() - t0) / 1000.0])
	print("résultat lu : ", result)
	ReelData.fill_missing(result, ctx, RandomNumberGenerator.new())
	print("tokens : ", ReelData.compute_tokens(result))
	quit()
