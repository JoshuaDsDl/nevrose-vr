# NÉVROSE — Game Design Document — VERSION FINALE (verrouillée)

*Ancien titre de travail : ASSIMILÉ.*

## 1. Pitch

Tu es un gars lambda, enfermé dans son appartement. Ta schizophrénie monte vite — et tes médocs sont cachés dans la maison. **La quête, c'est les pilules.** Elles spawnent aléatoirement dans des conteneurs : tiroirs, plans de travail, tables, sol, placards — parfois verrouillés, parfois non. Plus tu tardes à les trouver, plus tu deviens fou. Et au fil de ta recherche, des **mimics** infestent l'appart pour te faire chier : deux clés à molette côte à côte, une tremble légèrement... c'est un piège. Tue-la, ou attrape-la et explose-la contre le mur — mais gare aux dégâts collatéraux, car tu peux semi-détruire ton propre chez-toi de façon permanente. Sauf que les **super-médocs**, eux, te réinitialisent la schizo... et réparent la maison.

**Hook en une phrase :** fouiller ta propre maison pour rester sain d'esprit, pendant qu'elle s'assimile peu à peu à ton délire.

## 2. Le thème « Assimiler »

- **Les mimics assimilent tes objets** → tu ne peux plus faire confiance à ton propre chez-toi (deux clés à molette identiques, une seule est vraie).
- **Toi, tu es assimilé par ta schizo** : sans médocs, l'appart glisse vers le délire (murs qui respirent, voix, objets qui mentent). Les super-médocs inversent le processus — et la maison guérit en même temps que toi. Toi et le décor partagez le même état de santé.
- La maison et le joueur sont **un seul corps de gameplay** : te soigner = soigner l'appart.

## 3. Héros

Un mec lambda, customisable léger (tenue, déco). Pas de lore lourd : la folie vient des médocs manquants.

## 4. Contrôles (verrouillés)

- **Stick gauche** : déplacement classique, vitesse constante. Aucune dérive, aucun glitch — la folie ne vit PAS dans les contrôles.
- **Stick droit** : rotation fluide (ou snap 45° confort VR).
- **Mains** : ouvrir tiroirs/placards, attraper objets, saisir et **lancer contre le mur** pour casser.
- **Gun** : trouvé dans la maison, munitions limitées, tir précis.
- **Gâchettes** : tirer / frapper / lancer.

## 5. Mécaniques principales

### 5.1 La quête des pilules (cœur du jeu)
- Les médocs **spawne aléatoirement** à chaque run dans des conteneurs : **tiroirs, plans de travail, tables, sol, placards**.
- Chaque conteneur est **verrouillé ou non** :
  - **Non verrouillé** : ouverture directe (tiroir, placard).
  - **Verrouillé** : il faut trouver comment l'ouvrir — clé cachée ailleurs, code trouvé via un indice/objet WTF, ou déverrouillage forcé (casse, bruit qui attire les mimics).
- **Pression temporelle** : la jauge de schizo **monte vite** tant que tu n'as pas ta dose. Chaque seconde de fouille augmente la tension. Tu veux absolument trouver tes pilules — le jeu te force à fouiller partout, vite, en risquant les mimics.
- Prendre la pilule = reset partiel de la schizo + ralentissement de la montée.

### 5.2 Jauge de schizo / folie
- **Monte rapidement** quand les pilules sont introuvables, remonte lentement quand tu en as pris une.
- **Folie élevée** : murs qui respirent, voix dans les murs et le sol, objets WTF, mimics qui glitchent visuellement (détectables), hallucinations sonores.
- **Lucidité** : environnement stable — mais les mimics parfaitement indétectables (identiques aux vrais objets).
- Conflit permanent : **fou = mimics visibles mais perception fausse. Lucide = perception nette mais mimics invisibles.**
- 100% = game over narratif (l'appart t'assimile — tu deviens le mur).
- **Le chat in-game donne le temps restant avant de devenir fou** : une interface de messages (téléphone/messenger intégré au monde VR) qui affiche le compte à rebours avant la folie totale — ex. « Il te reste 2:34 avant que ça bascule. » Le chat est à la fois une source d'indices (codes, positions de pilules) et l'horloge de la pression. Plus la schizo monte, plus les messages deviennent inquiétants/fragmentés.

### 5.3 Mimics (side content — mobs occasionnels, pas le cœur du jeu)
- **Les mimics ne sont PAS la principale menace.** Le cœur du jeu = fouiller la maison et trouver les médocs sous pression de schizo. Les mimics sont du contenu secondaire, ponctuel.
- **Fréquence** : **maximum un seul mimic par round, et pas obligatoirement** — certains rounds s'en passent complètement. La majorité du temps, tu es seul avec ta recherche et ta folie montante.
- **Variante signature — le mimic caméléon WTF** : parfois le mimic se cache sous forme d'**objet WTF aberrant, déplacé du contexte** : un distributeur de boissons posé sur le lit, dans la salle de bain, un frigo dans le couloir... L'absurdité est le signal : un objet qui n'a rien à faire là = suspect par défaut. Soit c'est un indice/objet WTF utile, soit c'est le mimic.
- Il surgit de façon **imprévisible** et se résout vite : repérer, décider, tirer ou lancer. Puis on reprend la quête.
- **Exemple canonique** : deux clés à molette côte à côte, l'une tremble légèrement. C'est le faux.
- **Options de combat** :
  - **Tirer dessus** (gun) — rapide, mais bruyant et munitions limitées.
  - **Le récupérer et le casser en le lançant contre le mur** — gratuit, mais physique, risqué, et ça abîme la maison.
