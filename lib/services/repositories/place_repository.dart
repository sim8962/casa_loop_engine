import 'package:casa_loop_engine/models/map_marker_item.dart';

/// Contrat d'accès aux lieux (villes, villages, douars) pour la recherche.
///
/// L'implémentation attendue en production est `ObjectBoxPlaceRepository`.
abstract class PlaceRepository {
  Future<List<MapMarkerItem>> search(
    String query, {
    double? latitude,
    double? longitude,
  });
}
