# Erreurs déjà commises — à ne pas reproduire

Ce fichier liste les bugs que nous avons déjà rencontrés et corrigés.
**Relis-le avant de modifier le code** pour ne pas refaire les mêmes erreurs.

---

## 🔴 Critiques (cassent le jeu ou l'écran)

### 1. `Transform3D * AABB` ne conserve pas l'échelle non uniforme
**Symptôme :** les collisions de murs/meubles avaient la taille **native** de la
mesh au lieu de la taille affichée → des murs invisibles bloquaient des
passages (ex. le mur ouest de la chambre bouchait l'entrée, 8,6 m au lieu de 5 m).

**Pourquoi :** dans cette version de Godot, multiplier un `Transform3D` par un
`AABB` ne transforme pas correctement les 8 coins quand l'échelle est non
uniforme (mur pivoté de 90° + scale sur le mauvais axe).

**Règle :** pour calculer une AABB monde, **toujours transformer les 8 coins**
individuellement (voir `MapBase._world_bounds()` / `_bounds_in_container()`).
Ne jamais écrire `transform * aabb`.

### 2. Géométrie dupliquée au lancement
**Symptôme :** des murs et meubles « en plus » apparaissaient, des pièces
concurrentes se superposaient.

**Cause :** le script `_build_extension()` reconstruisait une extension
procédurale alors que la scène éditée contenait déjà `ExtensionEst`.

**Règle :** la `.tscn` est la **seule** source de géométrie. Le script n'ajoute
que le gameplay (conteneurs, clés, spawns, collisions invisibles).

### 3. Écran noir total sur Quest 2
**Cause :** `get_viewport().use_xr = true` jamais appelé.

**Règle :** ne jamais supprimer cet appel dans `_init_openxr()`.

### 4. Stick inversé sur Quest
**Règle :** conserver `move.y = -move.y` après `get_vector2(&"primary")`.

---

## 🟠 Interaction / gameplay

### 5. Clic sur la pilule referme le tiroir
**Symptôme :** viser la pilule dans un tiroir ouvert et cliquer refermait le
tiroir au lieu de prendre la pilule.

**Cause :** le rayon touchait la pilule (Area3D enfant du conteneur), puis le
dispatch remplaçait la cible par son parent (`InteractiveContainer`).

**Règle :** dans `_tick_interaction_ray`, une `Dose` doit **rester** la cible
(exception avant le fallback parent). Voir `main.gd`.

### 6. Tiroir qui « lévite »
**Symptôme :** le tiroir sortait complètement de sa carcasse (42 cm), ce qui
le faisait paraître en lévitation.

**Règle :** limiter `open_distance` à **75 % de la profondeur réelle** du
tiroir (calculé depuis son AABB, pas une valeur fixe).

### 7. Crash en cliquant sur la tasse (mimic)
**Cause :** `Mimic.interact()` sans paramètre, alors que `Main.interact()`
passe une clé. + référence `_pointed` survivant au `queue_free()`. + scale
zéro pendant la dissolution (transform singulière).

**Règle :** donner à `interact()` la signature `(_holding_key: Node3D = null)`,
nettoyer `_pointed` si `not is_instance_valid()`, et dissoudre vers
`scale = Vector3.ONE * 0.001` (pas `Vector3.ZERO`).

### 8. Clé non prise dans la main
**Symptôme :** erreur `Can't add child ... already has a parent` au ramassage.

**Règle :** utiliser `key.reparent(right_hand)` (pas `right_hand.add_child(key)`)
quand l'objet a déjà un parent.

---

## 🟡 Audio / haptique

### 9. Téléphone qui spamme
**Symptôme :** un carillon à chaque message Messenger, impossible de se concentrer.

**Règle :** messages ordinaires **silencieux** (visibles dans Messenger). Seules
les **alertes critiques** notifient, avec un cooldown de **20 s**.

### 10. Voix qui se superposent
**Règle :** une seule voix à la fois (`_is_voice_playing()`), cooldown figé
pendant le clip, minimum 3 s de silence après.

### 11. Haptiques Quest 2 inopérants
**Cause :** `trigger_haptic_pulse` n'est plus une méthode de `XRController3D`
en Godot 4.7 (ancien code) + durée de 70 s au lieu de 70 ms.

**Règle :** utiliser `xr_interface.trigger_haptic_pulse(action, tracker,
freq, amplitude, duration_sec, delay)` avec les **trackers** `left_hand` /
`right_hand`, et des durées en **secondes** (0.08–0.25 s).

---

## 🟢 Affichage / texte

### 12. Texte du téléphone illisible
**Règle :** police des messages ~18 px, bulles sur toute la largeur, 2 messages
récents max, téléphone ~12 cm devant la manette.

### 13. Game over dupliqué (texte superposé)
**Symptôme :** le HUD 2D et le Label3D VR affichaient tous les deux le game over,
plus le chat derrière.

**Règle :** HUD 2D **uniquement** en bureau, Label3D **uniquement** en VR.
Masquer chat + point de visée pendant le game over.

---

## 🛠️ Pièges généraux

- **Fin de ligne Windows (CRLF) :** les patches MCP multi-lignes échouent si les
  fins de ligne ne correspondent pas. Vérifier avec un lecteur avant de patcher.
- **Encodage UTF-8 :** écrire les fichiers JSON/commandes en UTF-8 explicite pour
  les accents français (sinon `NÉVROSE` devient `NÃ‰VROSE`).
- **`has_method(&"trigger_haptic_pulse")` est faux** sur un `XRController3D` en 4.7
  → ne pas s'en servir comme garde.
- **Ne jamais** commenter simplement `_build_extension()` pour « désactiver »
  une pièce : il contient des conteneurs indispensables aux tests.
