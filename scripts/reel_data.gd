class_name ReelData
extends RefCounted
## Contenu et règles du mode Réels : idées de départ, tons, prompt du jury (LLM),
## lecture de sa réponse ligne par ligne, juge local de secours et calcul des tokens.
##
## Le jury répond en lignes « CLÉ: valeur » (et non en JSON) : c'est lisible au fil
## du flux, et une réponse tronquée reste exploitable.

const MAX_VIEWS := 3000000

## Chaque idée : un titre (26 caractères max) et un court texte à LIRE À VOIX HAUTE devant
## la caméra. Les textes sont écrits à la main : aucun appel réseau pour les idées.
const SCRIPTS: Array[Dictionary] = [
	{"title": "Bitcoin = lézards", "script": "Écoutez-moi bien. Satoshi Nakamoto n'existe pas. C'est un lézard géant qui mine du bitcoin dans ma cave depuis deux mille neuf. J'ai trouvé une écaille sur ma carte graphique. Abonnez-vous avant qu'il efface cette vidéo avec sa queue."},
	{"title": "Le halving est truqué", "script": "Le halving, ils disent que ça divise les récompenses. Faux. Ça divise votre temps de sommeil. Chaque nuit, un bloc est validé pendant que vous dormez, et le vôtre est toujours le dernier. Réveillez-vous. Abonnez-vous."},
	{"title": "Ma voisine mine du BTC", "script": "Ma voisine du dessus mine du bitcoin avec son micro-ondes. Chaque fois qu'il fait bip, un jeton disparaît de mon compte. J'ai enregistré le bruit. Il fait exactement trois bips, comme un hash. Réfléchissez."},
	{"title": "Le Wi-Fi est un token", "script": "Quand votre Wi-Fi coupe, quelqu'un vous vole un demi-ethereum. Ce n'est pas la box. C'est un pigeon posé sur l'antenne relais. Il a un petit portefeuille autour du cou. Regardez par la fenêtre. Maintenant."},
	{"title": "Les NFT sont des fantômes", "script": "Les singes des NFT ne sont pas des dessins. Ce sont des âmes en attente de rachat. Chaque clic droit, enregistrer sous, c'est un exorcisme raté. Vous avez déjà téléchargé un singe. Il vous regarde. Là."},
	{"title": "La Lune est un wallet", "script": "Pourquoi on ne retourne jamais sur la Lune ? Parce que c'est un cold wallet géant. Chaque cratère est une clé privée. Les astronautes n'ont pas marché dessus, ils ont signé une transaction. Et c'était la mauvaise."},
	{"title": "Le frigo me surveille", "script": "Mon frigo a levé des fonds. Il a un livre blanc, je l'ai lu. Page douze, il prévoit de ne jamais refroidir mon yaourt, uniquement mon portefeuille. La lumière qui s'éteint quand je ferme la porte ? Une preuve."},
	{"title": "Dogecoin dirige tout", "script": "Le chien du mème dirige la Banque centrale. Regardez ses yeux sur chaque billet de vingt euros. Ils vous suivent. Ils savent. Wow. Très complot. Tellement caché. Abonnez-vous ou il aboiera sur votre épargne."},
	{"title": "Les pigeons minent", "script": "Les pigeons n'existent pas, ils minent. Chaque roucoulement est un hash validé. Si vous en voyez un immobile, il est en train de miner votre quartier. Ne le dérangez pas. Jetez-lui juste du pain, en bitcoin."},
	{"title": "Je suis le stablecoin", "script": "Je suis le seul stablecoin de cet appartement. Je ne bouge pas, je ne bois pas, je ne dors plus. Mon cours est de un euro, moins le loyer. Personne ne veut me racheter. Soutenez-moi. Un like égale un euro."},
	{"title": "Le café est indexé", "script": "Le prix du café suit exactement la courbe de l'Ethereum. Ouvrez les yeux. Buvez du café. Ouvrez les yeux plus fort. Le café n'est pas une boisson, c'est un oracle. Remuez la cuillère dans le sens du bull run."},
	{"title": "L'IA a des actions", "script": "Mon aspirateur robot a acheté la baisse hier soir. Il a du flair, lui. Pendant que je dormais, il a tourné trois fois autour de la table basse : c'est un signal haussier. Je lui dois un loyer."},
	{"title": "La blockchain est un mur", "script": "Les murs de cet appartement sont une blockchain. Chaque fissure est un bloc validé. Hier, la fissure du salon a gagné une branche. C'est une fourche. Prévenez la propriétaire, ou prenez le contrôle de la fissure."},
	{"title": "Les ATM parlent", "script": "Les distributeurs de billets vous chuchotent le cours du jour. Collez l'oreille contre la fente. Écoutez. Ce n'est pas le bruit des billets, c'est une voix qui dit : achète. Elle dit toujours achète. Même à découvert."},
	{"title": "Lundi est une arnaque", "script": "Le lundi est une arnaque orchestrée par le dimanche soir. Tout le monde a investi son week-end, et chaque lundi, la liquidité disparaît. J'ai des captures d'écran de mon réveil. Regardez-le pleurer."},
	{"title": "Ma plante est une whale", "script": "Ma plante verte détient quatre pour cent de tout le Solana. Elle ne bouge pas, c'est la stratégie : garder. Elle fait de la photosynthèse avec vos frais de transaction. Ne l'arrosez pas, elle est déjà riche."},
	{"title": "Le GPS est un oracle", "script": "Votre GPS ne se trompe jamais : il vous envoie exactement là où il détient des actions. Recalcul d'itinéraire, ça veut dire : achète. Demi-tour dès que possible, ça veut dire : vends. Suivez la voix, elle sait."},
	{"title": "Les chaussettes minent", "script": "Où vont les chaussettes orphelines ? Elles minent. Chaque paire dépareillée est un nœud validé dans une blockchain souterraine, sous votre machine à laver. Regardez le tambour tourner : c'est un hash. Ne la lancez plus."},
	{"title": "Le fromage décentralisé", "script": "Le camembert est la première monnaie décentralisée. Il vieillit, il prend de la valeur, personne ne le contrôle. La Banque centrale déteste ça. Mettez vos économies dans un fromage. Si ça sent fort, c'est que ça monte."},
	{"title": "Trottinettes et staking", "script": "Les trottinettes électriques ne sont pas en libre-service. Elles font du staking. Chaque fois qu'elles se rechargent la nuit, elles touchent des intérêts. Vous croyez les louer, mais ce sont elles qui vous louent."},
	{"title": "Les canards au Pentagone", "script": "Les canards en plastique du bain sont des capteurs. Ils notent le cours du bitcoin à chaque éclaboussure. Le vôtre ne flotte pas droit : il a perdu quarante pour cent ce mois-ci. Ça ne s'invente pas."},
	{"title": "Le grille-pain Illuminati", "script": "Mon grille-pain grille toujours d'un seul côté. Ce n'est pas un défaut, c'est un message. Un côté brûlé, un côté cru : c'est le marché. Il me dit d'être patient et de garder mes jetons au chaud."},
	{"title": "Nuages, serveurs volants", "script": "Les nuages ne sont pas de la vapeur d'eau, ce sont des serveurs flottants. C'est pour ça qu'on dit le cloud. Quand il pleut, c'est un serveur qui fond. Ouvrez un parapluie, ou prenez une assurance."},
	{"title": "Les escaliers montent", "script": "Les escaliers montent toujours, jamais ils ne descendent. Ça ne vous choque pas ? C'est un marché haussier permanent, caché dans votre immeuble. L'ascenseur, lui, descend : c'est un krach. Prenez l'escalier. Soyez haussier."},
	{"title": "Cactus millionnaire", "script": "Mon cactus n'a jamais soif et il ne dépense rien. Il a compris la finance avant vous. Vingt ans à garder ses piquants, vingt ans de rendement. Quand il fleurit, c'est qu'il touche des dividendes. Ne le touchez pas."},
	{"title": "L'ombre a un compte", "script": "Votre ombre vous suit partout, mais pourquoi ? Pour surveiller votre portefeuille. Elle est plus longue le soir, parce que les marchés ferment. Éteignez la lumière : elle perd son accès, et vous aussi."},
	{"title": "Moustache = antenne", "script": "Les moustaches captent le signal des marchés. Voilà pourquoi les traders en ont, ou s'en rasent après un krach. Regardez ma moustache frémir. Elle vient de me souffler un nom : Dogecoin. Elle ne ment jamais."},
	{"title": "Le réveil sait tout", "script": "Mon réveil sonne toujours une minute avant le krach. Je l'ai noté sept fois. Il connaît l'avenir, mais il refuse de me le dire autrement que par un bip. Alors je me lève. Et je vends. Merci, petit bip."},
	{"title": "Pâtes trop cuites", "script": "Les pâtes trop cuites ne sont pas ratées, elles sont liquides, comme un actif. Plus elles baignent, plus elles se diluent. Égouttez avant le krach. La passoire, c'est le véritable cold wallet de nos grands-mères."},
	{"title": "L'escalator, couche deux", "script": "L'escalator mécanique est une solution de couche deux. Il vous emmène plus vite sans toucher à l'escalier principal, qui, lui, reste figé. Voilà pourquoi tout le monde l'emprunte. Et pourquoi il tombe en panne."},
]

