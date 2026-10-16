import 'dart:async';
import 'dart:math' as math;

import 'package:get/get.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:casa_loop_engine/controllers/route_editor_controller.dart';
import 'package:casa_loop_engine/helpers/constants/color_hex.dart';
import 'package:casa_loop_engine/models/computed_route.dart';
import 'package:casa_loop_engine/models/local_map_pack.dart';
import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/services/map/offline_map_service.dart';
import 'package:casa_loop_engine/services/repositories/place_repository.dart';
import 'package:casa_loop_engine/helpers/geo/map_camera.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Position écran (pixels, origine en haut à gauche de la carte) du badge
/// numéroté d'un repère validé. Recalculée à chaque déplacement de caméra
/// ou resynchronisation des cercles ; [number] correspond à la position
/// courante dans la liste validée (index + 1).
class MapMarkerNumberLabel {
  const MapMarkerNumberLabel({required this.number, required this.dx, required this.dy});

  final int number;
  final double dx;
  final double dy;
}

/// État et orchestration de l'écran carte : installation du pack offline,
/// caméra, contrainte d'emprise et rendu des repères (cercles temporaire et
/// validés, glisser-déposer).
///
/// L'état de travail partagé (repères validés, préférences de segments,
/// objectifs et brouillon) est détenu par [RouteEditorController] : ce
/// controller observe ses révisions pour dessiner les cercles et y délègue
/// les mutations. Le controller détient le `MapLibreMapController` mais ne
/// construit aucun widget : la View se contente d'observer les états
/// exposés ici.
class MapController extends GetxController {
  MapController(this._mapService, this._editor);

  static MapController get instance => Get.find<MapController>();

  final OfflineMapService _mapService;
  final RouteEditorController _editor;

  /// Workers abonnés aux révisions de l'éditeur : un seul abonnement par
  /// signal, libéré dans [onClose]. La resynchronisation est ainsi pilotée
  /// par l'observation de l'état partagé, sans que l'éditeur référence ce
  /// controller.
  late final Worker _markersRevisionWorker;
  late final Worker _circlesRevisionWorker;
  late final Worker _restoreCirclesRevisionWorker;
  late final Worker _routeResultWorker;
  late final Worker _routeColorWorker;

  final Rxn<LocalMapPack> mapPack = Rxn<LocalMapPack>();
  final RxnString error = RxnString();
  final RxBool styleLoaded = false.obs;

  /// Repère temporaire affiché sur la carte en attente de validation : il
  /// ne fait pas encore partie de l'état de travail de
  /// [RouteEditorController].
  final Rxn<MapMarkerItem> pendingMarker = Rxn<MapMarkerItem>();

  /// Position écran courante du badge numéroté de chaque repère validé,
  /// dans l'ordre d'affichage. Rendue par la vue dans une surcouche Flutter
  /// (texte natif, lisible hors ligne) plutôt qu'en calque MapLibre, pour
  /// ne jamais dépendre de glyphes de police chargés depuis un serveur.
  final RxList<MapMarkerNumberLabel> markerNumberLabels = <MapMarkerNumberLabel>[].obs;

  MapLibreMapController? _map;
  Timer? _styleTimeout;
  double _currentZoom = MapCamera.initialZoom;
  bool _isEnforcingBounds = false;

  Circle? _pendingCircle;
  bool _isUpdatingPendingMarker = false;
  final Map<String, Circle> _validatedCircles = {};

  /// Lignes natives du dernier tracé calculé : une par segment, chacune
  /// dans la couleur choisie pour son couple dirigé ; vide si aucun n'est
  /// dessiné.
  final List<Line> _routeLines = [];

  /// Itinéraire effectivement représenté par [_routeLines] à l'instant
  /// présent ; `null` tant qu'aucun dessin complet n'a abouti pour
  /// l'itinéraire courant. Référence (identité, pas valeur) servant à
  /// détecter qu'un dessin ou une recoloration sont devenus périmés
  /// (résultat remplacé, carte fermée, style déchargé) en cours
  /// d'exécution, pour abandonner sans jamais toucher aux lignes d'un
  /// nouveau résultat.
  ComputedItinerary? _drawnItinerary;

  /// File sérialisant tout accès aux lignes de tracé : un dessin complet
  /// ([syncRouteLine]) et une recoloration ([_updateRouteLineColor]) ne
  /// s'exécutent jamais en parallèle. Chaque opération relit l'état
  /// courant au moment où elle s'exécute réellement — jamais celui
  /// capturé au moment de la demande — et revérifie la validité (résultat,
  /// carte, style) après chaque attente native.
  Future<void> _lineQueue = Future<void>.value();

  /// Génération du style chargé, incrémentée à chaque [onStyleLoaded] :
  /// [styleLoaded] reste `true` à travers un rechargement, elle ne permet
  /// donc pas à une opération en vol de détecter que le style — et les
  /// annotations qu'il portait — ont été remplacés pendant une attente
  /// native. Chaque opération sur les lignes capture la génération à son
  /// démarrage et la revérifie après chaque attente ; un écart signifie
  /// que les lignes natives déjà posées ne valent plus rien (détruites
  /// par le rechargement) et que l'opération doit s'abandonner.
  int _lineStyleGeneration = 0;

