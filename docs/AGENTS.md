# Guide pour les agents / contributeurs

Ce fichier explique **comment modifier ce projet sans le casser**. Il est
écrit pour un agent (Claude, humain, ou autre) qui arrive sur le code.

> **Règle d'or :** les 87 assertions de `tests/smoke_test.gd` doivent **toujours
> passer** avant tout export APK. Lance-les après chaque changement.

---

## 1. Structure à connaître avant de toucher quoi que ce soit

- **`scenes/map2_extended.tscn` est la SEULE source de géométrie.** Le script
  `map2_extended.gd` ajoute uniquement le gameplay (conteneurs, clés, mimics,
  spawns, collisions invisibles). **Ne recrée jamais de murs/meubles par code**
  → cela produit des doublons au lancement.
- **`scripts/main.gd` est l'orchestrateur.** Il possède un état `game_started`
  et `lobby`. Tant que `game_started == false`, la folie/le téléphone/la dose
  sont en pause. `start_game()` est idempotent (ne s'exécute qu'une fois).
- **`scripts/map_base.gd` factorise le gameplay.** Les maps concrètes
  (`Map2Extended`) héritent et surchargent `build()`.

## 2. Ce que tu peux / ne peux pas modifier

| Tu peux modifier | Tu ne dois PAS modifier sans réfléchir |
|---|---|
| `scenes/map2_extended.tscn` (glisser-déposer meubles) | `scripts/map_base.gd` (AABB, spawns) — casse les tests |
| Textes du lobby, meubles du lobby | `get_viewport().use_xr = true` (sinon écran noir) |
| Positions/échelles de meubles (éditeur) | `move.y = -move.y` après `get_vector2` (stick inversé) |
| Ajouter un conteneur via `_container_part()` | La signature `interact()` des objets interactifs |

## 3. Comment ajouter un conteneur interactif

Utilise **toujours** `_container_part()` (jamais une façade générique) :

```gdscript
_container_part(
    "Shell/ExtensionEst/Chambre/TableNuit",  # chemin du meuble support
    "drawer",                                 # nom de la partie GLB mobile
    "NightstandDrawer",                       # nom unique du conteneur
    InteractiveContainer.Mode.SLIDE,          # ou ROTATE
    InteractiveContainer.LockType.KEY,        # ou NONE / FORCEABLE
    0.35                                       # distance (SLIDE) / angle (ROTATE)
)
```

Le helper : trouve le vrai mesh GLB (`drawer`, `doorFridge`…), le reparente au
pivot d'origine, **conserve ses matériaux**, crée l'Area3D depuis son AABB.

## 4. Comment modifier la map à la main (éditeur Godot)

1. Ouvrir `scenes/map2_extended.tscn` dans l'éditeur.
2. Glisser-déposer depuis `assets/kenney/furniture/`.
3. `W` déplacer, `E` pivoter, `R` redimensionner.
4. Les GLB Kenney sont ~0,4× l'échelle réelle → mettre **×2,5** (sauf gros
   modèles déjà larges, cf. `FURN_SCALE` dans `map2_extended.gd`).
5. **Après avoir déplacé un meuble support de conteneur**, les clés/spawns se
   recalculent tout seuls (via `_surface_point` / AABB). Vérifie quand même.

## 5. Outils MCP Godot (si connecté)

Préfère les outils `godot-ai` (`node_create`, `node_set_property`,
`batch_execute`, `scene_save`) plutôt que d'écrire des scripts headless ad hoc.
**Toujours capturer** (`editor_screenshot`) après un placement pour vérifier.

## 6. Workflow obligatoire

1. Modifie (via éditeur ou MCP).
2. `git add` + commit (message en français, **pas de Co-Authored-By**).
3. Lance les tests headless (ci-dessous).
4. Si OK → push. Si KO → corrige avant de push.

```bash
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/smoke_test.gd
# Résultat attendu : === RESULTAT: PASS (0 échec(s)) ===
```

---

## 7. Conventions

- **Commentaires et messages en français.**
- Renderer `gl_compatibility`. **Zéro texture importée** pour les murs/mobiliers
  (textures procédurales ou GLB Kenney).
- **Pas de RigidBody** — murs gérés par `StaticBody3D` + boîtes, joueur par
  `CharacterBody3D`.
- Ne commite pas `build/`, `android/build/`, `.hermes/`, `.mcp.json`.

Voir [`ERREURS.md`](ERREURS.md) pour les pièges déjà rencontrés.
