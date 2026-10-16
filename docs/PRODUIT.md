# CASA LOOP — Produit et UI/UX

## Usage

Préparer une boucle moto sur téléphone, hors ligne après installation des ressources régionales, puis exporter le tracé vers une application compatible GPX. L’application ne fournit pas de guidage pendant la conduite.

## Fonctions existantes

| Parcours | Fonction |
|---|---|
| Préparer | Créer et nommer un trajet ; ajouter des repères sur la carte ou par recherche locale, les déplacer, les supprimer et les ordonner. |
| Régler | Choisir une préférence et une couleur pour chaque tronçon, retour au départ compris. Le curseur couvre Rapide, Routier, Équilibré, Pistes et Tout-terrain. |
| Calculer | Calculer la boucle avec Valhalla et afficher les mesures moteur. Une cible distance ou durée permet de rechercher une variante. |
| Conserver | Enregistrer un trajet et sa géométrie calculée, créer une copie, charger un tracé sauvegardé sans recalcul. |
| Exporter | Générer un GPX depuis le tracé retenu et ouvrir le partage système. |

Les préférences orientent le moteur sans garantir un type de voie ; Tout-terrain ne signifie pas routage libre hors réseau. Les durées moteur sont des estimations hors pauses. La recherche de cible ne garantit pas d’atteindre la distance ou la durée demandée.

## Écrans à travailler

| Écran | Points à examiner lors du prochain lot UI/UX |
|---|---|
| Carte | Lisibilité des repères, place du résumé, visibilité des commandes, distinction des états de calcul et d’erreur. |
| Repères choisis | Ordre et noms des repères, compréhension des préférences, retour au départ, cible, actions de sauvegarde et de calcul. |
| Recherche et feuilles de repères | Lisibilité des résultats, accès avec le clavier ouvert, fermeture et retour à la carte. |
| Bibliothèque | Lisibilité des noms, distinction tracé enregistré / à calculer, compréhension de Charger et Éditer. |

Ce tableau définit les sujets d’observation, pas des défauts reproduits ni des modifications déjà approuvées. Examiner les écrans actuels avant de proposer une nouvelle disposition.

## Contraintes du travail UI/UX

Préserver les fonctions, calculs, données sauvegardées et formats existants. Préférer des libellés simples, une hiérarchie visible des actions, un texte lisible et des zones tactiles accessibles. Vérifier petits écrans, paysage, clavier et texte agrandi dans le mandat concerné.

Ne pas introduire de nouvel écran, réglage ou comportement métier sans périmètre explicite. Le guidage, CarPlay et Android Auto restent exclus. L’iPad n’est pas une cible obligatoire.

## Limites connues

- iOS : moteur natif intégré ; validation sur téléphone physique non établie ici. Android : intégration native reportée.
- Packs : dépôt séparé requis ; pas de parcours complet d’installation destiné à l’utilisateur.
- Modification des repères ou préférences : le tracé courant est effacé. « Tracer » sauvegarde avant le calcul ; sur un trajet existant modifié, l’ancien tracé enregistré peut donc être remplacé par une sauvegarde sans géométrie avant le résultat du calcul.
- Variante : un meilleur résultat est appliqué automatiquement ; aucun retour utilisateur au résultat précédent n’est présent.
- Annulation : pas d’action d’arrêt du calcul principal ; l’arrêt de recherche ne garantit pas l’interruption de l’appel natif en cours.
- GPX : points consécutifs identiques dédupliqués, tronçons jointifs regroupés et coordonnées écrites à sept décimales. Un statut de partage indisponible est traité comme un échec.
- Les contrôles du snapshot ne constituent pas une empreinte cryptographique d’intégrité du tracé. Aucun mode de consultation dégradée sans fond cartographique n’a été identifié lors de la lecture du code.

Ces limites ne constituent pas un mandat de correction. Aucune recette de l’application n’a été exécutée pendant le nettoyage documentaire.

## Repères techniques

Flutter/GetX ; état partagé dans `RouteEditorController` ; injection dans `AppBinding` ; persistance ObjectBox et GetStorage ; carte MapLibre/MBTiles ; routage Valhalla par pont natif iOS ; partage via `share_plus`.

Le [manifeste régional](../tool/routing_regional/MANIFEST.md) décrit les ressources de routage.
