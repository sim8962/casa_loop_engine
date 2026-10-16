import 'package:casa_loop_engine/models/map_marker_item.dart';

/// Contrat d'accès aux lieux (villes, villages, douars) pour la recherche.
///
/// L'implémentation attendue en production est `ObjectBoxPlaceRepository`.
abstract class PlaceRepository {
  Future<List<MapMarkerItem>> search(String query);

  /// Lieu le plus proche des coordonnées, dans un rayon de
  /// [maxDistanceKm] à vol d'oiseau ; `null` si aucun lieu répertorié.
  /// Sert à proposer un nom indicatif (ville, village, lieu-dit) au repère
  /// posé à la main, à la place du générique « Repère ».
  Future<MapMarkerItem?> nearest({
    required double latitude,
    required double longitude,
    double maxDistanceKm = 5,
  });
}
