import 'package:objectbox/objectbox.dart';

/// Snapshot d'un trajet sauvegardé, persisté dans ObjectBox.
///
/// Plusieurs trajets indépendants sont conservés : chaque sauvegarde avec
/// un [id] existant met à jour ce trajet précis, sans affecter les autres.
@Entity()
class RouteDraftEntity {
  RouteDraftEntity({
    this.id = 0,
    required this.name,
    required this.createdAtMillis,
    required this.savedAtMillis,
    required this.targetMode,
    this.targetDistanceKm,
    this.targetDurationHours,
    required this.totalDistanceKm,
    required this.totalDurationHours,
    required this.averageSpeedKmh,
    required this.markersJson,
    required this.preferencesJson,
  });

  @Id()
  int id;

  /// Nom affiché dans la bibliothèque des trajets. Vide si l'utilisateur
  /// n'a jamais personnalisé le nom.
  String name;

  /// Date de création du trajet (premier enregistrement), fixée une fois
  /// pour toutes : base stable du nom par défaut.
  int createdAtMillis;

  int savedAtMillis;
  String targetMode;
  double? targetDistanceKm;
  double? targetDurationHours;
  double totalDistanceKm;
  double totalDurationHours;
  double averageSpeedKmh;

  /// Liste des repères encodée en JSON.
  String markersJson;

  /// Liste des préférences de route encodée en JSON.
  String preferencesJson;
}