  /// `true` pendant un recalcul des positions écran de
  /// [markerNumberLabels] : une nouvelle demande reçue pendant ce calcul
  /// n'est jamais abandonnée, mais rejouée une fois le calcul en cours
  /// terminé (voir [_labelsDirty]).
  bool _labelsSyncing = false;
  bool _labelsDirty = false;

  /// Associe l'identifiant natif d'un `Circle` (`circle.id`) à l'identifiant
  /// du [MapMarkerItem] qu'il représente, pour retrouver le bon repère
  /// lorsqu'un événement de glisser-déposer est reçu.
  final Map<String, String> _circleIdToMarkerId = {};
  OnFeatureDragCallback? _onFeatureDrag;
  bool _markersRestored = false;

  @override
  void onInit() {
    super.onInit();
    Diag.event('MapController.onInit');
    _markersRevisionWorker = ever(_editor.markersRevision, (_) {
      if (isClosed) return;
      unawaited(
        restoreMarkersDisplay().catchError((Object error) {
          Diag.error('MapController.markersRevision.sync', error);
          _editor.workingStateError.value = 'Affichage des repères impossible : $error';
        }),
      );
    });
    _circlesRevisionWorker = ever(_editor.circlesRevision, (_) {
      if (isClosed) return;
      unawaited(
        syncCirclesWithMarkers().catchError((Object error) {
          Diag.error('MapController.circlesRevision.sync', error);
          _editor.workingStateError.value = 'Affichage des repères impossible : $error';
        }),
      );
    });
    _restoreCirclesRevisionWorker = ever(_editor.restoreCirclesRevision, (_) {
      if (isClosed) return;
      unawaited(
        resyncAfterRollback(pendingMarker.value).catchError((Object error) {
          Diag.error('MapController.restoreCirclesRevision.sync', error);
          _editor.workingStateError.value = 'Affichage des repères impossible : $error';
        }),
      );
    });
    _routeResultWorker = ever(_editor.routeResultRevision, (_) {
      if (isClosed) return;
      unawaited(
        syncRouteLine().catchError((Object error) {
          Diag.error('MapController.routeResult.sync', error);
          _editor.workingStateError.value = 'Affichage du tracé impossible : $error';
        }),
      );
    });
    // Changement de couleur seul : recolore la ligne déjà affichée sans
    // rappeler le moteur ni recadrer la caméra, à la différence de
    // [_routeResultWorker] (nouveau calcul ou invalidation).
    _routeColorWorker = ever(_editor.routeColorRevision, (_) {
      if (isClosed) return;
      unawaited(
        _updateRouteLineColor().catchError((Object error) {
          Diag.error('MapController.routeColorRevision.sync', error);
        }),
      );
    });
    unawaited(loadMapPack());
  }

  /// Les cercles nécessitent une carte native et un style chargé.
  bool get _circleSyncReady => styleLoaded.value && _map != null;

  Future<Circle> _addCircle(CircleOptions options) => _map!.addCircle(options);

  Future<void> _removeCircle(Circle circle) => _map!.removeCircle(circle);

  /// Resynchronise les cercles affichés sur la carte avec les repères
  /// validés de [RouteEditorController] : retire les anciens cercles et la
  /// sélection temporaire éventuelle, puis redessine sans doublon. Si la
  /// carte n'est pas encore prête, reporte la restauration au prochain
  /// chargement de style via [restoreMarkersDisplay].
  /// Lève une erreur sans rien modifier si une autre synchronisation est déjà
  /// en cours (empêche le chevauchement entre chargement manuel et
  /// restauration automatique déclenchée par [onStyleLoaded]) ; si un
  /// retrait ou un ajout échoue en cours de route, les cercles déjà créés ou
  /// déjà retirés restent fidèlement suivis dans [_validatedCircles], pour ne
  /// jamais « oublier » un cercle natif existant.
  Future<void> syncCirclesWithMarkers() => Diag.future('MapController.syncCirclesWithMarkers', () async {
    if (_editor.isCirclesSyncing.value) {
      throw StateError('Une synchronisation des cercles est déjà en cours.');
    }
    if (!_circleSyncReady) {
      await clearPendingMarker();
      _validatedCircles.clear();
      _circleIdToMarkerId.clear();
      _markersRestored = false;
      markerNumberLabels.clear();
      return;
    }
    _editor.isCirclesSyncing.value = true;
    try {
      await clearPendingMarker();
      final toRemove = Map<String, Circle>.of(_validatedCircles);
      for (final entry in toRemove.entries) {
        await _removeCircle(entry.value);
        _validatedCircles.remove(entry.key);
        _circleIdToMarkerId.removeWhere((circleId, markerId) => markerId == entry.key);
      }
      for (final marker in _editor.validatedMarkers) {
        final circle = await _addCircle(_validatedCircleOptions(marker));
        _validatedCircles[marker.id] = circle;
        _circleIdToMarkerId[circle.id] = marker.id;
      }
      _markersRestored = true;
      unawaited(_updateMarkerLabels());
    } finally {
      _editor.isCirclesSyncing.value = false;
    }
  }, result: (_) => 'circles=${_validatedCircles.length}');

