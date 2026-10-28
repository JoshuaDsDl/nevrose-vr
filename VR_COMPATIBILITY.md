# Compatibilité VR — NÉVROSE

## Cibles supportées

| Plateforme | Runtime | Preset | Statut |
|-----------|---------|--------|--------|
| **Meta Quest 2** (standalone) | OpenXR (Android) | `Meta Quest 2` | ✅ exportable (`build/nevrose_quest2.apk`) |
| **HTC Vive Pro / SteamVR** | OpenXR (Windows) | `Windows Desktop (SteamVR / Vive Pro)` | ✅ exportable (`build/nevrose_windows.exe`) |
| **Windows + tout runtime OpenXR** | OpenXR (Windows) | `Windows Desktop (SteamVR / Vive Pro)` | ✅ `xr_mode=0` = détection auto |

## Configuration OpenXR

- `openxr/enabled=true` dans `project.godot` (toujours actif)
- `xr_features/xr_mode=0` dans le preset Windows → **détecte automatiquement** le
  runtime OpenXR par défaut (SteamVR, Windows Mixed Reality, etc.)
- `xr_features/xr_mode=1` dans le preset Quest 2 → force **OpenXR Android** (pas besoin
  de runtime externe)

## Mapping boutons

Le mapping est universel (OpenXR standard) — même les mêmes sur Quest 2 et Vive Pro :

| Action | Quest 2 | Vive Pro (SteamVR) | Usage dans NÉVROSE |
|--------|---------|-------------------|--------------------|
| `grip` | Grip | Grip | **Pointer** (index tendu, autres doigts flex) |
| `trigger` | Trigger | Trigger | **Saisir** (poing fermé avec grip+trigger) |
| `primary` | Stick | Stick | **Déplacement** (joystick gauche) |
| `secondary` | Trackpad | Trackpad (Vive Pro 1) | — (réserve) |

## Build Windows (SteamVR / Vive Pro)

```bash
# Préalables :
# 1. Templates d'export installés dans %APPDATA%/Godot/export_templates/4.7.2.stable/
# 2. SteamVR installé sur la machine cible (pas requis sur la machine de build)

cd NEVROSE-le-jeu-vr
godot --headless --path . --export-release \
  "Windows Desktop (SteamVR / Vive Pro)" build/nevrose_windows.exe
```

**Pour tester avec une Vive Pro :**
1. Lancer SteamVR
2. Exécuter `build/nevrose_windows.exe`
3. L'app OpenXR est détectée automatiquement, le jeu démarre en VR

**Pour tester sans casque (desktop) :**
- Ouvrir l'éditeur Godot → F5 (le viewport 3D fonctionne, pas de VR mais l'UI est testable)

## Build Quest 2 (APK)

```bash
# Préalables :
# 1. Android SDK + JDK 21 installés
# 2. Templates d'export installés
# 3. Keystore de debug généré (Godot le fait auto à la 1re export)

cd NEVROSE-le-jeu-vr
godot --headless --path . --export-debug \
  "Meta Quest 2" build/nevrose_quest2.apk
```

**Pour installer sur un Quest 2 :**
1. Câble USB ou `adb connect <ip-quest>`
2. `adb install build/nevrose_quest2.apk`
3. Lancer depuis le library Quest

## Mains animées

Les mains utilisent le sous-module `godot-xr-tools` (importé dans `addons/`).
Le script `hand.gd` lit `grip` et `trigger` via OpenXR → le **même code** fonctionne
sur toutes les plateformes. Aucun ajustement spécifique par hardware.

## Notes / limitations

- **Renderer** : `gl_compatibility` (compatible OpenGL ES 3.0+ → Quest 2 OK,
  Windows DX11 OK). Ne PAS changer en `forward+` (pas supporté Quest 2).
- **SteamVR doit être installé sur la machine de TEST, pas de BUILD.**
  Le build ne nécessite qu'un Godot + templates d'export.
- **Foveation** : `openxr/foveation_level=2` (max) — réduit la charge GPU.
  Sur Vive Pro 144 Hz, c'est essentiel pour tenir le framerate.
- **submit_depth_buffer=true** : profondeur native (pas de reprojection) —
  meilleur confort VR, léger surperformance requise.
