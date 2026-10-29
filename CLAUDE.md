# NÉVROSE — Serious Game VR (Meta Quest 2)

## C'est quoi

Jeu VR Godot 4.7.2 où tu es schizophrène et tu as oublié ta dose. Tu fouilles ton
studio pour retrouver la pilule avant que la jauge de folie n'atteigne 100 %.
Fragment 1 (studio) jouable. GDD verrouillé dans `ASSIMILE_GDD.md`.

## Modes de jeu

- **Résistance** : on démarre déjà fou (12 %), les voix (les 15 `assets/voices/v*.wav`,
  sac mélangé, de plus en plus nombreuses) montent avec la folie. Pilules visibles
  avec un faisceau cyan + vibration + indice sur le téléphone, toujours à ≥ 5 m du joueur.
  Plus de clés ni de verrous. Tokens à l'assimilation : 0,12/s tenue + 5/pilule.
- **Chasse** (`hunt_mode.gd`, `knock_patch.gd`, `monster.gd`) : « toc toc toc » dans
  les murs/plafond, on casse la plaque (gâchette ou coup de poing, 4 coups) ; au
  dernier mur le monstre (`assets/monster/entity.glb`, mannequin Xbot de three.js,
  animé) apparaît puis se dissout. Tokens : 8 + 5 par mur.
- **Lobby** : deux cartes géantes (viser + gâchette) pour choisir le mode ; boutique
  de décorations au mur sud (`decor_catalog.gd`), profil sauvegardé (`player_profile.gd`).
- Tests : `tests/smoke_test.gd` et `tests/test_modes.gd`.

## Commandes clés

| Action | Commande |
|--------|----------|
| Lancer tests headless | `Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/smoke_test.gd` |
| Exporter l'APK | `export JAVA_HOME="C:/Users/noah0/jdk-21" && Godot --headless --path . --export-debug "Meta Quest 2" build/nevrose_quest2.apk` |
| Ouvrir l'éditeur | `Godot_v4.7.2-stable_win64_console.exe --path .` |
| Voir les commits | `git log --oneline` |

## Chemins importants

- `scripts/main.gd` — cœur du jeu (boucle, XR, déplacement, interaction, folie)
- `scripts/map_base.gd` — base de toutes les maps (conteneurs, dose, clés, mimics)
- `scripts/map2_extended.gd` — générateur de la map 2 (extension procédurale Est + jardin)
- `scripts/procedural_textures.gd` — textures générées au démarrage (plâtre, bois, tissu, carrelage, métal)
- `scripts/vr_body.gd` — corps FPV visible en baissant les yeux
- `scenes/main.tscn` — scène racine (XROrigin3D + caméra + 2 manettes)
- `scenes/map2_extended.tscn` — LA map du jeu (salon/cuisine + coquille, éditable à la main)
- `assets/kenney/` — 340 objets GLB (meubles + aliments), licence CC0
- `assets/hands/` — mains VR low-poly (godot-xr-tools)
- `build/nevrose_quest2.apk` — l'APK exportée
- `checkpoint.txt` — état du projet + bugs connus + solutions
- `TEST_PROTO_6J.md` — plan de test sur 6 jours (7 paliers)

## Conventions

- Commentaires et messages de code en **français**
- Renderer **gl_compatibility** (recommandé Quest 2)
- Zéro texture importée pour les murs/mobiliers — tout est procédural ou GLB Kenney
- Pas de RigidBody — murs gérés par clamp de position ou StaticBody3D
- Tests headless : 24 assertions, doivent toujours passer avant export

## À ne pas casser

- `get_viewport().use_xr = true` dans `_init_openxr()` — sinon écran noir total
- `move.y = -move.y` après `get_vector2` — sinon stick inversé sur Quest
- `apartment` (la map, `MapBase`) expose `get_dose()` pour la proximité de la main
- Les conteneurs (`InteractiveContainer`) ont besoin d'un `Area3D` enfant nommé `area`

## Modifier la map à la main

1. Ouvrir `scenes/map2_extended.tscn` dans l'éditeur Godot
2. Glisser-déposer les objets depuis `assets/kenney/furniture/` ou `food/`
3. Bouger avec **W** (déplacer), **E** (pivoter), **R** (redimensionner)
4. Pour un mur unique : clic droit sur Mesh → "Make Unique" avant de modifier
5. Les GLB Kenney sont natifs ~0,4× l'échelle réelle → les meubles du .tscn
   sont à **×2,5** ; viser la même échelle pour rester cohérent

## Déploiement Quest 2

1. `adb push build/nevrose_quest2.apk /sdcard/Download/`
2. Lancer depuis le casque (Bibliothèque → Sources inconnues → NÉVROSE)
3. Récupérer les logs : `adb pull /sdcard/Android/data/com.noirlab.nevrose/files/logs/nevrose.log`

## Git

- Repo : `Noahcnci/serious-game-vr-ci3` (2 sous-dossiers : `NEVROSE-le-jeu-vr/` + `serious-game-vr-ci-3/`)
- Toujours commit + push après modification
- Ne pas committer `build/`, `android/build/`, `.hermes/`

### Mode Réels (3e mode)

Pièce dédiée `scripts/studio_map.gd` (`StudioMap`, autre map que l'appartement : fond violet,
néon, console, canapé ; les décorations achetées s'accrochent au mur du fond filmé).
`scripts/reel_mode.gd` : tableau des tendances (3 idées bizarres tirées au hasard + 4 tons),
trépied/REC, écran de retour avec avatar, fiche façon Instagram. Chaque idée est un **court
texte à lire à voix haute** (écrit par le LLM, sinon réserve locale `ReelData.SCRIPTS`) ; le
prompteur au-dessus de l'objectif le fait défiler pendant la prise. Le micro (`voice_meter.gd`,
pas de reconnaissance vocale) mesure le temps de parole, le volume et l'intonation ; le jury
(LLM) compare le temps parlé au temps de lecture normal du texte, et reçoit aussi une image de
la prise. Réponse en flux (`llm_client.gd`). Sans réseau : juge local (`ReelData.heuristic`).
Tokens selon vues/likes (`ReelData.compute_tokens`).

- Les GLB Kenney ont leur pivot dans un coin : dans le studio, toujours les poser avec
  `StudioMap._place_centered` (emprise centrée), jamais avec `position` brute.
- LLM : OpenRouter si une clé est présente (`OPENROUTER_API_KEY`, ou `key=` dans
  `llm.local.cfg` à la racine, **ignoré par git**, inclus dans l'APK par `include_filter`),
  modèle `google/gemini-2.5-flash-lite`. Sinon serveur llama.cpp (`user://llm.cfg` ou
  `NEVROSE_LLM_URL`, défaut Tailscale `http://100.113.199.15:8081`).
- Android : permissions `internet` et `record_audio` dans `export_presets.cfg`.
- Tests : `tests/test_reels.gd` (hors ligne) ; `tests/live_llm.gd` essai manuel réseau.
