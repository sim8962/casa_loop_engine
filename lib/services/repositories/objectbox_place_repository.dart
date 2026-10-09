import '../../../objectbox.g.dart';

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
  Future<List<MapMarkerItem>> search(String query, {double? latitude, double? longitude}) => Diag.future(
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
        final ranked = PlaceSearchRankingService.rank(
          candidates,
          normalized,
          latitude: latitude,
          longitude: longitude,
        );
        return ranked.take(_kResultLimit).map((e) => e.toMapMarker()).toList();
      } finally {
        q.close();
      }
    },
    params: 'query="$query" lat=$latitude lon=$longitude',
    result: (results) => 'count=${results.length}',
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
