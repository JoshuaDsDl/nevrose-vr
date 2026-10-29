class_name ReelData
extends RefCounted
## Contenu et règles du mode Réels : idées de départ, tons, prompt du jury (LLM),
## lecture de sa réponse ligne par ligne, juge local de secours et calcul des tokens.
##
## Le jury répond en lignes « CLÉ: valeur » (et non en JSON) : c'est lisible au fil
## du flux, et une réponse tronquée reste exploitable.

const MAX_VIEWS := 3000000

const PREMISES: Array[Dictionary] = [
	{"title": "Bitcoin = lézards", "hook": "Satoshi Nakamoto n'existe pas : c'est un lézard géant qui mine depuis ma cave."},
	{"title": "Le halving est truqué", "hook": "Le halving ne divise rien du tout. Ils divisent ta vie, pas les récompenses."},
	{"title": "Ma voisine mine du BTC", "hook": "Ma voisine du dessus mine du bitcoin avec son micro-ondes. J'ai des preuves sonores."},
	{"title": "Le Wi-Fi est un token", "hook": "Chaque fois que ton Wi-Fi coupe, quelqu'un te vole un demi-ethereum. Réfléchis."},
	{"title": "Les NFT sont des fantômes", "hook": "Les singes des NFT ne sont pas des dessins. Ce sont des âmes en attente de rachat."},
	{"title": "La Lune est un wallet", "hook": "Pourquoi on n'y retourne jamais ? Parce que la Lune est un cold wallet géant."},
	{"title": "Le frigo me surveille", "hook": "Mon frigo a levé des fonds. Il a un livre blanc. Je l'ai lu : c'est pire que je pensais."},
	{"title": "Dogecoin dirige tout", "hook": "Le chien du mème dirige la Banque centrale. Regarde ses yeux sur chaque billet."},
	{"title": "Les pigeons minent", "hook": "Les pigeons n'existent pas, ils minent. Chaque roucoulement, c'est un hash."},
	{"title": "Je suis le stablecoin", "hook": "Je suis le seul stablecoin de cet appartement et personne ne veut me racheter."},
	{"title": "Le café est indexé", "hook": "Le prix du café suit exactement la courbe de l'Ethereum. Ouvre les yeux. Bois du café."},
	{"title": "L'IA a des actions", "hook": "Mon aspirateur robot a acheté la dip hier soir. Il a du flair, lui."},
	{"title": "La blockchain est un mur", "hook": "Les murs de cet appartement sont une blockchain. Chaque fissure est un bloc validé."},
	{"title": "Les ATM parlent", "hook": "Les distributeurs te chuchotent le cours du jour. Colle ton oreille. Écoute."},
	{"title": "Lundi est une arnaque", "hook": "Le lundi est un rug pull orchestré par le dimanche soir. J'ai les captures d'écran."},
	{"title": "Ma plante est une whale", "hook": "Ma plante verte détient 4 % de tout le Solana. Elle ne bouge pas : c'est la stratégie."},
]

const TONES: Array[Dictionary] = [
	{"id": "alarmiste", "label": "ALARMISTE", "desc": "Fort, rapide, haletant.", "prompt": "alarmiste : fort, rapide, haletant"},
	{"id": "gourou", "label": "GOUROU", "desc": "Calme, grave, posé.", "prompt": "gourou : voix calme, grave et posée, pauses théâtrales"},
	{"id": "chuchote", "label": "CHUCHOTÉ", "desc": "Un secret à la caméra.", "prompt": "chuchoté : voix basse, confidentielle"},
	{"id": "vendeur", "label": "VENDEUR", "desc": "Énergie de télé-achat.", "prompt": "vendeur de formation : énergique, enthousiaste, très expressif"},
]

const FAKE_USERS := [
	"crypto_karen", "le_vrai_satoshi", "lezard_fr", "mamie_hodl", "t_as_pas_compris",
	"dr.complot", "bitcoinou_92", "paul.sceptique", "wagmi_boulanger", "chaton.nft",
	"theo_la_dip", "ex_de_vitalik", "camille.fact", "x_ape_x", "dave_stable",
]

const FAKE_COMMENTS_GOOD := [
	"J'ai tout compris, merci.", "Ça me retourne le cerveau 😭", "Abonné, abonné, abonné.",
	"Le gourou qu'on mérite.", "Je l'ai envoyé à ma banque.", "Plus convaincant que mon conseiller.",
	"Trop de vérités dans une seule vidéo.", "Ma mère vient d'acheter du Dogecoin.",
	"J'ai pleuré, puis j'ai acheté.", "Le troisième œil, c'est lui.",
]

