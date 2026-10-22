# Historique des versions

## 1.10.3

### Ajouts
- **Combats de boss découpés sans DBM.** Le premier coup échangé avec une créature de boss (dégât, raté, esquive ou parade) ouvre le combat de boss. Les monstres combattus depuis plus de 3 s restent dans leur propre combat.
- Le boss vu dans le journal et sa mort sont relayés au groupe : un joueur trop loin découpe et conclut au même instant.
- La fin d'un combat vue par un coéquipier fixe aussi la fin chez un joueur parti hors de portée.

### Modifications
- DBM, s'il est installé, sert seulement à confirmer la victoire ou l'échec. Il ne décide plus du découpage, pour que les joueurs avec et sans DBM découpent de la même façon.

## 1.10.2

- Les annonces de DBM sont relayées aux joueurs qui ne l'ont pas. Ce relais est remplacé en 1.10.3 par une détection propre à Zénith.

## 1.10.1

### Synchronisation
- Les absorptions **reçues** sont annoncées par lanceur : un bouclier est crédité même quand le lanceur était loin de sa cible.
- Plus de comptage en double quand deux clients ont découpé différemment, y compris quand un combat trop court n'a pas été gardé.
- Un écart de moins d'une seconde, dû à la latence, ne modifie plus les durées.
- Les compléments arrivés après la fin d'un combat entrent dans la relecture, le graphique et les records, sans déborder sur le combat voisin.

### Corrections
- Plantage possible des infobulles en mode « Excès de soins » (`Modes.lua`).
- Un familier adverse pouvait faire passer un combat de JcJ sauvage pour un boss.
- Les ratés, esquives et parades n'ouvraient ni ne prolongeaient un combat.
- Un coup entièrement absorbé hors combat n'usait pas le bouclier.
- Les ratés de Frappe-tempête et de Mutilation (main gauche) apparaissaient sur une ligne séparée.
- Un bouclier dont la disparition n'avait pas été vue restait en mémoire indéfiniment.
- Un rapport dans le chat pouvait être coupé au milieu d'un caractère accentué.

### Performances
- Une fenêtre qui affiche un combat terminé n'est plus recalculée en direct.
- L'option « Masquer hors groupe » ne force plus un recalcul toutes les 2 s.
- Le panneau de détails ne remet plus ses lignes en forme chaque seconde.

## 1.10.0

### Ajouts
- **Synchronisation de groupe** : chaque joueur partage ses propres dégâts, soins, absorptions, dégâts subis et temps d'activité. Ce qui était hors de portée du journal de combat est récupéré et affiché sur une ligne « Hors de portée (synchronisé) ».
- **Durée commune** : les débuts et fins de combat sont alignés sur ce que voit le groupe.
- Option « Synchroniser avec le groupe » (Options › Combat).
- Le bilan de fiabilité d'un combat indique ce qui a été récupéré auprès du groupe.

## 1.9.2 et versions antérieures

Versions publiées avant la tenue de ce journal.
