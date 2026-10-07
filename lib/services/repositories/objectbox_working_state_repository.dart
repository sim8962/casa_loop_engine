import '../../../objectbox.g.dart';
import '../../models/entities/marker_entity.dart';
import '../../models/entities/route_preference_entity.dart';
import '../../models/map_marker_item.dart';
import '../../models/route_draft_segment_preference.dart';
import '../objectbox/objectbox_store.dart';

/// Remplacement indivisible de l'état de travail ObjectBox (sans le brouillon).
///
/// `RoutePreferenceEntity` n'a pas de champ couleur ([RouteDraftSegmentPreference.color]
/// est ignoré ici) : l'ajouter imposerait un changement de schéma ObjectBox.
/// La couleur de chaque segment de l'état de travail est donc persistée
/// séparément par `RouteEditorController`, dans GetStorage.
class ObjectBoxWorkingStateRepository {
  ObjectBoxWorkingStateRepository(ObjectBoxStore objectBox) : _store = objectBox.store;
  final Store _store;

  Future<void> replace(List<MapMarkerItem> markers, List<RouteDraftSegmentPreference> preferences) async {
    _store.runInTransaction(TxMode.write, () {
      final markerBox = _store.box<MarkerEntity>();
      final preferenceBox = _store.box<RoutePreferenceEntity>();
      markerBox.removeAll();
      preferenceBox.removeAll();
      markerBox.putMany(markers.map(MarkerEntity.fromModel).toList());
      preferenceBox.putMany(
        preferences
            .map(
              (p) => RoutePreferenceEntity(
                startMarkerId: p.startMarkerId,
                endMarkerId: p.endMarkerId,
                value: p.value,
              ),
            )
            .toList(),
      );
    });
  }
}