const FAKE_COMMENTS_BAD := [
	"On se calme.", "C'est quoi ce mur derrière toi ?", "Tu as dormi quand ?",
	"Je cherche toujours la preuve.", "Ça manque d'énergie, non ?", "Même mon chat a zappé.",
	"Prends un café avant la prochaine.", "Algorithme, pitié.", "Qui a validé ça ?",
]

const _NUMBER_KEYS := {
	"VUES": "views", "LIKES": "likes", "COMMENTAIRES": "comments", "PARTAGES": "shares",
	"ABONNES": "followers", "ABONNÉS": "followers", "NOTE": "score",
}


# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------
static func ideas_messages() -> Array:
	return [
		{"role": "system", "content": "Tu écris des idées de réels Instagram comiques : théories du complot ABSURDES sur la crypto-monnaie et le quotidien (satire évidente, jamais de vraie désinformation, ni haine, ni vraie politique ou santé). Réponds uniquement par 3 lignes, au format exact :\nIDEE: <titre de 4 mots max> | <phrase d'accroche à dire face caméra, 12 mots max>"},
		{"role": "user", "content": "Donne 3 idées nouvelles et très différentes. Inspire-toi du thème du moment : %s." % ["les lézards", "les pigeons", "l'électroménager", "la Lune", "les voisins", "le Wi-Fi", "le café"].pick_random()},
	]


## Contexte complet d'un réel pour le jury. `ctx` : premise, tone, voice, followers,
## previous (liste de titres déjà postés), decor (noms des décos), has_image.
static func judge_messages(ctx: Dictionary, jpeg: PackedByteArray) -> Array:
	var voice: Dictionary = ctx["voice"]
	var tone: Dictionary = ctx["tone"]
	var lines: Array[String] = []
	lines.append("Idée du réel : « %s » — accroche : « %s »" % [ctx["premise"]["title"], ctx["premise"]["hook"]])
	lines.append("Ton annoncé par le créateur : %s." % tone["prompt"])
	lines.append("Compte : %d abonnés." % int(ctx["followers"]))
	if not (ctx["previous"] as Array).is_empty():
		lines.append("Réels déjà postés (ne récompense pas la répétition) : %s." % ", ".join(ctx["previous"]))
	if (ctx["decor"] as Array).is_empty():
		lines.append("Décor visible : mur nu, appartement vide.")
	else:
		lines.append("Décor visible derrière lui : %s." % ", ".join(ctx["decor"]))
	if voice.get("mic", false):
		lines.append("Mesures de la voix (tu n'entends pas les paroles) : %.0f s de prise, il parle %.0f %% du temps, volume moyen %.0f dB (crête %.0f dB), variation d'intonation %.1f dB (monotone < 3, expressif > 6), plus long silence %.1f s, %d phrases." % [
			voice["duration"], voice["speak_ratio"] * 100.0, voice["avg_db"], voice["peak_db"],
			voice["variation"], voice["longest_pause"], voice["bursts"]])
	else:
		lines.append("Micro indisponible : juge seulement l'idée, le ton annoncé et l'image.")
	var system := "Tu es « L'Algorithme », jury sarcastique et imprévisible d'un faux Instagram où l'on poste des réels de théories du complot ABSURDES sur la crypto (pure satire : pas de haine, pas de vraie désinformation). Tu juges l'idée, le ton, la cohérence entre le ton annoncé et la voix mesurée, et la mise en scène visible sur l'image jointe quand il y en a une. Sois sévère et varié : un réel plat fait moins de 500 vues, un bon réel quelques milliers, un grand réel plus de 50 000, un réel viral (rarissime) plus de 1 million. Les likes font 2 à 12 % des vues, les commentaires 1 à 10 % des likes, les partages 1 à 15 % des likes. Réponds UNIQUEMENT par ces lignes, dans cet ordre exact, sans markdown ni rien d'autre :\nVUES: <entier>\nLIKES: <entier>\nCOMMENTAIRES: <entier>\nPARTAGES: <entier>\nABONNES: <abonnés gagnés, entier>\nNOTE: <0 à 10>\nTITRE: <titre du réel, 5 mots max>\nVERDICT: <une phrase mordante, 20 mots max>\nC: <pseudo> | <commentaire drôle, 12 mots max>\n(5 lignes C: en tout : fans, haters et trolls mélangés)"
	var text := "\n".join(lines)
	var user_content: Variant = text
	if not jpeg.is_empty():
		user_content = LlmClient.image_content(text, jpeg)
	return [{"role": "system", "content": system}, {"role": "user", "content": user_content}]


