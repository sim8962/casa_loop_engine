# Rapport d'étude — moteur de routage hors ligne (iPhone + Android)

Date : 2026-10-06 — *mise à jour 3 : recette arrêtée (complément « clôturer la
recette »). Toutes les versions et options ci-dessous sont vérifiées dans les
sources publiques citées, pas déduites.*
Projet : CASA LOOP ENGINE (`/Users/macjam/Desktop/casa_loop_engine`)
Type : reconnaissance technique en lecture seule — **seul ce rapport a été modifié**

> Cibles confirmées : **iPhone ET Android, dès la première version** — validation
> sur appareil physique iPhone **et** appareil physique Android, en mode avion.
> Une réussite sur une plateforme ne valide pas l'autre.
> Modèles et versions des appareils de test : **inconnus, information à obtenir**
> (ne bloque pas la préparation de la recette).

> Note : le README référence des documents dans `docs/CASA_LOOP_ENGINE_docs_phase_C/`
> qui n'existent pas dans ce projet (dossier vide). L'étude a été menée sans eux ;
> toute décision dépendant de la spécification manquante est signalée comme assumée.

---

## 1. Constat de reconnaissance

### 1.1 Ce qui est déjà utilisable

- `RouteEditorController.traceRoute()` appelle `saveDraft()` puis journalise
  `routeComputationNotImplemented` — **aucun calcul n'est fait** ; stub assumé
  (`lib/controllers/route_editor_controller.dart`).
- Bouton « Tracer » : message honnête « calcul de la boucle à implémenter ».
- Réglages par segment : `segmentRoutePreferences` (0–100, Rapide → Trail),
  segment dirigé, boucle fermée. Seul réglage utilisateur existant.
- `MapController` (MapLibre) : cercles, drag, caméra — aucune primitive de tracé
  utilisée (ni `addLine`, ni `addLineLayer`/`addGeoJsonSource`).
- `OfflineMapService` : modèle d'installation MASTER → répertoire applicatif
  via `path_provider` avec copie atomique — déjà multiplateforme, réutilisable
  pour le graphe.
- `flutter analyze --no-pub` exécuté le 2026-10-06 : **aucune issue** (les 3
  imports corrigés vers `lib/routes/` sont confirmés sur disque).

### 1.2 Ce qui manque

- Aucun moteur de routage intégré (pas de `http`, FFI ni package de routage).
- Aucun graphe routable : `dev_data/routing_source/` ne contient que des PBF
  bruts (`roads_maroc.osm.pbf` ~114 Mo, `roads_core_maroc.osm.pbf` ~91 Mo) ;
  `valhalla/` ne contient qu'une copie du même PBF. Aucun binaire Valhalla sur
  la machine (ni brew, ni docker).
- `routes.json`/`RoadEntity` : index de recherche, **pas un graphe**.
- Le MBTiles (472 Mo) : fond d'affichage, **pas un graphe routable**.

### 1.3 Contexte technique projet (vérifié)

- iOS : `IPHONEOS_DEPLOYMENT_TARGET = 15.0` (pbxproj) ; Podfile `platform` à
  15.0 commentée.
- Android : `minSdk = flutter.minSdkVersion` → **24** à la révision Flutter du
  projet (`6655482`, candidat 3.47 ; `FlutterExtension.minSdkVersion = 24`,
  `compileSdkVersion = 36`, `ndkVersion = 28.2.13676358` vérifiés dans les
  sources Flutter à ce commit). `MainActivity.kt` présent
  (`android/app/src/main/kotlin/com/casaloopengine/casa_loop_engine/`).
- `maplibre_gl 0.27.1` : `addGeoJsonSource` + `addLineLayer` (casing + ligne)
  — identique sur les deux plateformes.

---

## 2. Comparaison (non reprise — conclusion maintenue)

Valhalla via `Rallista/valhalla-mobile` reste le choix : seul chemin où le
moteur embarqué est déjà publié en binaire **sur les deux plateformes** avec
costing par requête incluant un profil `motorcycle`. OSRM disqualifié (profil
Lua cuit dans le graphe, pas de profil moto, aucun chemin iOS maintenu).
Détails de la comparaison dans la version précédente de ce rapport (historique
chat) — la table est remplacée ci-dessous par les épingles vérifiées.

