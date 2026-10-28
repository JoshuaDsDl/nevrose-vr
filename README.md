# NÉVROSE

**Jeu sérieux VR (Meta Quest 2) — Godot 4.7.2**

Tu es schizophrène et tu as oublié ta dose. Fouille ton appartement pour
retrouver la pilule avant que la jauge de folie n'atteigne 100 %.
Le jeu démarre dans un **lobby cosy** (salon + bureau + ordinateur) qui sert de
tutoriel ; cliquer sur l'ordinateur lance la partie et te transporte dans
l'appartement.

---

## Sommaire

- [Aperçu](#aperçu)
- [Contrôles](#contrôles)
- [Architecture du code](#architecture-du-code)
- [Carte des systèmes](#carte-des-systèmes)
- [Lancer / tester / exporter](#lancer--tester--exporter)
- [État du développement](#état-du-développement)
- [Documentation](#documentation)

---

## Aperçu

| | |
|---|---|
| **Moteur** | Godot 4.7.2 (renderer `gl_compatibility`, recommandé Quest 2) |
| **Plateforme cible** | Meta Quest 2 (OpenXR) + fallback bureau |
| **Genre** | Serious game — fouille sous pression (horreur psychologique) |
| **Langue du code** | Français (commentaires, messages, logs) |

**Boucle de jeu :** la folie monte toute seule → fouille les meubles (tiroirs,
placards, frigo) → trouve et avale la pilule → la folie redescend → la pression
ré-augmente. Des **mimics** (objets qui tremblent) et des **voix dans les murs**
(HRTF) perturbent le joueur. À 100 % : game over.

---

## Contrôles

| Action | Quest 2 (VR) | Bureau (debug / tests) |
|---|---|---|
| Déplacement | stick gauche (vitesse constante) | `WASD` / flèches |
| Rotation | stick droit : snap 45° | `Q` / `E` / clic droit |
| Regard (pitch) | tête | souris (capturée) |
| Interagir (ouvrir, prendre) | gâchette index (rayon main droite) | `F` / clic gauche (rayon caméra) |
| Téléphone Messenger | bouton `X` / `Y` | `Tab` / `T` / `P` |
| Lancer la partie (lobby) | gâchette sur l'ordinateur | `F` / clic sur l'ordinateur |
| Restart après game over | gâchette | clic |

---

## Architecture du code

```
scenes/main.tscn            Point d'entrée : XROrigin3D + caméra + 2 manettes
└── scripts/main.gd         Orchestrateur : OpenXR, boucle, déplacement,
                            interaction (rayon), folie, HUD, téléphone, lobby

scripts/map2_extended.gd    LA map (étend la scène éditable map2_extended.tscn)
└── scripts/map_base.gd     Classe de base : conteneurs, dose, clés, mimics,
                            collisions invisibles, spawns

scripts/                    Systèmes autonomes
├── lobby_world.gd          Salon d'accueil (relance le signal de départ)
├── lobby_computer.gd       Ordinateur « CLIQUE POUR JOUER » (survol + clic)
├── entrance_door.gd        Porte d'entrée ouvrable (pivot + collision mobile)
├── container.gd            Tiroir / placard interactif (GLB réel, verrous)
├── pill.gd                 La Dose + carillon spatial (AudioStreamPlayer3D HRTF)
├── key_object.gd           Clé cachée (déverrouille un conteneur précis)
├── mimic.gd                Fausse tasse qui tremble (statique / mobile)
├── creepy_voices.gd        Voix dans les murs (une seule à la fois, HRTF)
├── phone.gd                Smartphone Messenger (messages, notifications)
├── vr_body.gd              Corps FPV visible en baissant les yeux (VR only)
├── rats.gd                 Rats qui traversent le jardin (décor animé)
├── procedural_textures.gd  Textures générées au démarrage (zéro import)
└── game_logger.gd          Journal de session (autoload GameLog)

tests/smoke_test.gd         87 assertions headless (doivent toujours passer)
```

### Points d'extension importants

- **`Main.start_game()`** — démarre la partie depuis le lobby. Idempotent,
  ne doit être appelé qu'une fois.
- **`Map2Extended._container_part()`** — crée un conteneur depuis une **vraie
  partie GLB** (pivot + matériau d'origine), jamais de façade générique.
- **`MapBase._world_bounds()`** — AABB monde correcte (8 coins transformés).
  **Ne pas utiliser `Transform3D * AABB`** (voir [Erreurs à éviter](docs/ERREURS.md)).

---

## Carte des systèmes

Flux d'une frame (simplifié) :

```
Physics frame (Main._physics_process)
  │
  ├─ game_started ? non ──► _tick_movement (lobby : pas de folie)
  │                            └─ capsule CharacterBody3D + collisions
  │
  └─ game_started ? oui ──► _tick_sanity        (folie ↑ → game over à 100)
                            _tick_movement        (capsule + clamp map)
                            _tick_interaction_ray (rayon → _pointed)
                            _tick_sanity_feedback (vignette, voix, murs)
                            _tick_pill_eat_feedback (zone bouche)

Interaction (gâchette / F)
  └─ Main.interact() ──► priorité : pilule tenue > clé > pilule > conteneur
                            > proximité
```

Cycle de la folie :

```
dose absorbue ──► sanity -= 55, montée ralentie ──► nouvelle dose (2 s)
      ▲                                                   │
      └── folie monte (1.4/s, +0.3/dose) ◄────────────────┘
              └── 100 % ──► GAME OVER ──► restart (gâchette)
```

---

## Lancer / tester / exporter

```bash
# Tests headless (87 assertions, doivent TOUJOURS passer avant export)
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/smoke_test.gd

# Ouvrir dans l'éditeur
Godot_v4.7.2-stable_win64_console.exe --path .

# Exporter l'APK (Meta Quest 2)
export JAVA_HOME="C:/Users/<toi>/jdk-21" && \
  Godot --headless --path . --export-debug "Meta Quest 2" build/nevrose_quest2.apk
```

> Les chemins exacts (Godot, JDK, Android SDK) dépendent de ta machine.
> Voir [`docs/INSTALL.md`](docs/INSTALL.md).

---

## État du développement

**Fragment 1 jouable** — lobby + appartement complet (salon, cuisine, couloir,
garage, chambre, SDB, dressing, jardin). Voir [`docs/ROADMAP.md`](docs/ROADMAP.md)
pour ce qui reste à faire.

| Système | État |
|---|---|
| Lobby + tutoriel | ✅ |
| Déplacement VR + bureau | ✅ (pitch souris, snap turn) |
| Collisions (murs, meubles) | ✅ (capsule + boîtes invisibles) |
| Conteneurs (tiroirs, frigo, placards) | ✅ (vraies parties GLB) |
| Pilule + carillon spatial | ✅ |
| Clés + verrous (clé / force) | ✅ |
| Mimics + voix HRTF | ✅ |
| Téléphone Messenger | ✅ (notifications silencieuses sauf alertes) |
| Haptiques Quest 2 | ✅ (`XRInterface.trigger_haptic_pulse`) |
| Porte d'entrée | ✅ |
| Export APK | ✅ (preset « Meta Quest 2 ») |

---

## Documentation

| Fichier | Contenu |
|---|---|
| [`docs/AGENTS.md`](docs/AGENTS.md) | Guide pour les agents / contributeurs (comment modifier sans casser) |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | Ce qui reste à faire, idées, ordre suggéré |
| [`docs/ERREURS.md`](docs/ERREURS.md) | Erreurs déjà commises → à ne pas reproduire |
| [`docs/INSTALL.md`](docs/INSTALL.md) | Installation des outils + build APK |
| [`ASSIMILE_GDD.md`](ASSIMILE_GDD.md) | Game Design Document verrouillé |
