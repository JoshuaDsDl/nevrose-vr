# Roadmap — ce qui reste à faire

Le fragment 1 (lobby + appartement complet) est **jouable et stable**. Voici les
pistes d'amélioration, par priorité suggérée.

## 🎯 Court terme (qualité / polish)

- [ ] **Équilibrage de la difficulté** : vitesse de montée de la folie, nombre
      de doses nécessaires, placement des clés (trop facile / trop dur ?).
- [ ] **Plus de variété de conteneurs** : utiliser `doorFreezer` du frigo, la
      porte droite du dressing, le tiroir droit de la table d'appoint.
- [ ] **Feedback d'ouverture forcée** : animation de « secousse » quand on force
      un verrou, pas seulement un flash.
- [ ] **Ambiance sonore** : bruitages d'ouverture/fermeture de tiroirs, pas de
      pas, respiration quand la folie monte.

## 🏠 Moyen terme (contenu)

- [ ] **Rats interactifs** : actuellement décoratifs (`rats.gd`). Les rendre
      perturbants (bruit, fouille dans les poubelles, fuient quand on approche).
- [ ] **Jardin jouable** : la clôture bloque, mais on pourrait y cacher une dose
      ou une clé. Ajouter des spots de spawn au jardin.
- [ ] **Événements scriptés** : porte qui claque, lumière qui grésille, ombre
      qui passe — déclenchés par seuils de folie.
- [ ] **Plus de mimics** : variantes (tasse, assiette, téléphone) avec des
      comportements légèrement différents.

## 🔧 Technique

- [ ] **Porte d'entrée verrouillée** : actuellement elle s'ouvre librement. La
      lier à une clé pour un vrai début de partie (sortir → rentrer ?).
- [ ] **Sauvegarde** : mémoriser le meilleur score (doses avant game over).
- [ ] **Options** : volume, sensibilité de la souris, échelle de la VR.
- [ ] **Profilage Quest 2** : vérifier les FPS, réduire les lumières si besoin.

## 🚀 Long terme (vision)

- [ ] **Fragment 2** : nouveau niveau (hôpital ? rêve ?) avec des mécaniques de
      folie différentes (murs qui respirent plus fort, gravité qui change).
- [ ] **Narration** : fil narratif qui se dévoile au fil des doses (pourquoi on
      oublie toujours sa dose ?).
- [ ] **Plusieurs fins** : selon le nombre de doses prises, ou le temps.

---

> **Avant d'ajouter une feature :** relis [`ERREURS.md`](ERREURS.md) et fais
> passer les 87 assertions. Ajoute une assertion pour chaque nouveau système.