- **Ne rien faire a un coût réel** :
  - **Ils volent tes médocs** : un mimic laissé en vie peut s'emparer d'une pilule repérée (ou déjà prise dans la main) et la planquer ailleurs — ta quête recule.
  - **Ils te rendent plus schizo** : tant qu'un mimic est en vie, il t'influence — la jauge de schizo monte plus vite et des hallucinations (fausses voix, faux objets, indices piégés) se multiplient. Leur simple présence te pourrit la perception.
- Se tromper = détruire un vrai objet (le doute coûte cher) ou se faire mordre la main.
- En folie, ils glitchent ; en lucidité, seul le comportement les trahit (tremblement, micro-déplacement, son sourd via audio spatial).
- **Boucle de tension (quand ils apparaissent)** : ignorer un mimic = médocs volés + schizo accélérée. Mais le chasser = temps perdu sur la recherche + bruit + dégâts à la maison. Chaque décision est un trade-off — ponctuel, pas permanent.
- Fréquence cible : **0 à 1 mimic par round**. S'ils deviennent du bruit de fond, le jeu rate son effet.

### 5.4 Destruction semi-permanente de l'appart
- Casse, impacts de balles, objets lancés : **les dégâts restent** toute la partie (murs troués, meubles brisés).
- La maison dégradée = moins de couverture, mimics qui utilisent tes trous, navigation plus dure.
- **Seuls les super-médocs réparent** : ils réinitialisent ta schizo ET restaurent l'appart à son état d'origine.
- Décision de ressource : casser maintenant pour survivre, ou préserver la maison en attendant le super-médoc ?

### 5.5 Objets WTF
- Pop aléatoire, utiles ou leurres :
  - Poisson dans le frigo qui donne des indices (codes de cadenas, positions de pilules).
  - Horloge qui parle quand on la tape.
  - TV qui montre le futur à +5 secondes.
- Certains sont des mimics déguisés.

### 5.6 Conteneurs verrouillés (détail)
- Types de verrous : cadenas à clé (clé cachée dans la maison), code (indice via objet WTF ou message chuchoté), verrou cassable (force, bruit).
- Le bruit d'un conteneur forcé ou d'un tir **attire les mimics** : la fouille en force a un coût.

## 6. Progression (rounds)

| Round | Nouvelle mécanique |
|---|---|
| 1 | Pilules faciles à trouver, premiers mimics statiques (tutorial implicite) |
| 2 | Conteneurs verrouillés, mimics en duo indiscernables |
| 3 | Mimics mobiles (bougent quand tu ne regardes pas), montée de schizo plus rapide |
| 4 | Objets WTF, leurres audio, mimics qui imitent des pilules |
| 5 | Appart qui se dégrade (couloirs longs, murs qui respirent), destruction quasi inévitable |
| 6 | Boss final : la maison t'a assimilé — tous les objets deviennent suspects, il faut trouver la dernière pilule au cœur de la folie |

## 7. Direction artistique

- Appart réaliste qui dérive avec la jauge : déco normale → textures qui respirent → pâte à modeler → chair sous la brique.
- Une couleur dominante par round, audio spatial binaural (voix dans murs et sol).
- UI minimaliste : la schizo se lit sur le monde (vignette, respiration des murs), pas de barre classique — **sauf le chat**, qui affiche le **temps restant avant de devenir fou**.

## 8. Confort VR

- Vignette automatique pendant les pics de folie.
- Option snap-turn dès le round 2.
- Aucun déplacement forcé hors contrôle joueur.

## 9. Décisions verrouillées (ne pas rouvrir)

- **La quête = les médocs.** Pas de safe central, pas d'objets-clés de safe : tu cherches tes pilules dans la maison, point.
- Pilules en spawn aléatoire : tiroirs, plans de travail, tables, sol, placards — verrouillés ou non.
- Schizo qui monte vite tant que les pilules sont introuvables.
- Mimics = **side quests mobs, occasionnels** : **0 à 1 par round**. Parfois déguisés en **objet WTF déplacé** (distributeur de boissons sur le lit, frigo dans la salle de bain). S'ils ne sont pas tués : **vol de médocs** + **schizo accélérée**.
- Combat : tirer OU récupérer et casser au lancer contre le mur.
- Destruction semi-permanente ; seuls les super-médocs reset la schizo ET réparent la maison.
- Déplacement joystick classique, sans dérive.
- Pas de co-op, pas de micro/cri (bonus idées uniquement).

## 10. Bonus idées (hors scope jam)

- Mode « dépendance » : rounds infinis, classement pilules.
- Fin double : assez de super-médocs = tu t'échappes de l'appart.
- Sonar vocal (crier pour révéler les contours des mimics).
- Le dealer à la main sous la porte — est-il le vrai monstre ?
