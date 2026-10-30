extends SceneTree
## Tests du mode Réels : lecture des réponses du jury, tokens, juge local de secours,
## puis une séance complète hors ligne (choix de l'idée, prise, jugement, fin).
##   Godot --headless --path . --script res://tests/test_reels.gd

var _failures := 0


func _assert(cond: bool, label: String) -> void:
	if cond:
		print("  [OK] ", label)
	else:
		_failures += 1
		printerr("  [ECHEC] ", label)


func _initialize() -> void:
	print("=== TEST RÉELS ===")
	LlmClient.force_offline = true

	# --- Lecture des réponses du jury ---
	var r := {}
	_assert(ReelData.parse_line(r, "VUES: 12 400") == "views" and r["views"] == 12400, "jury : « 12 400 » = 12400")
	_assert(ReelData.parse_line(r, "LIKES: 1,2k") == "likes" and r["likes"] == 1200, "jury : « 1,2k » = 1200")
	_assert(ReelData.parse_line(r, "**COMMENTAIRES:** 45") == "comments" and r["comments"] == 45, "jury : gras markdown toléré")
	_assert(ReelData.parse_line(r, "- PARTAGES: 30") == "shares" and r["shares"] == 30, "jury : puce tolérée")
	_assert(ReelData.parse_line(r, "ABONNÉS: 120") == "followers" and r["followers"] == 120, "jury : ABONNÉS avec accent")
	_assert(ReelData.parse_line(r, "NOTE: 7.5") == "score" and is_equal_approx(r["score"], 7.5), "jury : note décimale")
	_assert(ReelData.parse_line(r, "TITRE: « Le lézard du Wi-Fi »") == "title" and r["title"] == "Le lézard du Wi-Fi", "jury : titre sans guillemets")
	_assert(ReelData.parse_line(r, "VERDICT: Mou, mais sincère.") == "verdict", "jury : verdict")
	_assert(ReelData.parse_line(r, "C: @dr.complot | J'ai tout compris") == "comment" and r["comment_list"][0]["user"] == "dr.complot", "jury : commentaire")
	_assert(ReelData.parse_line(r, "bla bla sans clé") == "", "jury : ligne parasite ignorée")
	_assert(ReelData.parse_line(r, "VUES: beaucoup") == "", "jury : nombre absent ignoré")
	_assert(ReelData.parse_number("1.2M") == 1200000.0, "nombre : 1.2M")
	_assert(ReelData.format_count(12400) == "12,4 k" and ReelData.format_count(1250000) == "1,25 M" and ReelData.format_count(87) == "87", "affichage des compteurs")
	# --- Les 30 textes écrits à la main ---
	_assert(ReelData.SCRIPTS.size() >= 30, "idées : au moins 30 textes écrits à la main (%d)" % ReelData.SCRIPTS.size())
	var seen := {}
	for sc in ReelData.SCRIPTS:
		var title: String = sc["title"]
		_assert(title.length() <= 26 and not seen.has(title), "idée « %s » : titre court et unique" % title) if (title.length() > 26 or seen.has(title)) else null
		seen[title] = true
	_assert(ReelData.teaser(ReelData.SCRIPTS[0]["script"]).length() <= 100, "idée : accroche de carte courte")

	# --- Garde-fous et tokens ---
	var wild := {"views": 99999999, "likes": 99999999, "comments": 99999999, "shares": 99999999, "followers": 99999999, "score": 42}
	ReelData.sanitize(wild, 10)
	_assert(wild["views"] <= ReelData.MAX_VIEWS and wild["likes"] <= wild["views"] * 0.35, "garde-fous : chiffres délirants ramenés")
	_assert(wild["comments"] <= wild["likes"] and wild["score"] == 10.0, "garde-fous : commentaires et note bornés")
	var flop := {"views": 120, "likes": 3}
	var hit := {"views": 80000, "likes": 7000}
	_assert(ReelData.compute_tokens(hit) > ReelData.compute_tokens(flop) * 2, "tokens : un réel populaire rapporte bien plus")
	_assert(ReelData.compute_tokens(flop) >= 1, "tokens : même un flop rapporte au moins 1")
	_assert(ReelData.compute_tokens({"views": 0, "likes": 0}) == 1, "tokens : zéro vue = 1")

	# --- Juge local ---
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tone: Dictionary = ReelData.TONES[0]
	var premise: Dictionary = ReelData.local_premise(0)
	_assert(ReelData.SCRIPTS.size() >= 12, "idées locales : réserve de textes à lire (%d)" % ReelData.SCRIPTS.size())
	for i in ReelData.SCRIPTS.size():
		var n := ReelData.words(ReelData.SCRIPTS[i]["script"]).size()
		if n < 30 or n > 55:
			_assert(false, "idées locales : « %s » fait %d mots (30 à 55 attendus)" % [ReelData.SCRIPTS[i]["title"], n])
	_assert(ReelData.expected_duration(premise["script"]) > 8.0 and ReelData.expected_duration(premise["script"]) < 25.0, "texte : durée de lecture réaliste")
	var lazy := {"mic": true, "duration": 20.0, "speak_ratio": 0.08, "avg_db": -30.0, "peak_db": -20.0, "variation": 2.0, "longest_pause": 8.0, "bursts": 2}
	var lazy_total := 0.0
	var read_total := 0.0
	var read_voice := {"mic": true, "duration": 18.0, "speak_ratio": 0.85, "avg_db": -22.0, "peak_db": -12.0, "variation": 6.0, "longest_pause": 1.2, "bursts": 10}
	for i in 40:
		lazy_total += ReelData.heuristic({"premise": premise, "tone": ReelData.TONES[0], "voice": lazy, "followers": 37}, rng)["views"]
		read_total += ReelData.heuristic({"premise": premise, "tone": ReelData.TONES[0], "voice": read_voice, "followers": 37}, rng)["views"]
	_assert(read_total > lazy_total * 3.0, "juge local : lire le texte rapporte bien plus que se taire")
	var good_voice := {"mic": true, "duration": 24.0, "speak_ratio": 0.85, "avg_db": -18.0, "peak_db": -8.0, "variation": 8.0, "longest_pause": 1.0, "bursts": 12}
	var bad_voice := {"mic": true, "duration": 6.0, "speak_ratio": 0.1, "avg_db": -40.0, "peak_db": -34.0, "variation": 0.5, "longest_pause": 5.0, "bursts": 1}
	var total_good := 0.0
	var total_bad := 0.0
	for i in 40:
		total_good += ReelData.heuristic({"premise": premise, "tone": tone, "voice": good_voice, "followers": 37}, rng)["views"]
		total_bad += ReelData.heuristic({"premise": premise, "tone": tone, "voice": bad_voice, "followers": 37}, rng)["views"]
	_assert(total_good > total_bad * 3.0, "juge local : une belle performance fait plus de vues (%d vs %d)" % [total_good / 40, total_bad / 40])
	var local := ReelData.heuristic({"premise": premise, "tone": tone, "voice": good_voice, "followers": 37}, rng)
	_assert((local["comment_list"] as Array).size() == 5 and local["verdict"] != "", "juge local : verdict et 5 commentaires")
	var partial := {"views": 500}
	ReelData.fill_missing(partial, {"premise": premise, "tone": tone, "voice": good_voice, "followers": 37}, rng)
	_assert(partial["views"] == 500 and partial.has("verdict") and partial.has("title"), "réponse tronquée : complétée sans écraser le LLM")
	var msgs := ReelData.judge_messages({"premise": premise, "tone": tone, "voice": good_voice, "followers": 37, "previous": ["Un autre"], "decor": ["Mayo Zedong"]}, PackedByteArray())
	_assert(msgs.size() == 2 and (msgs[1]["content"] as String).contains("Mayo Zedong"), "prompt : le décor acheté est transmis au jury")
	_assert((msgs[1]["content"] as String).contains("Écoutez-moi bien") and (msgs[1]["content"] as String).contains("Lecture :"), "prompt : le texte et la durée de lecture sont transmis")
	var msgs_img := ReelData.judge_messages({"premise": premise, "tone": tone, "voice": good_voice, "followers": 37, "previous": [], "decor": []}, PackedByteArray([1, 2, 3]))
	_assert(msgs_img[1]["content"] is Array and msgs_img[1]["content"][1]["type"] == "image_url", "prompt : l'image part au format vision")

	# --- Client hors ligne : échec immédiat ---
	var client := LlmClient.new()
	root.add_child(client)
	var done := {"ok": true, "n": 0}
	client.finished.connect(func(ok: bool, _t: String) -> void:
		done["ok"] = ok
		done["n"] += 1)
	client.ask([{"role": "user", "content": "salut"}])
	_assert(done["n"] == 1 and not done["ok"], "client : hors ligne = échec immédiat, sans attente")
	client.queue_free()

	# --- Séance complète hors ligne ---
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.profile.persist = false
	var lobby: LobbyWorld = main.lobby
	_assert(lobby.card_reel != null, "lobby : carte du mode Réels")
	var cam_mask_before: int = main.xr_camera.cull_mask
	main._pointed = lobby.card_reel
	main.interact()
	for i in 8:
		await physics_frame
	_assert(main.mode == Main.Mode.REEL and main.reel != null and main.reel.started, "réels : mode actif et studio construit")
	var reel: ReelMode = main.reel
	_assert(reel.cam_vp != null and reel.monitor != null and reel.post != null, "réels : caméra, écran de retour et fiche créés")
	_assert((main.xr_camera.cull_mask & ReelMode.AVATAR_LAYER) == 0, "réels : l'avatar n'est visible que de la caméra du trépied")
	_assert(not main.creepy_voices.enabled and main.sanity == Main.START_SANITY, "réels : pas de voix de folie")
	_assert(reel.premises.size() == 3 and reel._premise_cards.size() == 3 and reel._tone_cards.size() == 4, "réels : 3 idées et 4 tons au tableau")
	_assert(main.apartment is StudioMap and main.apartment.get_node_or_null("Shell/Console") != null, "réels : tournage dans le studio dédié")
	_assert(String(reel.premises[0]["script"]) != "", "réels : chaque idée a son texte à lire")
	for card in reel._premise_cards:
		_assert(card.title_label.text.length() <= 26, "réels : titre de carte « %s » tient dans le panneau" % card.title_label.text)
	_assert(not reel.rec_button.enabled, "réels : REC grisé tant que rien n'est choisi")
	reel._premise_cards[1].interact()
	reel._tone_cards[2].interact()
	_assert(reel.premise_index == 1 and reel.tone_index == 2 and reel.rec_button.enabled, "réels : idée + ton choisis, REC prêt")
	var picked_title: String = reel.premises[1]["title"]
	var followers_before: int = main.profile.followers
	reel.rec_button.interact()
	_assert(reel.state == ReelMode.State.COUNTDOWN, "réels : compte à rebours lancé")
	await create_timer(3.3).timeout
	_assert(reel.state == ReelMode.State.RECORDING, "réels : tournage en cours après 3-2-1")
	_assert(reel._take_limit > reel._script_duration and reel._script_words.size() > 20, "réels : la prise dure le temps du texte (%.0f s)" % reel._take_limit)
	_assert(reel._prompter_text(0.0).contains("[color=#ffe27a]") and reel._prompter_text(reel._script_duration * 0.5).contains("[color=#7d7d86]"), "réels : le prompteur grise les mots déjà lus")
	reel.rec_button.interact()
	_assert(reel.state == ReelMode.State.RECORDING, "réels : STOP refusé avant la durée minimale")
	await create_timer(0.5).timeout
	reel._take_time = ReelMode.MIN_TAKE + 1.0
	await create_timer(0.3).timeout
	reel.rec_button.interact()
	_assert(reel.state == ReelMode.State.CHOOSING and reel.reels.size() == 1, "réels : prise terminée, réel posté")
	_assert(reel.reels[0]["premise"]["title"] == picked_title, "réels : le réel garde l'idée choisie")
	var waited := 0.0
	while reel._pending_count() > 0 and waited < 20.0:
		await create_timer(0.25).timeout
		waited += 0.25
	_assert(reel.reels[0]["state"] == "done", "réels : réel jugé (juge local, %.1f s)" % waited)
	var res: Dictionary = reel.reels[0]["result"]
	_assert(res.has("views") and res.has("verdict") and (res["comment_list"] as Array).size() >= 3, "réels : vues, verdict et commentaires présents")
	_assert(reel.reels[0]["judge"] == "juge local", "réels : jugé par le juge local hors ligne")
	_assert(reel.reels[0]["tokens"] >= 1 and main.profile.tokens == reel.reels[0]["tokens"], "réels : tokens crédités (%d)" % reel.reels[0]["tokens"])
	_assert(main.profile.followers >= followers_before and main.profile.reels_posted == 1, "réels : audience et compteur de réels mis à jour")
	await create_timer(1.5).timeout
	_assert(reel._selected == 0, "réels : le réel posté s'affiche à l'écran")

	# Deuxième réel pendant que le premier est fini, puis fin de séance.
	reel._premise_cards[0].interact()
	reel._tone_cards[0].interact()
	reel.rec_button.interact()
	await create_timer(3.3).timeout
	reel._take_time = ReelMode.MIN_TAKE + 1.0
	await create_timer(0.3).timeout
	reel.rec_button.interact()
	reel._end_button.interact()
	_assert(reel.state == ReelMode.State.FINISHING, "réels : TERMINER attend les verdicts en cours")
	waited = 0.0
	while not main.game_over and waited < 25.0:
		await create_timer(0.25).timeout
		waited += 0.25
	_assert(main.game_over and main.last_tokens == reel.session_tokens and reel.reels.size() == 2, "réels : séance close, %d tokens au total" % main.last_tokens)
	main.interact()
	await process_frame
	_assert(main.lobby != null and main.mode == Main.Mode.NONE and main.reel == null, "réels : retour au lobby")
	_assert(main.xr_camera.cull_mask == cam_mask_before, "réels : masque de la caméra restauré")

	LlmClient.force_offline = false
	print("=== RESULTAT: %s (%d échec(s)) ===" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)