## 3. Versions épinglées — preuves

| Élément | iOS | Android |
|---|---|---|
| Package publié | SPM `github.com/Rallista/valhalla-mobile`, tag **`0.6.4`** (commit `852dd75`, publié 2026-10-06) | Maven Central **`io.github.rallista:valhalla-mobile:0.6.4`** (aar, vérifié sur central.sonatype.com) |
| Artefact | `valhalla-wrapper.xcframework.zip` sur GitHub Releases, SHA256 `c12b796de073e89f6b0be02cbfabf845a324166467609268d747c094d27ddb47` (déclaré dans `Package.swift` au tag 0.6.4) | AAR avec `libvalhalla-wrapper.so` par ABI ; transitives : `valhalla-models`/`valhalla-models-config` 0.6.0, `osrm-openapi` 0.0.10 (stadiamaps), moshi 1.15.1, core-ktx 1.13.1, kotlin-stdlib 2.2.10 |
| Noyau moteur | `src/valhalla @ bafb699` = **valhalla 3.9.1** (commit « Release 3.9.1 », 2026-10-01) | **identique** — même submodule du repo, même commit |
| OS minimum | iOS **16.4** (`Package.swift` au tag) ; arch device arm64 | minSdk **24** ; ABIs arm64-v8a, armeabi-v7a, x86_64, x86 (build.gradle.kts au tag) |
| Licence | MIT | MIT |

**Compatibilité graphe** : les deux artefacts de la release 0.6.4 partagent le
même submodule `src/valhalla @ bafb699` — la parité iOS/Android est garantie
**par construction** au sein d'une release. Le graphe doit être construit avec
les outils de **valhalla upstream au commit `bafb699` (tag `3.9.1`)** pour
correspondre au format de tuiles attendu.

**Réserve de fraîcheur** : 0.6.4 est publié le 2026-10-06 (jour même). Si
Codex préfère une version décantée : **0.6.3** (28 août, commit `b47ad5a`,
submodule `src/valhalla @ e2f017b` — tag upstream correspondant à identifier
lors du build). La recette ci-dessous épingle 0.6.4 ; chaque mention est
substituable par son homologue 0.6.3.

## 4. Contrat commun (les deux plateformes)

Canal : `MethodChannel("casa/routing")`, JSON Valhalla **natif** (pas OSRM),
`units: "kilometers"` explicite.

- `configure` → chemin absolu du `valhalla.json` on-device ; construit l'instance.
- `route` → entrée : chaîne JSON de la requête `route` Valhalla complète ;
  sortie : chaîne JSON de la réponse brute.
  - iOS : `Valhalla.route(rawRequest: String) throws -> String` (vérifié dans
    `apple/Sources/Valhalla/Valhalla.swift` @ 0.6.4).
  - Android : `Valhalla.routeRaw(requestJson: String): String` (vérifié dans
    `Valhalla.kt` @ 0.6.4 ; couche JNI `ValhallaKotlin.route(handle, ByteArray)`).
  - Erreurs : enveloppe native `{"code": int, "message": string}` → convertie
    en `PlatformException` puis en erreur Dart normalisée.

Requête minimale de la preuve :

```json
{
  "locations": [{"lat": <A.lat>, "lon": <A.lon>}, {"lat": <B.lat>, "lon": <B.lon>}],
  "costing": "motorcycle",
  "units": "kilometers",
  "format": "json"
}
```

Décodage Dart : `trip.summary.length` (km), `trip.summary.time` (s),
`trip.legs[].shape` (polyline6 → décodeur ~40 lignes, pas de dépendance).

Cycle de vie requis par les deux APIs (vérifié dans les sources) :
- les appels sont **synchrones** (`throws`/`fun` bloquants) → dispatch hors
  thread UI : iOS file série `DispatchQueue` dédiée (ou `Task.detached`),
  Android `Dispatchers.IO` + `Mutex` (l'`ValhallaActor` interne synchronise
  déjà sous `synchronized`) ;
- **une seule instance moteur réutilisée** (le constructeur charge l'actor +
  les tuiles mmappées — coûteux ; `close()` pour libérer) ;
- appels **sérialisés** côté Dart (file de `Future` chaînées) + compteur de
  requêtes → toute réponse arrivant après une requête plus récente est
  **ignorée** (pas de résultat obsolète affiché).

