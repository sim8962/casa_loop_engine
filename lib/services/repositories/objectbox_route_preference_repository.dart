import '../../../objectbox.g.dart';

import 'package:casa_loop_engine/services/repositories/route_preference_repository.dart';
import 'package:casa_loop_engine/models/entities/route_preference_entity.dart';
import 'package:casa_loop_engine/services/objectbox/objectbox_store.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Persistance des préférences de route dans ObjectBox.
class ObjectBoxRoutePreferenceRepository implements RoutePreferenceRepository {
  ObjectBoxRoutePreferenceRepository(ObjectBoxStore objectBox)
    : _box = objectBox.store.box<RoutePreferenceEntity>();

  final Box<RoutePreferenceEntity> _box;

  @override
  Future<double?> load(String startMarkerId, String endMarkerId) => Diag.future(
    'ObjectBoxRoutePreferenceRepository.load',
    () async {
      final existing = await _find(startMarkerId, endMarkerId);
      return existing?.value;
    },
    params: 'start=$startMarkerId end=$endMarkerId',
    result: (value) => 'value=$value',
  );

  Future<RoutePreferenceEntity?> _find(String start, String end) => Diag.future(
    'ObjectBoxRoutePreferenceRepository._find',
    () async {
      final query = _box
          .query(
            RoutePreferenceEntity_.startMarkerId
                .equals(start)
                .and(RoutePreferenceEntity_.endMarkerId.equals(end)),
          )
          .build();
      try {
        return query.findFirst();
      } finally {
        query.close();
      }
    },
    params: 'start=$start end=$end',
    result: (entity) => 'found=${entity != null}',
  );
}
