import 'package:casa_loop_engine/models/map_marker_item.dart';

/// Persistance des repères validés par l'utilisateur.
///
/// L'interface isole les controllers du moteur de stockage : ObjectBox en
/// production.
abstract interface class MarkerRepository {
  Future<List<MapMarkerItem>> loadAll();

  /// Insère le repère ou met à jour celui qui porte le même identifiant.
  Future<void> save(MapMarkerItem marker);

  /// Insère ou met à jour plusieurs repères en une seule opération.
  Future<void> saveAll(List<MapMarkerItem> markers);

  Future<void> delete(String markerId);

  Future<void> replaceAll(List<MapMarkerItem> markers);
}
