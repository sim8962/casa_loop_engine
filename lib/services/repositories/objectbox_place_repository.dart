import 'dart:math' as math;

import '../../../objectbox.g.dart';

import 'package:casa_loop_engine/models/computed_route.dart';
import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/services/repositories/place_repository.dart';
import 'package:casa_loop_engine/services/search/place_search_key_service.dart';
import 'package:casa_loop_engine/services/search/place_search_ranking_service.dart';
import 'package:casa_loop_engine/models/entities/place_entity.dart';
import 'package:casa_loop_engine/services/objectbox/objectbox_store.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Recherche de localités dans ObjectBox.
class ObjectBoxPlaceRepository implements PlaceRepository {
  ObjectBoxPlaceRepository(ObjectBoxStore objectBox) : _box = objectBox.store.box<PlaceEntity>();

  final Box<PlaceEntity> _box;

  static const int _kCandidateLimit = 200;
  static const int _kResultLimit = 50;

  @override
  Future<List<MapMarkerItem>> search(String query) => Diag.future(
    'ObjectBoxPlaceRepository.search',
    () async {
      final normalized = PlaceSearchKeyService.normalize(query);
      if (normalized.isEmpty) {
        Diag.event('ObjectBoxPlaceRepository.search.early', 'emptyQuery');
        return [];
      }

      final q = _box.query(PlaceEntity_.searchKey.contains(normalized)).build();
      try {
        q.limit = _kCandidateLimit;
        final candidates = await q.findAsync();
        final ranked = PlaceSearchRankingService.rank(candidates, normalized);
        return ranked.take(_kResultLimit).map((e) => e.toMapMarker()).toList();
      } finally {
        q.close();
      }
    },
    params: 'query="$query"',
    result: (results) => 'count=${results.length}',
  );

  @override
  Future<MapMarkerItem?> nearest({
    required double latitude,
    required double longitude,
    double maxDistanceKm = 5,
  }) => Diag.future(
    'ObjectBoxPlaceRepository.nearest',
    () async {
      // Fenêtre bornée : les lieux sont des points, un rectangle autour du
      // point visé élague les candidats avant le calcul haversine exact.
      // Le delta de longitude tient compte de la convergence des
      // méridiens (planché à ~85° de latitude pour éviter toute division
      // extrême).
      final latDelta = maxDistanceKm / 111.0;
      final cosLat = math.cos(latitude * math.pi / 180).abs().clamp(0.09, 1.0);
      final lonDelta = maxDistanceKm / (111.0 * cosLat);
      final q = _box
          .query(
            PlaceEntity_.latitude
                .between(latitude - latDelta, latitude + latDelta)
                .and(PlaceEntity_.longitude.between(longitude - lonDelta, longitude + lonDelta)),
          )
          .build();
      try {
        final candidates = await q.findAsync();
        PlaceEntity? best;
        var bestMeters = maxDistanceKm * 1000;
        for (final entity in candidates) {
          final meters = ComputedRoute.haversineMeters(
            latitude,
            longitude,
            entity.latitude,
            entity.longitude,
          );
          if (meters <= bestMeters) {
            bestMeters = meters;
            best = entity;
          }
        }
        return best?.toMapMarker();
      } finally {
        q.close();
      }
    },
    params: 'lat=${latitude.toStringAsFixed(5)} lon=${longitude.toStringAsFixed(5)} maxKm=$maxDistanceKm',
    result: (marker) => 'found=${marker != null} name="${marker?.name ?? '-'}"',
  );
}

/// Extension de mapping minimal : `PlaceEntity` → `MapMarkerItem`.
///
/// Le nom affiché privilégie le français, puis le nom principal, l'arabe et
/// l'amazighe. Le type est normalisé en français pour l'UI.
extension PlaceEntityMapMarker on PlaceEntity {
  MapMarkerItem toMapMarker() => Diag.frequentSync('PlaceEntity.toMapMarker', () {
    final displayName = nameFr ?? nameAr ?? nameZgh ?? name;
    return MapMarkerItem(
      id: osmId,
      name: displayName,
      type: _displayType(placeType),
      latitude: latitude,
      longitude: longitude,
    );
  });
}

String _displayType(String? placeType) => Diag.frequentSync('PlaceEntity._displayType', () {
  switch (placeType) {
    case 'city':
    case 'town':
      return 'Ville';
    case 'village':
      return 'Village';
    case 'hamlet':
      return 'Hameau';
    case 'locality':
      return 'Lieu-dit';
    default:
      return placeType ?? 'Lieu';
  }
});
