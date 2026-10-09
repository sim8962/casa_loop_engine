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

  @override
  Future<void> save(MapMarkerItem marker) => Diag.future(
    'ObjectBoxMarkerRepository.save',
    () async {
      final existing = await _findByMarkerId(marker.id);
      final entity = MarkerEntity.fromModel(marker)..id = existing?.id ?? 0;
      await _box.putAsync(entity);
    },
    params: 'markerId=${marker.id} orderIndex=${marker.orderIndex}',
    result: (_) => 'saved=${marker.id}',
  );

  @override
  Future<void> saveAll(List<MapMarkerItem> markers) =>
      Diag.future('ObjectBoxMarkerRepository.saveAll', () async {
        final entities = markers.map((marker) => MarkerEntity.fromModel(marker)..id = 0).toList();
        await _box.putManyAsync(entities);
      }, params: 'count=${markers.length}');

  @override
  Future<void> delete(String markerId) async {
    final op = Diag.start('ObjectBoxMarkerRepository.delete', 'markerId=$markerId');
    try {
      final existing = await _findByMarkerId(markerId);
      if (existing == null) {
        op.early('notFound');
        return;
      }
      await _box.removeAsync(existing.id);
      op.end('deleted=$markerId');
    } catch (exception, stack) {
      op.fail(exception, stack);
      rethrow;
    }
  }

  @override
  Future<void> replaceAll(List<MapMarkerItem> markers) async {
    _box.removeAll();
    _box.putMany(markers.map(MarkerEntity.fromModel).toList());
  }

  Future<MarkerEntity?> _findByMarkerId(String markerId) => Diag.future(
    'ObjectBoxMarkerRepository._findByMarkerId',
    () async {
      final query = _box.query(MarkerEntity_.markerId.equals(markerId)).build();
      try {
        return query.findFirst();
      } finally {
        query.close();
      }
    },
    params: 'markerId=$markerId',
    result: (entity) => 'found=${entity != null}',
  );
}