  /// Recalcule la position écran du badge numéroté de chaque repère
  /// validé, dans l'ordre actuel (numéro = position + 1). Si un recalcul
  /// est déjà en cours (par exemple déclenché par un déplacement de
  /// caméra), la demande n'est jamais abandonnée : elle est rejouée une
  /// fois le recalcul en cours terminé.
  Future<void> _updateMarkerLabels() => Diag.frequentFuture('MapController._updateMarkerLabels', () async {
    if (_labelsSyncing) {
      _labelsDirty = true;
      return;
    }
    _labelsSyncing = true;
    try {
      do {
        _labelsDirty = false;
        final controller = _map;
        if (controller == null || !styleLoaded.value) {
          markerNumberLabels.clear();
          break;
        }
        final markers = List<MapMarkerItem>.of(_editor.validatedMarkers);
        if (markers.isEmpty) {
          markerNumberLabels.clear();
          continue;
        }
        final points = await controller.toScreenLocationBatch([
          for (final marker in markers) LatLng(marker.latitude, marker.longitude),
        ]);
        if (isClosed) return;
        markerNumberLabels.assignAll([
          for (var i = 0; i < markers.length && i < points.length; i++)
            MapMarkerNumberLabel(number: i + 1, dx: points[i].x.toDouble(), dy: points[i].y.toDouble()),
        ]);
      } while (_labelsDirty);
    } finally {
      _labelsSyncing = false;
    }
  }, result: (_) => 'labels=${markerNumberLabels.length}');

  /// Restauration automatique des cercles au démarrage ou au chargement de
  /// style : délègue à [syncCirclesWithMarkers] pour ne jamais dupliquer la
  /// logique de redessin. Se retire silencieusement si une synchronisation
  /// (notamment un chargement manuel) est déjà en cours, pour empêcher tout
  /// chevauchement des deux redessins.
  Future<void> restoreMarkersDisplay() async {
    final op = Diag.start(
      'MapController.restoreMarkersDisplay',
      'markers=${_editor.validatedMarkers.length}',
    );
    if (_markersRestored || _editor.isCirclesSyncing.value || !_circleSyncReady) {
      op.early(
        'restored=$_markersRestored syncing=${_editor.isCirclesSyncing.value} ready=$_circleSyncReady',
      );
      return;
    }
    try {
      await syncCirclesWithMarkers();
      // Au démarrage, on centre la caméra sur le dernier repère persisté.
      await _centerOnLastMarker();
      op.end('circles=${_validatedCircles.length}');
    } catch (exception, stack) {
      op.fail(exception, stack);
      rethrow;
    }
  }

  /// Redessine les cercles après la restauration de l'état de travail
  /// précédent par [RouteEditorController] (retour arrière d'un chargement
  /// manuel) : marque la restauration comme à refaire, resynchronise les
  /// cercles validés puis redessine la sélection temporaire conservée
  /// éventuelle. En cas d'échec, [pendingMarker] est restauré pour que le
  /// choix de l'utilisateur ne soit pas perdu ; l'erreur est relancée pour
  /// être tracée par l'appelant.
  Future<void> resyncAfterRollback(MapMarkerItem? previousPending) async {
    _markersRestored = false;
    try {
      await syncCirclesWithMarkers();
      if (previousPending != null) await _drawPendingMarker(previousPending, recenter: false);
    } catch (exception) {
      pendingMarker.value = previousPending;
      _markersRestored = false;
      rethrow;
    }
  }

  CircleOptions _validatedCircleOptions(MapMarkerItem marker) => Diag.frequentSync(
    'MapController._validatedCircleOptions',
    () => CircleOptions(
      geometry: LatLng(marker.latitude, marker.longitude),
      circleRadius: 8,
      circleColor: ColorHex.validatedMarker,
      circleStrokeColor: ColorHex.markerStroke,
      circleStrokeWidth: 2,
      circleOpacity: 1,
      draggable: true,
    ),
    params: 'markerId=${marker.id}',
  );

  /// Installe le pack cartographique offline puis arme la surveillance du
  /// chargement de style. Alimente [error] en cas d'échec d'installation.
  Future<void> loadMapPack() async {
    final op = Diag.start('MapController.loadMapPack', 'source=${_mapService.sourcePath}');
    try {
      final pack = await _mapService.ensureInstalled();
      if (isClosed) {
        op.early('closed');
        return;
      }
      mapPack.value = pack;
      _startStyleTimeout(pack);
      op.end('mbtiles=${pack.mbtilesPath}');
    } catch (installError, stack) {
      error.value = 'Installation MBTiles impossible\n$installError';
      op.fail(installError, stack);
    }
  }

  void _startStyleTimeout(LocalMapPack pack) {
    Diag.event('MapController._startStyleTimeout', 'timeoutSec=60');
    _styleTimeout = Timer(const Duration(seconds: 60), () {
      if (isClosed) return;
      Diag.error(
        'MapController._styleTimeout.fired',
        'MapLibre n’a pas chargé le style MBTiles local en 60 secondes. '
            'Source: mbtiles://${pack.mbtilesPath}',
      );
      error.value =
          'MapLibre n’a pas chargé le style MBTiles local en 60 secondes.\n'
          'Source: mbtiles://${pack.mbtilesPath}';
    });
  }

