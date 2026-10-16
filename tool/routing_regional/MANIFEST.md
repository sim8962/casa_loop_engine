# Pack de routage régional — Casablanca / Settat

## Identité

| Élément | Valeur |
|---|---|
| Archive | `graph/routing_regional.tar` |
| Taille de référence | 85 913 600 octets |
| SHA-256 attendu | `090c7a4f07ff90a3ac2845f378d712599e4ebd428432e660030831dc55c4456a` |
| Gabarit | `graph/valhalla.template.json` |
| Version Valhalla consignée | 3.9.1 ; intégration iOS `valhalla-mobile` 0.6.4 |
| Source | Geofabrik `africa/morocco`, données OSM du 9 octobre 2026 |
| Extraction | Emprise `-8.9,32.0,-6.6,33.85`, stratégie `smart` |
| SHA-256 de l’extrait source | `274af328f089c7da8e5bcf51723623d8bda00c1d60af96b3978ec22fcfa5a533` |

Zone demandée : Casablanca, Settat, Berrechid, El Jadida, Sidi Bennour, Ben Guerir, El Gara, Ben Ahmed et Khouribga. La stratégie d’extraction conserve les membres de relations et peut inclure des données au-delà de cette emprise. La présence d’une route ne garantit pas son accessibilité pour un profil donné.

## Utilisation

L’identité attendue par l’application est définie dans [AppConfig](../../lib/helpers/constants/app_config.dart). Le service installe le graphe dans le dossier applicatif `routing/`, vérifie son SHA-256 en flux avant configuration du moteur et réécrit les chemins du gabarit. Il réutilise ensuite la configuration pour les segments suivants.

Le fond de carte MBTiles est une ressource distincte. Les packs ne sont pas installés automatiquement avec l’application.

## Outils du projet

- Construction : `scripts/build_pack.sh`.
- Contrôle : `../routing_proof/scripts/validate_regional_pack.sh`.
- Installation de développement sur simulateur : `../routing_proof/scripts/install_regional_pack.sh`.

Leur exécution nécessite un mandat adapté : téléchargement, génération, calcul ou écriture dans le simulateur ne sont pas autorisés par ce manifeste.

Les identités et données de provenance ci-dessus sont des références ; les fichiers volumineux n’ont pas été rehachés pendant le nettoyage documentaire. Le manifeste ne prouve ni une validation sur téléphone physique ni une validation Android.