# ---------------------------------------------------------------------------
# Lecture de la réponse
# ---------------------------------------------------------------------------
## Range une ligne du jury dans `result`. Renvoie la clé interne mise à jour
## (« views », « comment »…) ou "" si la ligne n'est pas exploitable.
static func parse_line(result: Dictionary, raw: String) -> String:
	var line := raw.strip_edges().replace("**", "").lstrip("-•* ").strip_edges()
	var colon := line.find(":")
	if colon <= 0:
		return ""
	var key := line.substr(0, colon).strip_edges().to_upper()
	var value := line.substr(colon + 1).strip_edges()
	if value == "":
		return ""
	if _NUMBER_KEYS.has(key):
		var internal: String = _NUMBER_KEYS[key]
		var n := parse_number(value)
		if n < 0.0:
			return ""
		result[internal] = n if internal == "score" else int(n)
		return internal
	match key:
		"TITRE":
			result["title"] = value.trim_prefix("«").trim_suffix("»").strip_edges().left(48)
			return "title"
		"VERDICT":
			result["verdict"] = value.left(220)
			return "verdict"
		"C":
			var bar := value.find("|")
			if bar <= 0:
				return ""
			var user := value.substr(0, bar).strip_edges().trim_prefix("@").replace(" ", "_").left(18)
			var text := value.substr(bar + 1).strip_edges().left(110)
			if user == "" or text == "":
				return ""
			if not result.has("comment_list"):
				result["comment_list"] = []
			(result["comment_list"] as Array).append({"user": user, "text": text})
			return "comment"
	return ""


## « 12 400 », « 12,4k », « 1.2M »… renvoie -1 si aucun nombre.
static func parse_number(text: String) -> float:
	var t := text.to_lower().replace(" ", "").replace(" ", "").replace(" ", "")
	var mult := 1.0
	if t.contains("m"):
		mult = 1000000.0
	elif t.contains("k"):
		mult = 1000.0
	var digits := ""
	for ch in t:
		if ch >= "0" and ch <= "9":
			digits += ch
		elif (ch == "," or ch == ".") and not digits.contains("."):
			if mult > 1.0 or digits != "":
				digits += "."
		elif digits != "" and ch != "," and ch != ".":
			break
	if digits == "" or digits == ".":
		return -1.0
	return float(digits) * mult


## Une ligne IDEE: titre | accroche.
static func parse_idea(raw: String) -> Dictionary:
	var line := raw.strip_edges().replace("**", "").lstrip("-•* ").strip_edges()
	if not line.to_upper().begins_with("IDEE") and not line.to_upper().begins_with("IDÉE"):
		return {}
	var colon := line.find(":")
	if colon < 0:
		return {}
	var body := line.substr(colon + 1).strip_edges()
	var bar := body.find("|")
	if bar <= 0:
		return {}
	var title := body.substr(0, bar).strip_edges().left(24)
	var hook := body.substr(bar + 1).strip_edges()
	if hook.length() > 100:
		hook = hook.left(97).get_slice(" ", 0) if false else hook.left(97).rstrip(" ,;:.") + "…"
	if title == "" or hook == "":
		return {}
	return {"title": title, "hook": hook, "live": true}


# ---------------------------------------------------------------------------
# Cohérence des chiffres, tokens, juge local
# ---------------------------------------------------------------------------
## Garde-fous : le LLM peut exagérer ou oublier un champ.
static func sanitize(result: Dictionary, followers: int) -> void:
	var views := clampi(int(result.get("views", 0)), 0, MAX_VIEWS)
	var likes := clampi(int(result.get("likes", 0)), 0, int(views * 0.35))
	var comments := clampi(int(result.get("comments", 0)), 0, maxi(int(likes * 0.25), 0))
	var shares := clampi(int(result.get("shares", 0)), 0, maxi(int(likes * 0.4), 0))
	result["views"] = views
	result["likes"] = likes
	result["comments"] = comments
	result["shares"] = shares
	result["followers"] = clampi(int(result.get("followers", 0)), 0, maxi(int(views * 0.08), 0))
	result["score"] = clampf(float(result.get("score", 5.0)), 0.0, 10.0)
	result["followers_before"] = followers


## Tokens du réel : l'audience compte (échelle logarithmique) et l'engagement aussi.
static func compute_tokens(result: Dictionary) -> int:
	var views := float(result.get("views", 0))
	if views <= 0.0:
		return 1
	var like_rate := float(result.get("likes", 0)) / views
	var audience := 7.0 * log(1.0 + views / 50.0) / log(10.0)
	var engagement := 8.0 * clampf(like_rate / 0.12, 0.0, 1.0)
	return maxi(int(round(3.0 + audience + engagement)), 1)