  void onMapCreated(MapLibreMapController controller) {
    Diag.event('MapController.onMapCreated');
    _map = controller;
    _onFeatureDrag = _handleFeatureDrag;
    controller.onFeatureDrag.add(_onFeatureDrag!);
  }

  void onStyleLoaded() {
    Diag.event('MapController.onStyleLoaded');
    _styleTimeout?.cancel();
    styleLoaded.value = true;
    // Délai entre le style chargé et la première frame effectivement rendue.
    Diag.untilFirstFrame('MapController.styleLoaded.firstFrame');
    if (!_editor.isInitializing.value) {
      unawaited(
        restoreMarkersDisplay().catchError((Object error) {
          _editor.workingStateError.value = "Affichage des repères impossible : $error";
        }),
      );
    }
    // Les annotations natives sont perdues à chaque (re)chargement de style :
    // les références des lignes sont invalidées avant redessin et la
    // génération avance pour avorter toute opération en vol.
    _lineStyleGeneration++;
    _routeLines.clear();
    _drawnItinerary = null;
    if (_editor.tracedItinerary.value != null) {
      unawaited(
        syncRouteLine().catchError((Object error) {
          _editor.workingStateError.value = "Affichage du tracé impossible : $error";
        }),
      );
    }
  }

  void onCameraMove(CameraPosition camera) {
    // Le clamp interne sert au calcul des boutons. Le clamp visuel est
    // appliqué dans enforceBounds() à l'arrêt du geste, sinon les gestes
    // peuvent brièvement afficher un zoom hors plage.
    Diag.frequent('MapController.onCameraMove', 'zoom=${camera.zoom.toStringAsFixed(2)}');
    _currentZoom = camera.zoom.clamp(MapCamera.minZoom, MapCamera.maxZoom).toDouble();
    unawaited(_updateMarkerLabels());
  }

  Future<void> zoomBy(double delta) async {
    final op = Diag.start('MapController.zoomBy', 'delta=$delta zoom=$_currentZoom');
    try {
      final controller = _map;
      if (controller == null) {
        op.early('noController');
        return;
      }
      final targetZoom = MapCamera.clampZoom(_currentZoom, delta);
      if (targetZoom == _currentZoom) {
        op.early('alreadyAtBound');
        return;
      }
      _currentZoom = targetZoom;
      await controller.animateCamera(
        delta > 0 ? CameraUpdate.zoomIn() : CameraUpdate.zoomOut(),
        duration: const Duration(milliseconds: 250),
      );
      op.end('targetZoom=$targetZoom');
    } catch (exception, stack) {
      op.fail(exception, stack);
      rethrow;
    }
  }

