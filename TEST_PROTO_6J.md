# PLAN DE TEST PROTO — 6 JOURS NON STOP
# NÉVROSE fragment 1 — créé le 06/10/2026
# Règle d'or : l'utilisateur lance le jeu lui-même depuis le casque.
# Le déroulé : TU testes → TU me rapportes (même en vrac) → JE fixe/rebuild → on repasse le palier.

=====================================================================
PALIER 0 — MISE EN PLACE (avant le jour 1, ~30 min)
=====================================================================
[ ] Casque en mode développeur, câble branché, adb devices = "device"
[ ] NOUVELLE APK v2 (fix écran noir + logs) poussée dans /sdcard/Download/
[ ] apk v2 installée (depuis le casque ou adb install -r)
[ ] 1 session de lancement → nevrose.log récupéré et relu par l'assistant
[ ] Le log contient "[XR] OpenXR initialisé — viewport.use_xr=true"
     → Si non : diagnostic logcat, fix, rebuild, retour au [ ] précédent.

=====================================================================
PALIER 1 — LANCEMENT & AFFICHAGE (jour 1 matin)
=====================================================================
Le but : l'appart doit s'afficher correctement dans le casque.
[ ] Le jeu démarre depuis le menu (Sources inconnues → NÉVROSE), pas d'écran noir
[ ] L'appartement est visible entièrement (murs, lit, cuisine, table, TV, tapis)
[ ] Les couleurs sont lisibles (rien d'écrasé, pas de blanc saturé)
[ ] Le HUD s'affiche : point central blanc + chat en bas + vignette de folie
[ ] La lampe/lumière éclaire la pièce (pas de zone illisible)
[ ] 30 secondes sans crash ni gel
[ ] La caméra est à hauteur humaine (≈1,6-1,7 m), pas dans le sol ni le plafond
     → Échec d'un [ ] : me le dire précisément (quoi, où, quand) → fix → rebuild → retest.

=====================================================================
PALIER 2 — CONTRÔLES VR (jour 1 après-midi)
=====================================================================
Le but : les contrôles GDD §4 fonctionnent en VR réel.
[ ] Stick gauche : déplacement fluide à vitesse constante, dans les 4 directions
[ ] Les murs bloquent (pas de traverse, pas de sortie de l'appart)
[ ] Stick droit : snap turn 45° net, pas de rotation double (anti-rebond)
[ ] Le point central devient CYAN quand un objet interactif est visé
[ ] Gâchette index : ouvre un tiroir (mouvement animé vers soi)
[ ] Gâchette index : ouvre le placard
[ ] Un petit VIBREMENT (haptique) à chaque ouverture
[ ] Les deux manettes suivent les mains correctement (tracking)
[ ] 10 minutes de jeu → AUCUN symptôme de mal des transports
     (si nausée/lourdeur : noter à quel moment → on ajuste vitesse/snap)

=====================================================================
PALIER 3 — BOUCLE DE JEU COMPLÈTE (jour 2 → jour 3)
=====================================================================
Le but : tout le cycle pilule/folie/game over fonctionne en conditions réelles.
[ ] Une pilule cyan SPAWNE quelque part (tiroir/placard/plan de travail/sol)
[ ] Le chat affiche le compte à rebours avant la folie totale
[ ] Prendre la pilule (gâchette dessus) → sanity redescend nettement
[ ] Effet visible : la vignette se referme quand la folie monte
[ ] Murs qui respirent perceptibles à folie élevée
[ ] Messages du chat de plus en plus inquiétants (GDD §5.2)
[ ] Une NOUVELLE pilule spawn ~2 s après la prise
[ ] Laisser monter la folie à 100 → GAME OVER (écran + message assimilation)
[ ] Gâchette depuis le game over → la partie recommence proprement
[ ] 3 runs complets de suite SANS crash
[ ] À chaque run, noter : temps pour trouver la 1ʳᵉ pilule, nb d'ouvertures,
     sensation de pression (sur 5)
     → Si la boucle est trop facile/trop dure : on ajuste les constantes
       (SANITY_RATE, SANITY_RATE_AFTER_DOSE, délais) — elles sont en tête de scripts/main.gd.

=====================================================================
PALIER 4 — MIMIC & VARIABILITÉ (jour 3 → jour 4)
=====================================================================
Le but : le side-content mimic se comporte comme le GDD §5.3 (0 à 1 par round).
[ ] Sur 6 runs : le mimic apparaît parfois, parfois pas (fréquence 0-1/run)
[ ] Quand il est là : la tasse TREMBLE visiblement
[ ] Interagir avec la tasse qui tremble → purge + PÉNALITÉ de folie ressentie
[ ] Interagir avec un objet NORMAL ne fait rien (pas de faux positif)
[ ] La position de la pilule CHANGE bien entre les runs (4 spots min distincts)
[ ] Le mimics volant / taux accéléré : optionnel (pas codé encore) → noter si tu
     le sens manquer, pour prioriser la phase suivante.

=====================================================================
PALIER 5 — ROBUSTESSE & ENDURANCE (jour 4 → jour 5)
=====================================================================
Le but : le proto tient la route techniquement.
[ ] Session CONTINUE de 20+ minutes sans crash ni chute de fps visible
[ ] 5 lancements d'affilée sans dégradation (temps de chargement stable)
[ ] Désinstaller + réinstaller l'APK → tout repart proprement
[ ] Le jeu reste dans le périmètre Guardian (pas de conflit avec les murs réels)
[ ] Casque : pas de surchauffe anormale, batterie tenable
[ ] Après chaque session : nevrose.log présent et exploitable (lignes HB)
[ ] adb install -r par-dessus l'ancienne version → données/logs toujours OK

=====================================================================
PALIER 6 — VERDICT DU PROTO (jour 5 → jour 6)
=====================================================================
Le but : décider ce que le proto valide et ce qui change avant le fragment 2.
[ ] Bilan sensations : immersion / pression / lisibilité / confort — chacun noté /5
[ ] Liste des bugs rencontrés, triée : BLOQUANT (empêche de jouer) /
     MAJEUR (gâche) / MINEUR (cosmétique)
[ ] Points forts du proto validés (à garder tel quel)
[ ] Réponse à la question : la boucle pilule/folie est-elle FUN en l'état ?
[ ] Décision : GO pour fragment 2 (conteneurs verrouillés + chat-indices) ?
[ ] Moi (assistant) : checkpoint.txt mis à jour avec les apprentissages des 6 jours

=====================================================================
RYTHME DE JOURNÉE SUGGÉRÉ
=====================================================================
1. Session de test 15-20 min (tu joues, tu notes à chaud)
2. Tu me rapportes les résultats du palier (même en vrac, je trie)
3. Je fixe + rebuild APK (~8 min) en parallèle de ta pause
4. On repasse le palier en échec, puis on avance au suivant
5. Chaque soir : mise à jour de ce fichier ( [x] cochés )

À noter pendant TOUTE la campagne :
- heure/durée de chaque session
- bug = quoi + où + dans quel palier
- toute sensation de malaise VR (important pour un serious game)
- envies émergentes ("j'aurais aimé pouvoir…") → ça alimente le fragment 2