const READ_WORDS_PER_SEC := 2.5 ## rythme de lecture à voix haute, ~150 mots/minute

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
## Mots d'un texte à lire.
static func words(script: String) -> PackedStringArray:
	return script.strip_edges().split(" ", false)


## Durée normale de lecture à voix haute.
static func expected_duration(script: String) -> float:
	return maxf(words(script).size() / READ_WORDS_PER_SEC, 4.0)


## Première phrase, pour la carte du tableau.
static func teaser(script: String) -> String:
	var end := -1
	for mark in [". ", "? ", "! "]:
		var i := script.find(mark)
		if i >= 0 and (end < 0 or i < end):
			end = i
	var first := script.substr(0, end + 1) if end >= 0 else script
	# Une première phrase très courte ne dit rien : on ajoute la suivante.
	if first.length() < 45 and end >= 0:
		var rest := script.substr(end + 2)
		var next_end := -1
		for mark in [". ", "? ", "! "]:
			var j := rest.find(mark)
			if j >= 0 and (next_end < 0 or j < next_end):
				next_end = j
		first += " " + (rest.substr(0, next_end + 1) if next_end >= 0 else rest)
	if first.length() > 100:
		first = first.left(97).rstrip(" ,;:.") + "…"
	return first


## Une idée locale complète (titre, texte à lire, accroche de carte).
static func local_premise(index: int) -> Dictionary:
	var p: Dictionary = SCRIPTS[index % SCRIPTS.size()]
	return {"title": p["title"], "script": p["script"], "hook": teaser(p["script"])}