## 5. Options `motorcycle` — vérifiées dans valhalla 3.9.1

Lu dans `src/sif/motorcyclecost.cc` et `src/sif/dynamiccost.cc` **au tag 3.9.1**
(le code embarqué, pas la doc) :

| Option | Parseur | Effet réel dans 3.9.1 |
|---|---|---|
| `use_highways` (0–1, déf. 0.5) | `ParseMotorcycleCostOptions` | facteur de classe routière (kHighwayFactor : motorway 1.0, trunk 0.5, reste 0) |
| `use_tolls` (0–1, déf. 0.5) | idem | facteur de péage (0 → pénalise, 1 → légère préférence) |
| `use_trails` (0–1, déf. 0.0) | idem | module `kSurfaceFactor` (paved 0 → path 1.0) + biais de classe jusqu'à ×8 ; ≥0.5 favorise pistes/surfaces mauvaises |
| `top_speed` (10–140 km/h) | idem | plafond de vitesse effectif par edge |
| `use_tracks` (0–1, déf. 0.5) | `ParseBaseCostOptions` (`dynamiccost.cc`, `set_use_tracks`) | pénalité ≤300 s + facteur 0.8–4 sur edges `track` |
| `use_living_streets`, `use_distance`, `shortest` | `ParseBaseCostOptions` | options de base disponibles |
| **`use_hills`** | **ABSENT de `MotorcycleCost`** en 3.9.1 (présent dans `autocost`/`bicyclecost`, exige des tuiles d'élévation skadi) | **retiré du mapping** — serait ignoré silencieusement |

**Conséquence honnête** : « Sinueux » n'a **pas de paramètre dédié** ; sa
seule approximation en 3.9.1 est `use_highways` ↓ + `use_trails` modéré —
**non démontrée**, à ne pas présenter comme réalisée. Calibration des cinq
préférences **après** la preuve moteur.

Mapping indicatif pour la calibration ultérieure (valeurs à valider sur
device, jamais annoncées comme appliquées sans différence de géométrie
observée) :

| Préférence (0–100) | `costing_options.motorcycle` proposé |
|---|---|
| Rapide (≤20) | `use_highways: 0.9`, `use_trails: 0.0`, `use_tracks: 0.1`, `use_tolls: 0.5` |
| Routier (≤40) | `use_highways: 0.5`, `use_trails: 0.15`, `use_tracks: 0.3` |
| Sinueux (≤60) | `use_highways: 0.15`, `use_trails: 0.45`, `use_tracks: 0.4` *(approximation)* |
| Aventure (≤80) | `use_highways: 0.1`, `use_trails: 0.7`, `use_tracks: 0.7` |
| Trail (>80) | `use_highways: 0.0`, `use_trails: 1.0`, `use_tracks: 1.0`, `top_speed: 40` |

## 6. Graphe de preuve

### Zone et points

- Zone : **Casablanca intra-muros + périphérie** (emprise carte :
  −9.51…−4.12 E / 31.88…34.25 N). Justification : densité maximale de
  `highway=*` donc meilleure chance de snapping et de contournements —
  suffisant pour la **première preuve** (requête `motorcycle` par défaut).
  Exemple de paire A→B : deux repères choisis dans l'app (tap carte ou
  entrée `routes.json`), typiquement dans Casablanca.
- Crop : `osmium extract -b` sur la bbox englobant A et B **+ marge
  ≥ 15 km** sur chaque côté (les détours de routage peuvent sortir du
  rectangle strict ; une coupure au bord invaliderait la preuve). Exemple
  indicatif : `[-8.0, 33.35, -7.1, 33.8]`. **Pas de build de tout le Maroc**
  pour cette preuve.
- PBF source : **`roads_maroc.osm.pbf`** plutôt que `roads_core_maroc` — non
  parce que plus gros, mais parce que `use_trails`/`use_tracks` et la phase
  suivante (Aventure/Trail) exigent `highway=track`/`surface`/`tracktype`,
  supposés absents ou réduits d'un extract « core ». Décision finale après
  inspection ci-dessous ; si `roads_core_maroc` couvre la zone avec les tags
  requis, les deux conviennent.

### Contrôles de routabilité (fileinfo seul ne suffit pas)

