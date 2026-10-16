import 'package:casa_loop_engine/models/map_marker_item.dart';

/// Contrat d'accès aux routes numérotées (RN, RR, RP) pour la recherche.
///
/// L'implémentation attendue en production est `ObjectBoxRoadRepository`.
abstract class RoadRepository {
  Future<List<MapMarkerItem>> search(String query);
}
