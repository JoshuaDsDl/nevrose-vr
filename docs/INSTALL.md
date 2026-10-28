# Installation des outils + build APK

Ces chemins sont **ceux d'une machine de développement**. Adapte-les à la tienne.

## Prérequis

| Outil | Version | Rôle |
|---|---|---|
| Godot | 4.7.2 stable (console) | Moteur + export |
| JDK | 21 (Temurin) | Build Gradle Android |
| Android SDK | cmdline-tools + platform-tools + `platforms;android-34` + `build-tools;34.0.0` | Export APK |
| Templates d'export Godot | 4.7.2.stable | `export_templates/` |

## Installation (une fois)

1. Installer Godot 4.7.2 et ajouter le chemin au `PATH` (ou utiliser le chemin complet).
2. Installer JDK 21, définir `JAVA_HOME`.
3. Installer l'Android SDK + les packages listés ci-dessus.
4. Dans Godot : **Éditeur → Gérer les templates d'export** → installer 4.7.2.
5. Configurer l'export Android (clés debug, chemins SDK) — voir `export_presets.cfg`.

## Tester sans casque (recommandé à chaque changement)

```bash
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/smoke_test.gd
# Attendu : === RESULTAT: PASS (0 échec(s)) ===
```

## Jouer sur PC (clavier/souris)

Ouvrir le projet dans l'éditeur Godot 4.7.2 → lancer `scenes/main.tscn`.
OpenXR absent → fallback bureau automatique.

## Build APK (Meta Quest 2)

```bash
export JAVA_HOME="C:/Users/<toi>/jdk-21"
Godot_v4.7.2-stable_win64_console.exe --headless --path . \
    --export-debug "Meta Quest 2" build/nevrose_quest2.apk
```

Le build Gradle peut dépasser le timeout du terminal (600 s) **mais l'APK est
déjà écrit**. Vérifie avec `ls -la build/` puis tue le processus Godot restant.

### Déployer sur le casque

```bash
adb push build/nevrose_quest2.apk /sdcard/Download/
# Puis lancer depuis le casque : Bibliothèque → Sources inconnues → NÉVROSE
```

### Récupérer les logs du casque

```bash
adb pull /sdcard/Android/data/com.noirlab.nevrose/files/logs/nevrose.log
```

## Pièges connus (build)

- **« Gradle build template not installed »** → le preset doit pointer
  `gradle_build_directory="res://android"` (Godot ajoute `/build` tout seul).
- **« Version mismatch »** → créer `android/.build_version` contenant exactement
  `4.7.2.stable` (sans suffixe).
- **« ETC2/ASTC required »** → `textures/vram_compression/import_etc2_astc=true`
  déjà réglé dans `project.godot`.

Voir [`ERREURS.md`](ERREURS.md) pour les erreurs de **code** (pas de build).
