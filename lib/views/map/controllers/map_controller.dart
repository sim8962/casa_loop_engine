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
import 'package:casa_loop_engine/helpers/geo/map_camera.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Position écran (pixels, origine en haut à gauche de la carte) du badge
/// numéroté d'un repère validé. Recalculée à chaque déplacement de caméra
/// ou resynchronisation des cercles ; [number] correspond à la position
/// courante dans la liste validée (index + 1), jamais à l'identité du
/// repère ([markerId]), qui ne change jamais.
class MapMarkerNumberLabel {
  const MapMarkerNumberLabel({
    required this.markerId,
    required this.number,
    required this.dx,
    required this.dy,
  });

  final String markerId;
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

  /// Ligne native du dernier tracé calculé, dans la couleur choisie pour le
  /// segment ; `null` si aucun n'est dessiné.
  Line? _routeLine;
  bool _routeLineSyncing = false;

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
            MapMarkerNumberLabel(
              markerId: markers[i].id,
              number: i + 1,
              dx: points[i].x.toDouble(),
              dy: points[i].y.toDouble(),
            ),
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
    // la référence de la ligne est invalidée avant redessin.
    _routeLine = null;
    if (_editor.tracedSegment.value != null) {
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

  /// Dessine ou retire la géométrie du dernier tracé calculé par
  /// [RouteEditorController] et cadre la caméra dessus. Sans effet visible
  /// quand la carte ou le style ne sont pas prêts : le redessin est alors
  /// reporté au prochain `onStyleLoaded`. Sérialisée contre elle-même pour
  /// éviter les redessins imbriqués.
  ///
  /// Dessine une seule ligne native [_routeLine] dans la couleur choisie
  /// pour le segment tracé (position 0 → 1, seul segment calculé).
  Future<void> syncRouteLine() => Diag.future('MapController.syncRouteLine', () async {
    if (_routeLineSyncing) return;
    final controller = _map;
    if (controller == null || !styleLoaded.value) {
      _routeLine = null;
      return;
    }
    _routeLineSyncing = true;
    try {
      final existingLine = _routeLine;
      if (existingLine != null) {
        try {
          await controller.removeLine(existingLine);
        } catch (removeError) {
          Diag.error('MapController.removeRouteLine', removeError);
        }
        _routeLine = null;
      }
      final route = _editor.tracedSegment.value;
      if (route == null || isClosed) return;
      final geometry = [for (final p in route.geometry) LatLng(p.latitude, p.longitude)];
      _routeLine = await controller.addLine(
        LineOptions(
          geometry: geometry,
          lineColor: _editor.colorForSegment(0),
          lineWidth: 4,
          lineOpacity: 1,
          lineJoin: 'round',
        ),
      );
      await _frameRoute(route);
    } finally {
      _routeLineSyncing = false;
    }
  }, result: (_) => 'line=${_routeLine != null}');

  /// Recolore la ligne déjà affichée sans toucher à sa géométrie, sans
  /// rappeler le moteur et sans recadrer la caméra : réaction à
  /// [RouteEditorController.routeColorRevision] uniquement (changement de
  /// couleur de l'utilisateur), jamais à un nouveau calcul.
  Future<void> _updateRouteLineColor() => Diag.future('MapController._updateRouteLineColor', () async {
    final controller = _map;
    final line = _routeLine;
    if (controller == null || line == null) return;
    await controller.updateLine(line, LineOptions(lineColor: _editor.colorForSegment(0)));
  }, result: (_) => 'updated=${_routeLine != null}');

  /// Cadre la caméra sur l'emprise de la géométrie calculée.
  Future<void> _frameRoute(ComputedRoute route) async {
    final controller = _map;
    if (controller == null) return;
    var minLat = route.geometry.first.latitude;
    var maxLat = minLat;
    var minLon = route.geometry.first.longitude;
    var maxLon = minLon;
    for (final point in route.geometry) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLon = math.min(minLon, point.longitude);
      maxLon = math.max(maxLon, point.longitude);
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
  }, result: (_) => 'removedCircle=${_map != null}');

  Future<void> showPendingMarkerAt(LatLng latLng) => Diag.future(
    'MapController.showPendingMarkerAt',
    () async {
      final marker = MapMarkerItem(
        id: 'pending_${DateTime.now().millisecondsSinceEpoch}',
        name: MapMarkerItem.defaultPersonalizedName,
        type: 'personnalisé',
        latitude: latLng.latitude,
        longitude: latLng.longitude,
        orderIndex: _editor.validatedMarkers.length,
      );
      await showPendingMarker(marker, recenter: false);
    },
    params:
        'lat=${latLng.latitude.toStringAsFixed(5)} '
        'lon=${latLng.longitude.toStringAsFixed(5)}',
  );

  Future<void> showPendingMarker(MapMarkerItem marker, {bool recenter = true}) async {
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