  /// Ramène la caméra dans l'emprise du MBTiles lorsqu'elle en sort, ou la
  /// recentre lorsque la zone visible est plus large que l'emprise.
  Future<void> enforceBounds() async {
    var outcome = 'noop';
    await Diag.frequentFuture('MapController.enforceBounds', () async {
      if (_isEnforcingBounds) {
        outcome = 'busy';
        return;
      }
      final controller = _map;
      if (controller == null) {
        outcome = 'noController';
        return;
      }

      _isEnforcingBounds = true;
      try {
        final visible = await controller.getVisibleRegion();
        final camera = controller.cameraPosition;
        final currentCenter =
            camera?.target ??
            LatLng(
              (visible.southwest.latitude + visible.northeast.latitude) / 2,
              (visible.southwest.longitude + visible.northeast.longitude) / 2,
            );
        final visibleLatSpan = visible.northeast.latitude - visible.southwest.latitude;
        final visibleLonSpan = visible.northeast.longitude - visible.southwest.longitude;
        final boundsLatSpan = MapCamera.north - MapCamera.south;
        final boundsLonSpan = MapCamera.east - MapCamera.west;

        var deltaLat = 0.0;
        var deltaLon = 0.0;
        if (visibleLatSpan >= boundsLatSpan) {
          deltaLat = (MapCamera.south + MapCamera.north) / 2 - currentCenter.latitude;
        } else {
          if (visible.southwest.latitude < MapCamera.south) {
            deltaLat += MapCamera.south - visible.southwest.latitude;
          }
          if (visible.northeast.latitude > MapCamera.north) {
            deltaLat -= visible.northeast.latitude - MapCamera.north;
          }
        }
        if (visibleLonSpan >= boundsLonSpan) {
          deltaLon = (MapCamera.west + MapCamera.east) / 2 - currentCenter.longitude;
        } else {
          if (visible.southwest.longitude < MapCamera.west) {
            deltaLon += MapCamera.west - visible.southwest.longitude;
          }
          if (visible.northeast.longitude > MapCamera.east) {
            deltaLon -= visible.northeast.longitude - MapCamera.east;
          }
        }

        final clampedZoom = (camera?.zoom ?? _currentZoom)
            .clamp(MapCamera.minZoom, MapCamera.maxZoom)
            .toDouble();
        final hasZoomDelta = (camera?.zoom ?? _currentZoom) != clampedZoom;

        if (deltaLat.abs() < 1e-6 && deltaLon.abs() < 1e-6 && !hasZoomDelta) {
          return;
        }
        await controller.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(currentCenter.latitude + deltaLat, currentCenter.longitude + deltaLon),
              zoom: clampedZoom,
              bearing: camera?.bearing ?? 0,
              tilt: camera?.tilt ?? 0,
            ),
          ),
        );
        outcome =
            'moved dLat=${deltaLat.toStringAsFixed(4)} '
            'dLon=${deltaLon.toStringAsFixed(4)} zoom=$clampedZoom';
      } catch (exception, stack) {
        // Ignoré : erreur ponctuelle de plateforme lors de la lecture ou du
        // déplacement de la caméra, sans impact fonctionnel — tracée
        // néanmoins pour le diagnostic.
        outcome = 'ignored';
        Diag.error('MapController.enforceBounds.caught', exception, stack);
      } finally {
        _isEnforcingBounds = false;
      }
    }, result: (_) => outcome);
  }

  /// Dessine ou retire les géométries du dernier tracé calculé par
  /// [RouteEditorController], puis cadre la caméra dessus une seule fois —
  /// uniquement si le dessin a abouti sans devenir périmé en cours de
  /// route. Sans effet visible quand la carte ou le style ne sont pas
  /// prêts : le redessin est alors reporté au prochain `onStyleLoaded`.
  /// Sérialisée avec [_updateRouteLineColor] via [_enqueueLineOperation] :
  /// chaque opération relit l'état courant au moment où elle s'exécute
  /// réellement, jamais celui capturé au moment de la demande — plusieurs
  /// demandes empilées convergent donc naturellement vers le dernier état.
  ///
  /// Dessine une ligne native par segment, dans la couleur choisie pour son
  /// couple dirigé, sans contour ni raccord droit entre les géométries.
  Future<void> syncRouteLine() => Diag.future(
    'MapController.syncRouteLine',
    () => _enqueueLineOperation(() async {
      final controller = _map;
      if (controller == null || !styleLoaded.value) {
        _routeLines.clear();
        _drawnItinerary = null;
        return;
      }
      final itinerary = _editor.tracedItinerary.value;
      if (identical(_drawnItinerary, itinerary) && _routeLines.length == (itinerary?.segments.length ?? 0)) {
        // Déjà à jour : demande redondante (plusieurs révisions empilées
        // pour le même résultat).
        return;
      }
      final drawn = await _drawLines(controller, itinerary);
      // Le cadrage reste une étape distincte du dessin, déclenchée
      // seulement par un dessin complet et réussi — jamais par une
      // recoloration ([_updateRouteLineColor] ne l'appelle jamais).
      if (drawn && itinerary != null) {
        await _frameItinerary(controller, itinerary);
      }
    }),
    result: (_) => 'lines=${_routeLines.length}',
  );

  /// Dessine [itinerary] (ou retire les lignes existantes si `null`), sans
  /// jamais cadrer la caméra. Retourne `true` si le dessin complet a pu
  /// être posé sans que le résultat, la carte ou le style ne changent en
  /// cours de route ; `false` sinon — les lignes déjà posées pour cette
  /// tentative sont alors retirées, mais aucune ligne du nouveau résultat
  /// n'est touchée (l'opération suivante en file, déjà en attente, s'en
  /// charge avec l'état à jour).
  Future<bool> _drawLines(MapLibreMapController controller, ComputedItinerary? itinerary) async {
    final styleGeneration = _lineStyleGeneration;
    await _removeRouteLines(controller);
    _drawnItinerary = null;
    if (itinerary == null) return true;
    for (final segment in itinerary.segments) {
      if (_isLineRenderStale(controller, itinerary, styleGeneration)) {
        await _removeRouteLines(controller);
        return false;
      }
      final geometry = [for (final p in segment.route.geometry) LatLng(p.latitude, p.longitude)];
      _routeLines.add(
        await controller.addLine(
          LineOptions(
            geometry: geometry,
            lineColor: _editor.colorForPair(segment.identity.startMarkerId, segment.identity.endMarkerId),
            lineWidth: 4,
            lineOpacity: 1,
            lineJoin: 'round',
          ),
        ),
      );
    }
    if (_isLineRenderStale(controller, itinerary, styleGeneration)) {
      await _removeRouteLines(controller);
      return false;
    }
    _drawnItinerary = itinerary;
    return true;
  }

  /// `true` si une opération en cours sur les lignes de tracé, démarrée
  /// pour [controller], [itinerary] et la génération de style
  /// [styleGeneration] capturée à son démarrage, n'est plus valide :
  /// contrôleur fermé, carte remplacée (nouveau contrôleur natif), style
  /// déchargé ou rechargé (la génération a avancé, les annotations
  /// natives déjà posées sont perdues), ou résultat de l'éditeur changé
  /// depuis le début de l'opération (comparaison par identité, pas par
  /// valeur). Vérifiée après chaque attente native.
  bool _isLineRenderStale(
    MapLibreMapController controller,
    ComputedItinerary itinerary,
    int styleGeneration,
  ) =>
      isClosed ||
      !identical(_map, controller) ||
      !styleLoaded.value ||
      styleGeneration != _lineStyleGeneration ||
      !identical(_editor.tracedItinerary.value, itinerary);

  /// Retire toutes les lignes de tracé affichées ; une ligne dont la
  /// suppression échoue (annotation déjà perdue par un rechargement de
  /// style) est simplement oubliée de la liste.
  Future<void> _removeRouteLines(MapLibreMapController controller) async {
    final lines = List<Line>.of(_routeLines);
    _routeLines.clear();
    for (final line in lines) {
      try {
        await controller.removeLine(line);
      } catch (removeError) {
        Diag.error('MapController.removeRouteLine', removeError);
      }
    }
  }

  /// Recolore les lignes déjà dessinées pour l'itinéraire courant, sans
  /// toucher aux géométries et **sans jamais cadrer la caméra** : réaction
  /// à [RouteEditorController.routeColorRevision] uniquement (changement
  /// de couleur de l'utilisateur), jamais à un nouveau calcul. Sérialisée
  /// avec [syncRouteLine] via [_enqueueLineOperation].
  ///
  /// Si l'itinéraire dessiné ([_drawnItinerary]) ne correspond pas (encore)
  /// à celui en cours — dessin pas encore terminé ou déjà remplacé —,
  /// l'opération est silencieusement abandonnée sans toucher à aucune
  /// ligne : le prochain dessin complet appliquera de toute façon les
  /// couleurs à jour via [RouteEditorController.colorForPair]. La validité
  /// est revérifiée après chaque attente native pour abandonner sans
  /// toucher aux lignes d'un nouveau résultat si celui-ci est remplacé en
  /// cours de boucle.
  Future<void> _updateRouteLineColor() => Diag.future(
    'MapController._updateRouteLineColor',
    () => _enqueueLineOperation(() async {
      final controller = _map;
      final itinerary = _editor.tracedItinerary.value;
      if (controller == null || itinerary == null || !styleLoaded.value) return;
      if (!identical(_drawnItinerary, itinerary) || _routeLines.length != itinerary.segments.length) {
        return;
      }
      final styleGeneration = _lineStyleGeneration;
      final lines = List<Line>.of(_routeLines);
      for (var i = 0; i < lines.length; i++) {
        if (_isLineRenderStale(controller, itinerary, styleGeneration)) return;
        final identity = itinerary.segments[i].identity;
        await controller.updateLine(
          lines[i],
          LineOptions(lineColor: _editor.colorForPair(identity.startMarkerId, identity.endMarkerId)),
        );
      }
    }),
    result: (_) => 'lines=${_routeLines.length}',
  );

  /// Sérialise tout accès aux lignes de tracé : [syncRouteLine] et
  /// [_updateRouteLineColor] s'enchaînent dans l'ordre de leur appel, sans
  /// jamais s'exécuter en parallèle. Une opération en échec ne bloque pas
  /// les suivantes : l'erreur reste portée par le [Future] retourné à
  /// l'appelant, mais la file continue.
  Future<void> _enqueueLineOperation(Future<void> Function() operation) {
    final result = _lineQueue.then((_) => operation());
    _lineQueue = result.catchError((Object error, StackTrace stack) {
      Diag.error('MapController.lineOperation', error, stack);
    });
    return result;
  }

  /// Cadre la caméra sur l'emprise de toutes les géométries calculées.
  /// Jamais appelée par [_updateRouteLineColor] : une recoloration seule ne
  /// recadre jamais la caméra.
  Future<void> _frameItinerary(MapLibreMapController controller, ComputedItinerary itinerary) async {
    if (itinerary.segments.isEmpty) return;
    var minLat = itinerary.segments.first.route.geometry.first.latitude;
    var maxLat = minLat;
    var minLon = itinerary.segments.first.route.geometry.first.longitude;
    var maxLon = minLon;
    for (final segment in itinerary.segments) {
      for (final point in segment.route.geometry) {
        minLat = math.min(minLat, point.latitude);
        maxLat = math.max(maxLat, point.latitude);
        minLon = math.min(minLon, point.longitude);
        maxLon = math.max(maxLon, point.longitude);
      }
    }
    // Marge verticale plus grande en bas : le résumé du tracé y est affiché.
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(minLat, minLon), northeast: LatLng(maxLat, maxLon)),
        left: 56,
        top: 120,
        right: 56,
        bottom: 220,
      ),
      duration: const Duration(milliseconds: 450),
    );
  }

  Future<void> _centerOnLastMarker() => Diag.future('MapController._centerOnLastMarker', () async {
    if (_editor.validatedMarkers.isEmpty) {
      Diag.event('MapController._centerOnLastMarker.early', 'noMarkers');
      return;
    }
    await centerOn(_editor.validatedMarkers.last);
  });

  Future<void> centerOn(MapMarkerItem marker) => Diag.future('MapController.centerOn', () async {
    final controller = _map;
    if (controller == null) {
      Diag.event('MapController.centerOn.early', 'noController');
      return;
    }
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(marker.latitude, marker.longitude), _currentZoom),
      duration: const Duration(milliseconds: 350),
    );
  }, params: 'markerId=${marker.id}');

  Future<void> clearPendingMarker() => Diag.future('MapController.clearPendingMarker', () async {
    final circle = _pendingCircle;
    if (circle != null) {
      await _removeCircle(circle);
    }
    _pendingCircle = null;
    pendingMarker.value = null;
    _pendingNameAuto = false;
  }, result: (_) => 'removedCircle=${_map != null}');

  /// `true` tant que le nom du repère temporaire vient d'une suggestion
  /// (ou du générique) et n'a pas été saisi : un glisser-déposer peut
  /// alors mettre à jour la suggestion ; un nom tapé reste intact.
  bool _pendingNameAuto = false;

  /// Nom du lieu répertorié le plus proche (ville, village, lieu-dit) —
  /// `null` si le référentiel est absent ou sans lieu dans le rayon :
  /// le repli reste [MapMarkerItem.defaultPersonalizedName].
  Future<String?> _suggestPlaceName(double latitude, double longitude) async {
    if (!Get.isRegistered<PlaceRepository>()) return null;
    try {
      final nearest = await Get.find<PlaceRepository>().nearest(latitude: latitude, longitude: longitude);
      return nearest?.name;
    } catch (error) {
      Diag.event('MapController.suggestPlaceName.fail', '$error');
      return null;
    }
  }

  /// Après un glisser-déposer du repère temporaire dont le nom est encore
  /// automatique : propose le lieu le plus proche de la nouvelle position
  /// (ou retombe sur le générique s'il n'y en a plus dans le rayon).
  Future<void> _applyPendingSuggestion() => Diag.future('MapController.applyPendingSuggestion', () async {
    final marker = pendingMarker.value;
    if (marker == null) return;
    final suggestion = await _suggestPlaceName(marker.latitude, marker.longitude);
    final current = pendingMarker.value;
    if (current == null || current.id != marker.id || !_pendingNameAuto) return;
    final name = suggestion ?? MapMarkerItem.defaultPersonalizedName;
    if (name != current.name) {
      pendingMarker.value = current.copyWith(name: name);
    }
  });

  Future<void> showPendingMarkerAt(LatLng latLng) => Diag.future(
    'MapController.showPendingMarkerAt',
    () async {
      final suggestion = await _suggestPlaceName(latLng.latitude, latLng.longitude);
      final marker = MapMarkerItem(
        id: 'pending_${DateTime.now().millisecondsSinceEpoch}',
        name: suggestion ?? MapMarkerItem.defaultPersonalizedName,
        type: 'personnalisé',
        latitude: latLng.latitude,
        longitude: latLng.longitude,
        orderIndex: _editor.validatedMarkers.length,
      );
      await showPendingMarker(marker, recenter: false);
      // Le nom proposé est automatique : il suivra un éventuel glisser.
      _pendingNameAuto = true;
    },
    params:
        'lat=${latLng.latitude.toStringAsFixed(5)} '
        'lon=${latLng.longitude.toStringAsFixed(5)}',
  );

  Future<void> showPendingMarker(MapMarkerItem marker, {bool recenter = true}) async {
    // Toute autre source (ex. résultat de recherche) arrive déjà nommée :
    // le nom n'est pas automatique, un glisser ne le remplacera pas.
    _pendingNameAuto = false;
    if (_editor.mutationsBlocked) {
      Diag.event('MapController.showPendingMarker', 'loadingDraft');
      return;
    }
    _editor.isMutatingMarkers.value = true;
    try {
      await _drawPendingMarker(marker, recenter: recenter);
    } finally {
      _editor.isMutatingMarkers.value = false;
    }
  }

  Future<void> _drawPendingMarker(MapMarkerItem marker, {bool recenter = true}) async {
    final op = Diag.start('MapController.showPendingMarker', 'markerId=${marker.id} name="${marker.name}"');
    if (_isUpdatingPendingMarker) {
      op.early('selectionBusy');
      return;
    }
    _isUpdatingPendingMarker = true;
    try {
      final controller = _map;
      if (controller == null) {
        op.early('noController');
        return;
      }
      await clearPendingMarker();
      if (recenter) {
        await centerOn(marker);
      }
      final circle = await controller.addCircle(
        CircleOptions(
          geometry: LatLng(marker.latitude, marker.longitude),
          circleRadius: 9,
          circleColor: ColorHex.pendingMarker,
          circleStrokeColor: ColorHex.markerStroke,
          circleStrokeWidth: 2,
          circleOpacity: 0.9,
          draggable: true,
        ),
      );
      if (isClosed) {
        await controller.removeCircle(circle);
        op.early('closed');
        return;
      }
      pendingMarker.value = marker;
      _pendingCircle = circle;
      op.end('circleId=${circle.id}');
    } catch (exception, stack) {
      op.fail(exception, stack);
      rethrow;
    } finally {
      _isUpdatingPendingMarker = false;
    }
  }

  /// Met à jour le nom du repère temporaire depuis la fiche de saisie ;
  /// un nom vide retombe sur [MapMarkerItem.defaultPersonalizedName].
  void setPendingMarkerName(String name) => Diag.frequentSync('MapController.setPendingMarkerName', () {
    final marker = pendingMarker.value;
    if (marker == null) return;
    final trimmed = name.trim();
    // Un nom saisi n'est plus automatique : il ne sera pas remplacé par
    // une suggestion au prochain glisser-déposer.
    _pendingNameAuto = trimmed.isEmpty;
    pendingMarker.value = marker.copyWith(
      name: trimmed.isEmpty ? MapMarkerItem.defaultPersonalizedName : trimmed,
    );
  }, params: 'markerId=${pendingMarker.value?.id}');

  Future<void> validatePendingMarker() async {
    if (_editor.mutationsBlocked) {
      Diag.event('MapController.validatePendingMarker', 'loadingDraft');
      return;
    }
    final marker = pendingMarker.value;
    if (marker != null && _editor.validatedMarkers.any((m) => m.id == marker.id)) {
      throw StateError('Ce repère est déjà présent dans le trajet.');
    }
    final circle = _pendingCircle;
    final controller = _map;
    final op = Diag.start('MapController.validatePendingMarker', 'markerId=${marker?.id}');
    if (_isUpdatingPendingMarker) {
      op.early('selectionBusy');
      return;
    }
    _isUpdatingPendingMarker = true;
    try {
      if (marker == null || circle == null || controller == null) {
        op.early('missingState');
        return;
      }
      _editor.isMutatingMarkers.value = true;
      await controller.updateCircle(
        circle,
        const CircleOptions(circleColor: ColorHex.validatedMarker, circleRadius: 8, circleOpacity: 1),
      );
      _validatedCircles[marker.id] = circle;
      _circleIdToMarkerId[circle.id] = marker.id;
      _pendingCircle = null;
      pendingMarker.value = null;
      // L'identifiant temporaire `pending_` est conservé à la validation. Il
      // est unique à la milliseconde, donc sans risque de collision dans une
      // session utilisateur réelle.
      await _editor.addValidatedMarker(marker);
      // Recentre sur le dernier repère ajouté pour valider la création.
      await _centerOnLastMarker();
      unawaited(_updateMarkerLabels());
      op.end('markers=${_editor.validatedMarkers.length}');
    } catch (exception, stack) {
      op.fail(exception, stack);
      rethrow;
    } finally {
      _isUpdatingPendingMarker = false;
      _editor.isMutatingMarkers.value = false;
    }
  }

  /// Met à jour la position d'un repère (temporaire ou validé) lorsque
  /// l'utilisateur relâche le `Circle` correspondant après un
  /// glisser-déposer sur la carte.
  void _handleFeatureDrag(
    math.Point<double> point,
    LatLng origin,
    LatLng current,
    LatLng delta,
    String id,
    Annotation? annotation,
    DragEventType eventType,
  ) {
    Diag.frequent('MapController.onFeatureDrag', 'event=$eventType id=$id');
    if (eventType != DragEventType.end) return;

    // La sélection temporaire n'est pas persistée : son glisser-déposer
    // reste possible même pendant un chargement ou une mutation.
    if (_pendingCircle != null && id == _pendingCircle!.id) {
      pendingMarker.value = pendingMarker.value!.copyWith(
        latitude: current.latitude,
        longitude: current.longitude,
      );
      // Nom encore automatique (suggestion ou générique) : le repère a
      // bougé, la suggestion du lieu le plus proche est recalculée.
      if (_pendingNameAuto) unawaited(_applyPendingSuggestion());
      Diag.event(
        'MapController.pendingMarkerDragged',
        'lat=${current.latitude.toStringAsFixed(5)} '
            'lon=${current.longitude.toStringAsFixed(5)}',
      );
      return;
    }

    if (_editor.mutationsBlocked) {
      Diag.event('MapController.onFeatureDrag', 'mutationsBlocked');
      // Le cercle natif a déjà bougé : resynchronisation de l'affichage sans
      // recentrer la caméra, en préservant la sélection temporaire.
      _markersRestored = false;
      if (!_editor.isLoadingDraft.value) {
        final pending = pendingMarker.value;
        unawaited(() async {
          try {
            await syncCirclesWithMarkers();
            if (pending != null) await _drawPendingMarker(pending, recenter: false);
          } catch (error) {
            _editor.workingStateError.value = 'Carte à resynchroniser : $error';
          }
        }());
      }
      return;
    }

    final markerId = _circleIdToMarkerId[id];
    if (markerId == null) return;
    final index = _editor.validatedMarkers.indexWhere((item) => item.id == markerId);
    if (index == -1) return;
    final moved = _editor.validatedMarkers[index].copyWith(
      latitude: current.latitude,
      longitude: current.longitude,
    );
    _editor.validatedMarkers[index] = moved;
    Diag.event(
      'MapController.markerDragged',
      'markerId=$markerId index=$index '
          'lat=${current.latitude.toStringAsFixed(5)} '
          'lon=${current.longitude.toStringAsFixed(5)}',
    );
    unawaited(_updateMarkerLabels());
    _editor.scheduleWorkingSave();
  }

  @override
  void onClose() {
    Diag.event('MapController.onClose');
    _styleTimeout?.cancel();
    _markersRevisionWorker.dispose();
    _circlesRevisionWorker.dispose();
    _restoreCirclesRevisionWorker.dispose();
    _routeResultWorker.dispose();
    _routeColorWorker.dispose();
    final onFeatureDrag = _onFeatureDrag;
    if (onFeatureDrag != null) {
      _map?.onFeatureDrag.remove(onFeatureDrag);
    }
    super.onClose();
  }
}
