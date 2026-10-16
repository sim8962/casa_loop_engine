import 'package:casa_loop_engine/models/map_marker_item.dart';

/// Persistance des repères validés par l'utilisateur.
///
/// L'interface isole les controllers du moteur de stockage : ObjectBox en
/// production.
abstract interface class MarkerRepository {
  Future<List<MapMarkerItem>> loadAll();
}
