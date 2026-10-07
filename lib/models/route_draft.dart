import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/models/route_draft_segment_preference.dart';

/// Snapshot d'un trajet en cours, prêt à être persisté dans ObjectBox.
class RouteDraft {
  RouteDraft({
    this.id,
    required this.name,
    required this.createdAt,
    required this.savedAt,
    required this.targetMode,
    this.targetDistanceKm,
    this.targetDurationHours,
    required this.totalDistanceKm,
    required this.totalDurationHours,
    required this.averageSpeedKmh,
    required this.markers,
    required this.preferences,
  });

  /// Identifiant unique du trajet sauvegardé ; `null` tant qu'il n'a jamais
  /// été écrit dans le repository (première sauvegarde à venir).
  final String? id;

  /// Nom affiché dans la bibliothèque des trajets. Vide si l'utilisateur
  /// n'a jamais personnalisé le nom : l'affichage retombe alors sur le nom
  /// par défaut dérivé de [createdAt].
  final String name;

  /// Date de création du trajet, fixée une fois pour toutes à la première
  /// sauvegarde : sert de base stable au nom par défaut, qui ne change pas
  /// au fil des sauvegardes suivantes.
  final DateTime createdAt;

  final DateTime savedAt;

  /// Nom du [LoopTargetMode] : 'distance' ou 'duration'.
  final String targetMode;

  final double? targetDistanceKm;
  final double? targetDurationHours;
  final double totalDistanceKm;
  final double totalDurationHours;
  final double averageSpeedKmh;
  final List<MapMarkerItem> markers;
  final List<RouteDraftSegmentPreference> preferences;
}
