<div align="center">

# Zénith

**Compteur de combat pour World of Warcraft 3.3.5 (Wrath of the Lich King)**

*Par un passionné de Wrath of the Lich King, pour tous ceux qui continuent de faire vivre le Norfendre.*

![Client](https://img.shields.io/badge/client-3.3.5a-1e90ff)
![Lua](https://img.shields.io/badge/Lua-5.1-000080)
![Dépendances](https://img.shields.io/badge/d%C3%A9pendances-aucune-success)
![Langue](https://img.shields.io/badge/langue-fran%C3%A7ais-informational)
![Licence](https://img.shields.io/badge/licence-GPL--3.0-blue)

</div>

---

Zénith mesure tout ce qui se passe en combat : dégâts, soins, boucliers, dégâts subis, morts, auras. Il ne se contente pas d'afficher des barres : il explique chaque chiffre, analyse votre combat en phrases simples et permet de le revoir seconde par seconde.

Il a été conçu pour les joueurs passionnés de la 3.3.5, ceux qui enchaînent les raids et veulent des chiffres justes, un outil qui ne casse pas en plein combat, et une interface pensée pour cette extension plutôt qu'adaptée d'une autre version du jeu.

## Par un passionné, pour les passionnés

Pour beaucoup d'entre nous, Wrath of the Lich King reste l'extension de référence. Naxxramas suspendue au-dessus de la Désolation des dragons. Les modes difficiles d'Ulduar, les soirées passées à apprendre chaque phase de Yogg-Saron, et le défi d'Algalon l'Observateur. L'Épreuve du croisé et ses tentatives comptées. Puis l'ascension de la Citadelle de la Couronne de glace, aile après aile, jusqu'au Trône de glace et au dernier face-à-face avec Arthas.

Des années plus tard, des milliers de joueurs continuent de faire vivre le Norfendre. Ils méritent des outils à la hauteur de ces combats, et Zénith est né de cette conviction.

Il n'a pas été adapté d'une autre version du jeu : chaque ligne a été écrite pour le client 3.3.5, en pensant aux rencontres qu'on y mène vraiment.

- **Les rencontres à plusieurs boss sont reconnues comme un seul combat**, sous leur vrai nom, avec leur propre règle de victoire : le Conseil des princes de sang et ses trois princes, l'Assemblée du fer, les Jumelles val'kyrs, les Quatre cavaliers, la Bataille des canonnières, Valithria Marcherêve.
- **Les mécaniques propres à l'extension sont prises en compte** : les véhicules d'Ulduar et de la Couronne de glace, les essences des Jumelles val'kyrs qui ne sont créditées à personne, la Marque de sang du chevalier de la mort, le Renvoi de sort du guerrier, les absorptions propres aux tanks (talents Défenseur ardent et Volonté de la nécropole, bonus Stoïcisme du tier 10 guerrier).
- **Les records et les essais suivent la logique du raid** : un record par boss et par difficulté (10 ou 25, normal ou héroïque), et un compteur d'essais qui accompagne votre progression jusqu'à la victoire.
- **L'interface est entièrement en français**, avec les noms de sorts et de boss que vous voyez en jeu.

L'objectif est simple : vous laisser vous concentrer sur le combat, essai après essai, avec un compteur juste, fiable, et qui ne vous lâche pas au moment où le Roi-liche entame sa dernière phase.

## Pourquoi Zénith

### Des chiffres justes, et les mêmes pour tout le groupe

Dans la 3.3.5, chaque jeu ne lit que son propre journal de combat. Ce journal a une portée limitée : ce qui se passe trop loin de vous n'y apparaît pas. Et chaque compteur décide seul du moment où un combat commence et finit. Deux joueurs du même raid affichent donc rarement les mêmes chiffres, et celui qui était à l'écart voit les autres faire moins de dégâts qu'en réalité.

Zénith corrige ce problème à la source :

- **Synchronisation de groupe.** Le jeu de chaque joueur voit toujours tout ce que ce joueur fait, même loin des autres. Chaque Zénith partage donc ses propres totaux avec le groupe, et chacun récupère ce que son journal a manqué. Rien n'est jamais compté deux fois.
- **Durée commune.** Le DPS dépend de la durée du combat. Zénith aligne le début et la fin du combat sur ce que voit le groupe : tout le monde divise par le même temps.
- **Combats de boss découpés au bon moment.** Quand des monstres sont enchaînés sur un boss, le combat de boss commence au premier coup échangé avec lui, au même instant chez tous les joueurs. Cela ne dépend d'aucun autre addon : DBM n'est pas nécessaire.
- **Boucliers attribués à leur lanceur.** Le journal de la 3.3.5 dit combien de dégâts ont été absorbés, mais pas par quel bouclier. Zénith reconstitue l'ordre dans lequel le serveur consomme les boucliers, pour créditer chaque absorption au bon prêtre, paladin ou mage.

Exemple sur un combat de boss simulé, avec un mage à 4 770 DPS réels et un second joueur placé loin de lui pendant 15 secondes :

| | Ce que voit le mage | Ce que voit l'autre joueur |
|---|---|---|
| Journal local seul | 4 770 DPS | 3 152 DPS (−34 %) |
| Zénith | 4 770 DPS | 4 770 DPS |

### Conçu pour jouer sans être gêné par des bugs

Un compteur ne doit jamais devenir un problème en plein raid. Zénith a été construit avec cette priorité :

- **Réparation automatique du journal de combat.** Le client 3.3.5 a un bogue connu : son journal cesse parfois de fonctionner, et tous les compteurs s'arrêtent avec lui. Zénith détecte la panne et relance le journal sans intervention.
- **Aucune dépendance.** Zénith n'embarque aucune bibliothèque externe : pas de conflit de versions avec vos autres addons.
- **Démarrage contrôlé.** Si un fichier manque après une mise à jour faite jeu ouvert, Zénith l'indique clairement et reste inactif, au lieu d'afficher une cascade d'erreurs.
- **Erreurs isolées.** Les tâches périodiques (fin de combat, synchronisation, inspection) sont protégées : une erreur inattendue est signalée sans arrêter les autres.
- **Bilan de fiabilité.** Pour chaque combat, Zénith indique si des données ont pu manquer et pourquoi : panne du journal, familier non identifié, bouclier inconnu, données récupérées auprès du groupe.
- **Léger.** Le traitement du journal est optimisé pour les raids de 25 joueurs, et les fenêtres ne se recalculent que lorsque c'est utile.
- **Vérifié.** Le comportement à plusieurs joueurs a été testé en simulation, avec ou sans DBM, joueur à portée ou non. Chaque modification publiée passe une vérification automatique.

### Comprendre, pas seulement mesurer

Chaque mesure est expliquée en une phrase, avec son niveau de confiance : chiffre exact lu dans le journal, ou part d'estimation (boucliers, temps d'activité). Un joueur qui débute comprend ce qu'il voit, et un joueur confirmé sait exactement d'où vient chaque chiffre.

## Fonctionnalités

### Les fenêtres

Chaque fenêtre affiche une mesure, sous forme de barres classées, pour le combat en cours, un combat passé ou le total. Vous pouvez ouvrir jusqu'à cinq fenêtres, par exemple les dégâts dans l'une et les soins dans l'autre. Survolez une barre pour voir les sorts principaux du joueur, cliquez dessus pour ouvrir sa fiche complète.

**26 mesures**, réparties en cinq familles :

| Famille | Mesures |
|---|---|
| Dégâts | dégâts infligés, DPS, DPS en direct, dégâts par ennemi, dégâts infligés aux alliés |
| Tank et survie | dégâts subis, dégâts subis rapportés aux PV max, défense du tank (bloqué, absorbé, résisté), évitement, dégâts subis par sort ennemi, morts |
| Soins | soins et absorptions, soins seuls, absorptions seules, excès de soins, SPS, soins reçus |
| Ennemis et JcJ | dégâts infligés par les ennemis, soins des ennemis, joueurs adverses vaincus |
| Utilitaire | coups fatals, résurrections, interruptions, dissipations, temps d'activité, menace |

Le mode simple ne montre que les mesures essentielles, le mode expert les montre toutes.

### La fiche d'un joueur

Un clic sur une barre ouvre la fiche complète du joueur pour ce combat, en huit onglets :

- **Dégâts, Soins, Dégâts subis, Sur alliés** : chaque sort avec son total, sa part, le nombre de coups, la moyenne, les moyennes normale et critique, le minimum et le maximum, les critiques, les ratés et leur nature (esquive, parade, résistance…), les montants absorbés ou bloqués. À côté, les cibles touchées, les joueurs soignés ou les sources des dégâts subis.
- **Auras** : la part du combat pendant laquelle chaque amélioration et chaque affaiblissement était actif. Utile pour vérifier qu'un débuff important est bien maintenu.
- **Graphique** : le DPS ou le SPS au fil du combat, avec la moyenne et les morts marquées.
- **Morts** : pour chaque mort, les derniers coups reçus et soins avant la mort, avec les points de vie restants à chaque instant.
- **Analyse** : un bilan rédigé, par exemple :
  > Classement : 2e sur 10 aux dégâts, soit 14,2 % du total du groupe.
  > Temps d'activité : 91,0 % du combat. Excellent rythme.
  > Attaques ratées, esquivées ou parées : 7,5 %. Vérifiez vos scores de toucher et d'expertise.

### Relecture d'un combat

Un combat terminé peut être rejoué : le classement évolue seconde par seconde, comme une vidéo, et vous pouvez avancer ou reculer à votre guise. C'est le meilleur moyen de voir à quel moment un essai a basculé.

### Records et essais

Votre meilleur DPS et votre meilleur SPS sont mémorisés pour chaque boss et chaque difficulté. Lors des combats suivants, le pied de la fenêtre affiche en direct votre avance ou votre retard sur ce record. Zénith compte aussi les essais sur chaque boss jusqu'à la victoire.

### Combats enregistrés

Zénith garde les derniers combats (10 par défaut), nommés d'après le boss ou l'ennemi principal, avec leur issue : « (vaincu) » ou « (échec n° 3) ». Une option ne conserve que les combats de boss. Les données peuvent être gardées d'une session à l'autre, et Zénith propose de les effacer en entrant dans une nouvelle instance.

### Spécialisation et rôle

Zénith reconnaît la spécialisation et le rôle (tank, soigneur, dégâts) de chaque membre du groupe, et peut afficher l'icône correspondante sur les barres.

### Rapport

Le classement affiché peut être envoyé en un clic dans le groupe, le raid, la guilde, les officiers, en chuchotement à votre cible ou dans votre seule fenêtre de discussion.

### Résumé de fin de combat

À la fin de chaque combat, un court bandeau indique votre classement et votre DPS ou SPS, puis disparaît.

### Personnalisation

Six thèmes de couleurs, cinq textures de barres, quatre polices, la taille du texte, la hauteur des barres, l'échelle des fenêtres, la fréquence de rafraîchissement. Les fenêtres peuvent se masquer automatiquement hors combat ou hors groupe. Tout se règle dans un panneau d'options en français, sans rechargement de l'interface.

## Installation

1. Téléchargez `Zenith-x.y.z.zip` dans **[Releases](../../releases)**.
   > **Attention** : n'utilisez pas le bouton vert *Code → Download ZIP*, qui produit un dossier `Zenith-main` que le jeu ne charge pas.
2. Quittez complètement le jeu.
3. Décompressez l'archive dans `World of Warcraft/Interface/AddOns/`. Vous devez obtenir `AddOns/Zenith/Zenith.toc`.
4. Relancez le jeu.

Pour profiter de la synchronisation, les membres du groupe doivent eux aussi utiliser Zénith, de préférence dans la même version.

## Commandes

| Commande | Effet |
|---|---|
| `/zenith` ou `/zn` | ouvrir les options |
| `/zenith aide` | revoir la présentation pour débuter |
| `/zenith basculer` | afficher ou masquer les fenêtres |
| `/zenith nouvelle` | créer une fenêtre |
| `/zenith verrou` | verrouiller ou déverrouiller les fenêtres |
| `/zenith reinit` | effacer toutes les données |
| `/zenith memoire` | mémoire utilisée par l'addon |

## Sous le capot

| | |
|---|---|
| Client | 3.3.5a (build 12340), `## Interface: 30300` |
| Langage | Lua 5.1, API WoW 3.3.5 |
| Dépendances | aucune. LibBossIDs, LibGroupTalents et DBM sont mis à profit s'ils sont présents. |
| Code | environ 6 700 lignes, 10 fichiers |

Le fonctionnement complet est décrit dans **[docs/CONSTRUCTION.md](docs/CONSTRUCTION.md)** : architecture, lecture du journal de combat, attribution des boucliers, découpage des combats, protocole de synchronisation, interface, performances et vérification.

L'historique des versions est dans **[CHANGELOG.md](CHANGELOG.md)**.

## Contribuer

Les signalements de bugs et les suggestions sont les bienvenus dans l'onglet **Issues**. Pour un écart de chiffres entre deux joueurs, joignez une capture des deux fenêtres pour le même combat.

Pour proposer une modification du code, lisez **[CONTRIBUTING.md](CONTRIBUTING.md)**.

## Licence

Copyright (C) 2026 BellaHealFr.

Zénith est un logiciel libre distribué sous **GNU GPL v3** (`GPL-3.0-only`), avec des conditions supplémentaires prévues par l'article 7 de la licence. Vous pouvez l'utiliser, l'étudier, le modifier et le redistribuer. Toute version redistribuée, modifiée ou non, doit :

- rester sous la même licence, code source compris ;
- conserver la mention de l'auteur ;
- si elle est modifiée, être clairement signalée comme différente de l'original, sous **un autre nom que « Zénith »** et avec un autre dossier d'installation.

Texte complet : [`LICENSE`](LICENSE). Conditions supplémentaires : [`NOTICE.md`](NOTICE.md).

World of Warcraft est une marque de Blizzard Entertainment. Ce projet n'est ni affilié à Blizzard Entertainment, ni approuvé par lui.

---

<div align="center">

Créé par **BellaHealFr**

*Pour tous ceux qui n'ont jamais quitté le Norfendre.*

</div>
