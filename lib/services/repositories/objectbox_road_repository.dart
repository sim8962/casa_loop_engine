import '../../../objectbox.g.dart';

import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/services/repositories/road_repository.dart';
import 'package:casa_loop_engine/services/search/road_search_key_service.dart';
import 'package:casa_loop_engine/models/entities/road_entity.dart';
import 'package:casa_loop_engine/services/objectbox/objectbox_store.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Recherche de routes numérotées dans ObjectBox.
class ObjectBoxRoadRepository implements RoadRepository {
  ObjectBoxRoadRepository(ObjectBoxStore objectBox) : _box = objectBox.store.box<RoadEntity>();

  final Box<RoadEntity> _box;

  static const int _kResultLimit = 50;

  @override
  Future<List<MapMarkerItem>> search(String query, {double? latitude, double? longitude}) => Diag.future(
    'ObjectBoxRoadRepository.search',
    () async {
      final normalized = RoadSearchKeyService.normalize(query);
      if (normalized.isEmpty) {
        Diag.event('ObjectBoxRoadRepository.search.early', 'emptyQuery');
        return [];
      }

      final searchTerm = RoadSearchKeyService.canonicalizeReference(normalized);
      final q = _box.query(RoadEntity_.searchKey.contains(searchTerm)).order(RoadEntity_.reference).build();

      try {
        q.limit = _kResultLimit;
        final candidates = await q.findAsync();
        return candidates.map((e) => e.toMapMarker()).toList();
      } finally {
        q.close();
      }
    },
    params: 'query="$query" lat=$latitude lon=$longitude',
    result: (results) => 'count=${results.length}',
  );
}
