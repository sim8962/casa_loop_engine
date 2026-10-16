import '../../../objectbox.g.dart';

import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/services/repositories/marker_repository.dart';
import 'package:casa_loop_engine/models/entities/marker_entity.dart';
import 'package:casa_loop_engine/services/objectbox/objectbox_store.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Persistance des repères dans ObjectBox.
class ObjectBoxMarkerRepository implements MarkerRepository {
  ObjectBoxMarkerRepository(ObjectBoxStore objectBox) : _box = objectBox.store.box<MarkerEntity>();

  final Box<MarkerEntity> _box;

  @override
  Future<List<MapMarkerItem>> loadAll() => Diag.future('ObjectBoxMarkerRepository.loadAll', () async {
    final entities = await _box.getAllAsync();
    final markers = entities.map((entity) => entity.toModel()).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return markers;
  }, result: (markers) => 'count=${markers.length}');
}