1. `osmium fileinfo -e <pbf>` : bbox d'en-tête, version osmium, replication.
2. `osmium tags-count` sur le **crop** : présence de `highway=*` (avec
   `track`), `maxspeed`, `surface`, `tracktype`, `access`/`motor_vehicle`,
   relations `type=restriction` (restrictions de virage).
3. **Décisif** : `valhalla_run_route` (binaire de test du build) sur les
   tuiles construites, avec les deux points réels — vérifie connectivité et
   snapping **avant** le transfert. C'est un pré-contrôle Mac, **pas** la
   preuve device.

### Méthode de construction recommandée (unique)

Build des outils valhalla depuis les **sources upstream au commit `bafb699`**
sur le Mac. (Alternative : image Docker — Docker absent de la machine,
installation à autoriser séparément ; non retenue.)

Installations hors projet à autoriser :

```sh
brew install cmake pkg-config protobuf protobuf-c boost lz4 \
  spatialite libspatialite sqlite3 luajit curl osmium-tool \
  bash coreutils automake libtool
```

Construction (répertoire hors projet, ex. `~/dev/valhalla_proof/`) :

```sh
git clone https://github.com/valhalla/valhalla.git && cd valhalla
git checkout bafb699            # = tag 3.9.1, version embarquée par 0.6.4
git submodule update --init --recursive

# noms exacts des options à confirmer dans CMakeLists.txt @ bafb699
cmake -B build -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_TOOLS=ON -DENABLE_DATA_TOOLS=ON -DENABLE_SERVICES=OFF \
  -DENABLE_HTTP=OFF -DENABLE_TESTS=OFF -DENABLE_PYTHON_BINDINGS=OFF
cmake --build build -j$(sysctl -n hw.physicalcpu) \
  --target valhalla_build_tiles valhalla_build_config \
           valhalla_build_extract valhalla_run_route
```

Graphe :

```sh
./build/scripts/valhalla_build_config > ~/dev/valhalla_proof/valhalla.json
# éditer : mjolnir.tile_dir, mjolnir.tile_extract=.../routing_proof.tar,
#          mjolnir.timezone absent des tuiles locales (tzdata injecté par la
#          lib sur iOS ; à vérifier côté Android via ValhallaConfigManager)
osmium extract -b -8.0,33.35,-7.1,33.8 --strategy=smart \
  -o ~/dev/valhalla_proof/proof_zone.osm.pbf \
  /Users/macjam/Desktop/casa_loop_engine/dev_data/routing_source/roads_maroc.osm.pbf
./build/valhalla_build_tiles -c ~/dev/valhalla_proof/valhalla.json \
  ~/dev/valhalla_proof/proof_zone.osm.pbf
./build/valhalla_build_extract -c ~/dev/valhalla_proof/valhalla.json -v
# pré-contrôle (pas la preuve device) :
./build/valhalla_run_route -c ~/dev/valhalla_proof/valhalla.json \
  -j '{"locations":[{...A},{...B}],"costing":"motorcycle","units":"kilometers"}'
```

Sortie : `routing_proof.tar` (taille à mesurer — inconnue avant build).

## 7. Installation sur les téléphones (preuve, pas distribution finale)

Le `--dart-define` **ne transfère rien** : il ne fait que pointer vers un
chemin déjà présent sur le device. Le transfert réel, par plateforme :

