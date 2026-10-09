# CASA LOOP ENGINE

Application Flutter de préparation de boucles moto, avec priorité à l’iPad et au fonctionnement hors ligne après installation des packs.

## Documentation

- [Plan de reprise iPad](docs/CASA_LOOP_ENGINE_docs_phase_C/PLAN_REPRISE_IPAD_2026-10-04.md) : état actuel, limites et étapes P0–P9.
- [Spécification produit](docs/CASA_LOOP_ENGINE_docs_phase_C/CASA_LOOP_ENGINE_SPECIFICATION_UNIFIEE_OFFLINE_final.md) : fonctions attendues et règles de stockage.
- [Journal historique](docs/CASA_LOOP_ENGINE_docs_phase_C/rapport_travail_fait.md) : travaux antérieurs et nettoyage.

## État actuel

Carte MapLibre, recherche locale ObjectBox, repères et brouillon sont présents dans le code. Valhalla embarqué, génération réelle de boucle, bibliothèque et export GPX restent à implémenter. Les distances actuelles sont indicatives.

`assets/data/` contient les datasets embarqués. `dev_data/` conserve les sources cartographiques et routières, exclues de Git. `tool/` contient les scripts de génération des datasets.

Le chemin MBTiles par défaut vise encore l’ancien environnement Mac. L’installation des packs dans le stockage de l’iPad est prévue dans P1.

## Vérification

```sh
flutter pub get
flutter analyze
flutter test
```

Le dossier `test/` est actuellement vide : la dernière commande ne valide donc aucune suite. Les résultats de tests d’août 2026 sont historiques. Le dossier actuel ne contient pas de dépôt Git.
