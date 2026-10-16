import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/models/route_draft_segment_preference.dart';
import 'package:casa_loop_engine/models/saved_route_snapshot.dart';

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
    required this.markers,
    required this.preferences,
    this.computedResult,
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
  final List<MapMarkerItem> markers;
  final List<RouteDraftSegmentPreference> preferences;

  /// Résultat moteur enregistré avec le trajet (boucle complète, retour
  /// inclus), ou `null` lorsque les réglages sauvegardés n'ont pas de
  /// tracé valide — état explicite « tracé à recalculer » : anciens
  /// trajets sans géométrie, ou géométrie devenue incohérente après
  /// modification des repères ou des préférences. Jamais restauré si
  /// son contenu ne correspond pas aux repères et préférences du
  /// trajet.
  final SavedRouteSnapshot? computedResult;
}
