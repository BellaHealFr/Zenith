# Contribuer à Zénith

Merci de vouloir améliorer Zénith ! Que vous soyez joueur ou développeur, il y a une place pour vous.

## Signaler un problème ou proposer une idée

Ouvrez un ticket dans l'onglet **Issues** et choisissez le formulaire :
- **Signaler un problème** : erreur Lua, chiffres différents entre joueurs, chiffre faux, affichage ;
- **Proposer une idée** : nouvelle mesure, amélioration de l'interface.

Pour un écart de chiffres entre deux joueurs, le plus utile est une **capture des deux fenêtres sur le même combat**, avec la version de Zénith de chacun.

Avant d'ouvrir un ticket, vérifiez qu'il n'existe pas déjà.

## Proposer une modification du code

1. **Discutez-en d'abord** dans un ticket si la modification est importante : cela évite de travailler pour rien.
2. Créez une copie du dépôt (*Fork*), puis une branche au nom parlant (`correction-boucliers`, `mesure-interruptions`…).
3. Lisez **[docs/CONSTRUCTION.md](docs/CONSTRUCTION.md)**, qui explique le fonctionnement complet. Sa section [Contribuer](docs/CONSTRUCTION.md#contribuer) donne les règles :
   - Lua 5.1 et API 3.3.5 uniquement ;
   - aucune bibliothèque embarquée ;
   - textes en français ;
   - compatibilité des données sauvegardées et du protocole de synchronisation.
4. **Testez en jeu** sur un client 3.3.5a, en groupe si la modification touche le combat ou la synchronisation.
5. Ouvrez une demande de fusion (*Pull Request*) et remplissez la liste de vérifications.

La vérification automatique (syntaxe Lua 5.1, fichiers du `.toc`, numéros de version, en-têtes de licence) doit être verte.

## Style

- Une tabulation pour l'indentation des fichiers Lua.
- Fonctions de l'API copiées dans des variables locales en tête de fichier.
- Commentaires en français, qui expliquent **pourquoi** plutôt que **quoi**.
- Messages de commit courts, en français, à l'infinitif : « Corriger l'attribution d'Égide divine », « Ajouter la mesure des interruptions ».

## Licence des contributions

Zénith est publié sous **GPL-3.0** avec les conditions supplémentaires de [`NOTICE.md`](NOTICE.md). Toute contribution est publiée sous cette même licence. Vous restez l'auteur de votre contribution, et votre nom apparaît dans l'historique du dépôt.
