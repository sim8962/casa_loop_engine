# CASA LOOP ENGINE

Application Flutter de préparation de boucles moto hors ligne : choisir les repères, régler chaque tronçon, calculer une boucle, enregistrer le tracé et exporter un GPX.

## Documentation

- [Produit et UI/UX](docs/PRODUIT.md) : fonctions existantes, écrans et limites.
- [Règles des agents](AGENTS.md) : périmètre et validations.
- [Pack régional](tool/routing_regional/MANIFEST.md) : fichiers, couverture et intégrité.

## État de l’application

Le socle iOS est implémenté. Les validations disponibles concernent le simulateur ; la validation sur iPhone physique reste à établir. Android est une cible reportée : le pont natif de routage reste à réaliser.

Les ressources cartographiques et routières doivent être installées séparément. Le guidage embarqué, CarPlay et Android Auto sont hors périmètre.

Le travail actuel porte sur la préparation du déploiement. Le dossier de tests a été supprimé à la demande de l’utilisateur ; aucune nouvelle validation de livraison n’en découle.
