import 'computed_route.dart';

/// Unité de la cible utilisateur — l'affichage choisit Distance (km) ou
/// Durée (heures) ; la comparaison se fait toujours dans l'unité de la
/// cible, mesurée par le moteur.
enum RouteTargetUnit { kilometers, hours }

/// Cible d'ajustement saisie par l'utilisateur. Valide uniquement si la
/// valeur est finie et strictement positive — les cibles nulles,
/// négatives ou non finies sont refusées dès le modèle.
class RouteTarget {
  const RouteTarget({required this.unit, required this.value});

  final RouteTargetUnit unit;
  final double value;

  /// Tolérance relative : une cible est « approchée » uniquement si
  /// l'écart relatif absolu du résultat est ≤ 5 %.
  static const toleranceRatio = 0.05;

  bool get isValid => value.isFinite && value > 0;

  /// Libellé court de la cible pour l'affichage (ex. « 120 km »,
  /// « 2,5 h »).
  String get label => unit == RouteTargetUnit.kilometers ? '$value km' : '$value h';
}

/// Comparaison d'un itinéraire complet à une cible valide. Les mesures
/// comparées sont les totaux moteur de la boucle (retour compris) dans
/// l'unité de la cible — jamais les estimations indicatives.
class RouteTargetComparison {
  const RouteTargetComparison({required this.target, required this.actualValue});

  final RouteTarget target;

  /// Valeur réelle mesurée : km pour une cible distance, heures pour
  /// une cible durée.
  final double actualValue;

  factory RouteTargetComparison.forItinerary(ComputedItinerary itinerary, RouteTarget target) =>
      RouteTargetComparison(
        target: target,
        actualValue: target.unit == RouteTargetUnit.kilometers
            ? itinerary.totalDistanceKm
            : itinerary.totalDurationSeconds / 3600,
      );

  /// Écart signé dans l'unité de la cible (positif = au-dessus).
  double get signedDelta => actualValue - target.value;

  /// Écart relatif signé ; `target.value` est garanti > 0 par
  /// [RouteTarget.isValid], vérifié à la construction des cibles
  /// exploitées — protégé contre une division nulle défensivement.
  double get relativeDelta => target.value > 0 ? signedDelta / target.value : 0.0;

  /// Écart absolu relatif — mesure de sélection des candidats.
  double get absRelativeDelta => relativeDelta.abs();

  bool get withinTolerance => target.isValid && absRelativeDelta <= RouteTarget.toleranceRatio;
}

/// Issue d'une recherche bornée de variantes.
enum RouteTargetSearchOutcome {
  /// Un candidat a satisfait la tolérance — meilleur résultat publié.
  reached,

  /// Recherche épuisée sans candidat dans la tolérance — meilleur
  /// résultat complet conservé (référence incluse).
  notReached,

  /// Arrêt utilisateur ou invalidation : le meilleur résultat complet
  /// déjà trouvé est conservé.
  cancelled,
}

/// Résultat complet d'une recherche bornée de variantes : toujours une
/// boucle entière (référence ou variante), jamais un état partiel.
class RouteTargetSearchResult {
  const RouteTargetSearchResult({
    required this.itinerary,
    required this.outcome,
    required this.candidateLoopsEvaluated,
    required this.engineCalls,
    required this.itineraryChanged,
  });

  /// Meilleure boucle complète trouvée — la référence si aucune
  /// variante ne fait mieux.
  final ComputedItinerary itinerary;

  final RouteTargetSearchOutcome outcome;

  /// Boucles candidates évaluées (référence exclue) — ≤ 8.
  final int candidateLoopsEvaluated;

  /// Appels moteur supplémentaires réellement lancés — ≤ 24.
  final int engineCalls;

  /// Vrai si [itinerary] diffère de la référence (variante meilleure).
  final bool itineraryChanged;
}