## Juge local : sert quand le serveur est injoignable ou quand une réponse est
## incomplète. Il tient compte des mêmes mesures que le LLM.
static func heuristic(ctx: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var voice: Dictionary = ctx["voice"]
	var score := 4.0
	if voice.get("mic", false):
		var duration: float = voice["duration"]
		score = 2.0
		score += clampf(duration / 14.0, 0.0, 1.0) * 2.0
		score += clampf((float(voice["speak_ratio"]) - 0.25) / 0.5, 0.0, 1.0) * 2.0
		score += clampf(float(voice["variation"]) / 7.0, 0.0, 1.0) * 1.5
		var tone_id: String = ctx["tone"]["id"]
		var avg: float = voice["avg_db"]
		var match_tone := 0.0
		match tone_id:
			"chuchote":
				match_tone = clampf((-26.0 - avg) / 12.0, 0.0, 1.0)
			"gourou":
				match_tone = clampf(float(voice["longest_pause"]) / 1.2, 0.0, 1.0) * 0.6 + clampf(1.0 - absf(avg + 24.0) / 14.0, 0.0, 1.0) * 0.4
			_:
				match_tone = clampf((avg + 30.0) / 14.0, 0.0, 1.0)
		score += match_tone * 1.5
	score += rng.randf_range(-1.2, 1.4)
	score = clampf(score, 0.0, 10.0)
	var reach := 1.0 + log(1.0 + float(ctx["followers"]) / 100.0) / log(10.0)
	var views := 90.0 * pow(10.0, score / 10.0 * 2.5) * reach * rng.randf_range(0.6, 1.5)
	if rng.randf() < 0.06:
		views *= rng.randf_range(6.0, 20.0) # le réel qui explose pour rien
	var like_rate := lerpf(0.02, 0.11, score / 10.0) * rng.randf_range(0.8, 1.2)
	var result := {
		"views": int(views),
		"likes": int(views * like_rate),
		"comments": int(views * like_rate * rng.randf_range(0.03, 0.09)),
		"shares": int(views * like_rate * rng.randf_range(0.04, 0.12)),
		"followers": int(views * rng.randf_range(0.004, 0.02) * score / 5.0),
		"score": score,
		"title": (ctx["premise"]["title"] as String),
		"verdict": _local_verdict(score, ctx),
		"comment_list": local_comments(score, 5, rng),
	}
	sanitize(result, int(ctx["followers"]))
	return result


static func _local_verdict(score: float, ctx: Dictionary) -> String:
	if score >= 8.0:
		return "Le complot est limpide, la voix est habitée : l'Algorithme a été convaincu malgré lui."
	if score >= 6.0:
		return "Solide. On sent la conviction, il manque juste une preuve plus louche."
	if score >= 4.0:
		return "Correct. Le ton « %s » aurait gagné à être poussé plus loin." % ctx["tone"]["label"].to_lower()
	if score >= 2.0:
		return "Mou. Même les lézards ont zappé."
	return "Silence gêné. L'Algorithme s'est endormi avant la fin."


static func local_comments(score: float, count: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var users := FAKE_USERS.duplicate()
	users.shuffle()
	for i in count:
		var good := rng.randf() < clampf(score / 10.0 + 0.1, 0.1, 0.9)
		var pool: Array = FAKE_COMMENTS_GOOD if good else FAKE_COMMENTS_BAD
		out.append({"user": users[i % users.size()], "text": pool[rng.randi() % pool.size()]})
	return out


## Complète un résultat partiel (réponse tronquée) avec le juge local.
static func fill_missing(result: Dictionary, ctx: Dictionary, rng: RandomNumberGenerator) -> void:
	var fallback := heuristic(ctx, rng)
	for key in ["views", "likes", "comments", "shares", "followers", "score", "title", "verdict"]:
		if not result.has(key):
			result[key] = fallback[key]
	if not result.has("comment_list") or (result["comment_list"] as Array).size() < 3:
		var list: Array = result.get("comment_list", [])
		for c in fallback["comment_list"]:
			if list.size() >= 5:
				break
			list.append(c)
		result["comment_list"] = list
	sanitize(result, int(ctx["followers"]))


## 12 400 → « 12,4 k », 1 250 000 → « 1,25 M ».
static func format_count(n: int) -> String:
	if n < 1000:
		return str(n)
	if n < 1000000:
		var k := n / 1000.0
		return ("%.1f k" % k).replace(".", ",") if k < 100.0 else "%d k" % int(k)
	return ("%.2f M" % (n / 1000000.0)).replace(".", ",")