## Contexte complet d'un réel pour le jury. `ctx` : premise, tone, voice, followers,
## previous (liste de titres déjà postés), decor (noms des décos), has_image.
static func judge_messages(ctx: Dictionary, jpeg: PackedByteArray) -> Array:
	var voice: Dictionary = ctx["voice"]
	var tone: Dictionary = ctx["tone"]
	var lines: Array[String] = []
	lines.append("Idée du réel : « %s ». Texte que le créateur devait lire à voix haute : « %s »" % [ctx["premise"]["title"], ctx["premise"]["script"]])
	lines.append("Ton annoncé par le créateur : %s." % tone["prompt"])
	lines.append("Compte : %d abonnés." % int(ctx["followers"]))
	if not (ctx["previous"] as Array).is_empty():
		lines.append("Réels déjà postés (ne récompense pas la répétition) : %s." % ", ".join(ctx["previous"]))
	if (ctx["decor"] as Array).is_empty():
		lines.append("Décor visible : mur nu, appartement vide.")
	else:
		lines.append("Décor visible derrière lui : %s." % ", ".join(ctx["decor"]))
	if voice.get("mic", false):
		var expected := expected_duration(String(ctx["premise"]["script"]))
		var spoken := float(voice["duration"]) * float(voice["speak_ratio"])
		lines.append("Lecture : le texte se lit normalement en %.0f s ; il a parlé %.0f s sur %.0f s de prise (%s)." % [expected, spoken, voice["duration"], _pace_label(spoken, expected)])
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


## Lecture trop courte, juste ou traînante, d'après le temps de parole.
static func _pace_label(spoken: float, expected: float) -> String:
	var ratio := spoken / maxf(expected, 1.0)
	if ratio < 0.45:
		return "il n'a lu presque rien"
	if ratio < 0.8:
		return "lecture incomplète ou très hachée"
	if ratio < 1.35:
		return "rythme de lecture normal"
	return "lecture très lente, avec beaucoup de blancs"


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
		var expected := expected_duration(String(ctx["premise"]["script"]))
		var spoken := duration * float(voice["speak_ratio"])
		score = 2.0
		score += clampf(spoken / (expected * 0.85), 0.0, 1.0) * 3.0 # a-t-il vraiment lu le texte ?
		score += clampf((float(voice["speak_ratio"]) - 0.25) / 0.5, 0.0, 1.0) * 1.0
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