- **Android** : `adb push routing_proof.tar
  /sdcard/Android/data/com.casaloopengine.casa_loop_engine/files/routing/routing_proof.tar`
  — répertoire externe spécifique à l'app, accessible via `adb` sans root,
  débogage USB requis. Idem pour le MBTiles MASTER :
  `.../files/map_packs/casa_trail_v4_z7_z15.mbtiles`. Les services existants
  copient ensuite le MASTER vers le stockage interne de l'app
  (`getApplicationDocumentsDirectory`, non accessible par adb — normal : la
  copie applicative est l'installation).
- **iOS** : `xcrun devicectl device copy to --device <udid>
  --domain-type appDataContainer --domain-identifier com.casaloopengine.casa_loop_engine
  --source routing_proof.tar --destination Documents/routing_proof.tar`
  (Xcode 15+, app signée en développement — drapeau/syntaxe exacte à valider
  au branchement). Alternative si devicectl échoue :
  `UIFileSharingEnabled=YES` dans `ios/Runner/Info.plist` **[protégé]** +
  glisser-déposer via Finder → Fichiers.

Le chemin passé par `--dart-define` devient alors un **chemin on-device**
(pas `/Users/...`). Distinction : la distribution finale (pack embarqué en
asset ou téléchargement premier lancement) est un choix produit ultérieur,
hors preuve.

## 8. Projet de mandat d'implémentation — fichiers et commandes

### Fichiers (créer / modifier)

| Fichier | Action |
|---|---|
| `ios/Runner.xcodeproj/project.pbxproj` | **[protégé]** SPM `rallista/valhalla-mobile` **exact 0.6.4** + `IPHONEOS_DEPLOYMENT_TARGET` → 16.4 |
| `ios/Podfile` | **[protégé]** `platform :ios, '16.4'` |
| `ios/Runner/AppDelegate.swift` | `MethodChannel("casa/routing")` : `configure` (instancie `Valhalla(configPath:)` une fois) + `route` → `route(rawRequest:)` dispatché hors thread principal |
| `android/app/build.gradle.kts` | **[protégé]** `implementation("io.github.rallista:valhalla-mobile:0.6.4")` ; minSdk déjà 24 via Flutter — **aucune montée requise** |
| `android/app/src/main/kotlin/com/casaloopengine/casa_loop_engine/MainActivity.kt` | `MethodChannel("casa/routing")` : `configure` (`Valhalla(configPath)` une fois) + `route` → `routeRaw(...)` dans `Dispatchers.IO` sous `Mutex` |
| `lib/services/routing/valhalla_route_engine.dart` | **[nouveau]** channel unique : build de la requête JSON, envoi brut, décodage `trip.summary` + polyline6, normalisation des erreurs, file sérialisée + rejet des réponses obsolètes |
| `lib/services/routing/offline_routing_service.dart` | **[nouveau]** install MASTER `.tar` → répertoire applicatif (copie atomique, miroir `OfflineMapService`) + écriture du `valhalla.json` on-device pointant `mjolnir.tile_extract` |
| `lib/models/computed_route.dart` | **[nouveau]** géométrie + distanceKm + durée |
| `lib/controllers/route_editor_controller.dart` | `traceRoute()` : save → A→B (repères 0→1, préférence segment 0) ; `isRouting`/`computedRoute`/`routingError`/`routeRevision` ; invalidation à toute mutation |
| `lib/views/map/controllers/map_controller.dart` | observer `routeRevision` → `addGeoJsonSource`+`addLineLayer` (casing+ligne) + `newLatLngBounds` ; effacement sur invalidation |
| `lib/views/selected_markers/views/selected_markers_view.dart` | état calcul/erreur/distance+durée |
| `lib/views/selected_markers/controllers/selected_markers_controller.dart` | délégations |
| `lib/bindings/app_binding.dart` | enregistrer les services routing |
| `lib/helpers/constants/app_config.dart` | **[protégé]** `routingTarSourcePath` + chemin on-device MBTiles via `--dart-define` |
| `test/services/valhalla_route_engine_test.dart`, `test/controllers/route_editor_trace_test.dart` | **[nouveaux]** polyline6, mapping, erreurs, rejet de réponse obsolète |
| `pubspec.yaml` | **[protégé]** a priori aucune dépendance nouvelle |

### Commandes proposées (à autoriser, non exécutées)

- Mac : `brew install` (liste §6), `git clone`/`checkout`/`submodule` de
  valhalla hors projet, `cmake` configure+build, `osmium fileinfo`,
  `osmium tags-count`, `osmium extract`, `valhalla_build_config`,
  `valhalla_build_tiles`, `valhalla_build_extract`, `valhalla_run_route`.
- Projet : `flutter analyze --no-pub`, `flutter test --no-pub`,
  `flutter pub get` (si dépendance), `pod install` (si Podfile modifié),
  `flutter build ios --debug`, `flutter build apk --debug`,
  `flutter run -d <iPhone>`, `flutter run -d <android>`.
- Devices : `adb push` (Android), `xcrun devicectl device copy to` (iOS) —
  + éventuellement `UIFileSharingEnabled` dans `Info.plist` **[protégé]**.

### Écritures hors projet requises

`~/dev/valhalla_proof/` (clone + build valhalla), `~/dev/vcpkg` **non requis**
(conso binaire uniquement), installations brew, caches SPM/Xcode/Gradle/Maven,
push adb/devicectl vers les devices.

### Critères d'acceptation — sur chaque plateforme (mode avion)

1. App démarre ; `routing_proof.tar` présent dans le stockage applicatif ;
   `valhalla.json` écrit avec chemin absolu on-device.
2. Deux repères → Tracer → requête `motorcycle` exécutée **sur device**
   (log Diag + durée mesurée, thread UI non bloqué).
3. Ligne MapLibre suit le réseau visible ; caméra cadrée.
4. Distance (`trip.summary.length`, km) et durée (`time`, s) affichées —
   aucune valeur haversine.
5. Requête avec `use_highways:0.9` vs `use_highways:0` produit des géométries
   différentes sur au moins une paire de repères — sinon constat honnête.
6. Erreurs explicites : graphe absent, repère non snappable, échec moteur,
   réponse obsolète rejetée.
7. Mutation repère/préférence après calcul → tracé invalidé/effacé.

## 9. Inconnues restantes et décisions à prendre

1. **Appareils de test** : modèles + versions iOS/Android à obtenir.
2. **iPhone ≥ iOS 16.4** — si l'iPhone cible est en 15.x, la cible ne peut pas
   monter sans nouveau device (décision bloquante possible).
3. **Fraîcheur 0.6.4** (publié aujourd'hui) : accepter ou retenir 0.6.3
   (noyau `e2f017b`) — les deux épingles sont documentées ; le mandat doit
   nommer la release retenue et le commit moteur associé.
4. **tzdata Android** : injectée automatiquement côté iOS ; gestion équivalente
   Android à confirmer dans `files/`/`ValhallaConfigManager` au tag 0.6.4.
5. **Contenu des PBF** : couverture/tags à inspecter (`osmium fileinfo`,
   `tags-count`) — choix du PBF confirmé à cette étape.
6. **devicectl copy** : fonctionnement réel sur l'app en signature debug à
   vérifier au branchement ; sinon `UIFileSharingEnabled`.
7. Docs `phase_C` absents : décisions dépendant de la spec assumées
   (signalement fait, aucune recréation).

## 10. Restitution

- **Fichiers modifiés** : ce rapport uniquement
  (`docs/RAPPORT_ETUDE_MOTEUR_ROUTAGE_2026-10-06.md`).
- **Hors étude, autorisé explicitement** : reconstruction de
  `lib/routes/app_routes.dart` + `lib/routes/app_pages.dart` après suppression
  accidentelle (littéraux de routes choisis : `/map`, `/selected_markers`,
  `/route_library` — originaux introuvables, pas de dépôt Git).
- **Commandes exécutées** : lectures projet (`ls`, `find`, `cat`, `grep`,
  `sed`, `head`, `stat`, `pwd`) ; `flutter analyze --no-pub` → **aucune issue**
  (imports confirmés sur disque) ; fetches web sur sources publiques
  (rallista/valhalla-mobile releases/Package.swift/Valhalla.swift/
  ValhallaKotlin.kt/Valhalla.kt/build.gradle.kts/.gitmodules/src-tree,
  central.sonatype.com, valhalla/valhalla commit bafb699 + tag 3.9.1
  motorcyclecost.cc/dynamiccost.cc, flutter/flutter commit 6655482
  FlutterExtension.kt, maplibre docs). Aucune donnée du projet transmise à un
  service externe.
- **Vérifié vs hypothèse** : versions, commits moteur, minSdk/iOS floor, API
  raw-JSON et options 3.9.1 = **vérifiés dans les sources** ; noms des options
  CMake du tag, gestion tzdata Android, fonctionnement devicectl sur cette
  signature, contenu des PBF, taille du graphe = **hypothèses/contrôles à
  exécuter**, pas des faits.
- **Pas de conclusion « prêt à implémenter »** : il manque encore le choix
  0.6.4 vs 0.6.3, les infos appareils, et les autorisations §8.
- **Autorisations ciblées nécessaires** : écritures hors projet (clone/build
  valhalla), brew, modifications des fichiers protégés listés, commandes
  projet/devices du §8.

L'implémentation n'a pas commencé.
