import 'package:casa_loop_engine/models/computed_route.dart';
import 'package:casa_loop_engine/models/route_target_result.dart';

/// Extrémités géographiques d'un segment de la boucle : le couple dirigé
/// de repères utilisateur à l'origine du segment (retour N→1 compris).
class RouteSegmentEndpoints {
  const RouteSegmentEndpoints({
    required this.startLat,
    required this.startLon,
    required this.endLat,
    required this.endLon,
  });

  final double startLat;
  final double startLon;
  final double endLat;
  final double endLon;
}

/// Appel moteur retournant la route principale puis les variantes
/// `alternates` du segment — injecté pour isoler la recherche du pont
/// natif dans les tests.
typedef RouteSegmentVariantsFetcher = Future<List<ComputedRoute>> Function({
  required double startLat,
  required double startLon,
  required double endLat,
  required double endLon,
  double? preference,
  int maxAlternates,
});

/// Recherche bornée de boucles proches d'une cible distance/durée.
///
/// Stratégie (voir ROUTING_TARGETS.md) : pour chaque segment de la
/// boucle de référence, un appel `alternates: n` récupère les variantes
/// produites par le moteur pour le même couple dirigé et la même
/// préférence ; chaque boucle candidate remplace exactement un segment
/// par une variante. Les repères, leur ordre, le retour N→1 et les
/// préférences sont préservés ; aucune géométrie n'est fabriquée —
/// chaque mesure provient du moteur.
///
/// Budgets : [_maxCandidateLoops] boucles candidates évaluées,
/// [_maxEngineCalls] appels supplémentaires, et une fenêtre de lancement
/// de [_maxLaunchWindow] vérifiée avant chaque nouvel appel. Les trois
/// limites s'appliquent ensemble ; la tolérance atteinte arrête la
/// recherche immédiatement. Les appels sont séquentiels — jamais
/// concurrents sur le pont natif.
class RouteTargetSearch {
  RouteTargetSearch({required this._fetchVariants});

  /// Maximum de boucles candidates évaluées en plus de la référence.
  static const int _maxCandidateLoops = 8;

  /// Maximum d'appels moteur supplémentaires lancés par une recherche.
  static const int _maxEngineCalls = 24;

  /// Fenêtre maximale pour lancer de nouveaux appels ; un appel déjà en
  /// vol peut se terminer après ce délai — sa réponse est ignorée si la
  /// recherche a été annulée ou invalidée entre-temps.
  static const Duration _maxLaunchWindow = Duration(seconds: 15);

  /// Variantes `alternates` demandées par segment — plafonné par
  /// `service_limits.max_alternates` de la configuration embarquée (2).
  static const int _maxAlternatesPerSegment = 2;

  /// Écart de mesure au-delà duquel deux routes sont considérées comme
  /// réellement distinctes (1 m / 1 s) — une variante aux mesures
  /// identiques à la référence n'apporte rien.
  static const double _measureEpsilonKm = 0.001;
  static const double _measureEpsilonSeconds = 1.0;

  final RouteSegmentVariantsFetcher _fetchVariants;

  /// Génération de la recherche : [cancel] l'incrémente, et toute
  /// réponse reçue pour une génération antérieure est ignorée.
  int _generation = 0;

  /// Demande l'arrêt de la recherche en cours : la boucle cesse de
  /// lancer des appels dès le prochain point de contrôle ; une réponse
  /// en vol peut arriver — elle est ignorée si la génération a changé.
  void cancel() => _generation++;

  /// Cherche une boucle plus proche de [target] que [reference].
  ///
  /// [endpoints] et [preferences] sont alignés sur
  /// `reference.segments` : même longueur, même ordre dirigé — capturés
  /// au lancement par l'appelant (snapshot cohérent).
  ///
  /// Ne lève pas d'exception métier : un appel variant en échec est
  /// sauté — la boucle de référence reste toujours un résultat complet
  /// valide.
  Future<RouteTargetSearchResult> search({
    required ComputedItinerary reference,
    required List<RouteSegmentEndpoints> endpoints,
    required List<double?> preferences,
    required RouteTarget target,
  }) async {
    assert(endpoints.length == reference.segments.length);
    assert(preferences.length == reference.segments.length);
    final generation = _generation;
    final launchedAt = DateTime.now();
    final launchDeadline = launchedAt.add(_maxLaunchWindow);

    var bestItinerary = reference;
    var bestComparison = RouteTargetComparison.forItinerary(reference, target);
    // La référence entre déjà dans la tolérance : cible approchée sans
    // dépenser le moindre appel moteur.
    if (bestComparison.withinTolerance) {
      return RouteTargetSearchResult(
        itinerary: reference,
        outcome: RouteTargetSearchOutcome.reached,
        candidateLoopsEvaluated: 0,
        engineCalls: 0,
        itineraryChanged: false,
      );
    }
    var engineCalls = 0;
    var candidateLoops = 0;
    var cancelled = false;

    bool isStale() => generation != _generation;

    outer:
    for (var index = 0; index < reference.segments.length; index++) {
      if (isStale()) {
        cancelled = true;
        break;
      }
      // Les trois budgets s'appliquent ensemble : le premier atteint
      // arrête le lancement de nouveaux appels.
      if (engineCalls >= _maxEngineCalls || candidateLoops >= _maxCandidateLoops) break;
      if (!DateTime.now().isBefore(launchDeadline)) break;

      engineCalls++;
      final endpointsOfSegment = endpoints[index];
      final List<ComputedRoute> variants;
      try {
        variants = await _fetchVariants(
          startLat: endpointsOfSegment.startLat,
          startLon: endpointsOfSegment.startLon,
          endLat: endpointsOfSegment.endLat,
          endLon: endpointsOfSegment.endLon,
          preference: preferences[index],
          maxAlternates: _maxAlternatesPerSegment,
        );
      } catch (_) {
        // Un appel variant en échec est ignoré : la référence et les
        // autres segments ne sont pas affectés.
        continue;
      }
      // Réponse en vol arrivée après annulation/invalidation : ignorée.
      if (isStale()) {
        cancelled = true;
        break;
      }

      final referenceRoute = reference.segments[index].route;
      for (final variant in variants.skip(1)) {
        if (_sameMeasures(variant, referenceRoute)) continue;
        candidateLoops++;
        final candidate = _withSegmentRoute(reference, index, variant, DateTime.now());
        final comparison = RouteTargetComparison.forItinerary(candidate, target);
        if (comparison.absRelativeDelta < bestComparison.absRelativeDelta) {
          bestItinerary = candidate;
          bestComparison = comparison;
        }
        if (comparison.withinTolerance) {
          // Arrêt anticipé : la cible est approchée, inutile d'explorer
          // davantage.
          break outer;
        }
        if (candidateLoops >= _maxCandidateLoops) break outer;
      }
    }

    return RouteTargetSearchResult(
      itinerary: bestItinerary,
      outcome: cancelled
          ? RouteTargetSearchOutcome.cancelled
          : bestComparison.withinTolerance
          ? RouteTargetSearchOutcome.reached
          : RouteTargetSearchOutcome.notReached,
      candidateLoopsEvaluated: candidateLoops,
      engineCalls: engineCalls,
      itineraryChanged: !identical(bestItinerary, reference),
    );
  }

  /// Construit la boucle candidate : même identité dirigée sur chaque
  /// segment (repères, numéros et couleurs préservés), seule la route du
  /// segment [index] est remplacée par la variante moteur. [computedAt]
  /// est l'instant de la variante retenue — la date de calcul du
  /// résultat assemblé, pas celle de la référence.
  static ComputedItinerary _withSegmentRoute(
    ComputedItinerary reference,
    int index,
    ComputedRoute route,
    DateTime computedAt,
  ) {
    final segments = List<TracedSegment>.of(reference.segments);
    segments[index] = TracedSegment(identity: segments[index].identity, route: route);
    return ComputedItinerary(segments: segments, computedAt: computedAt);
  }

  static bool _sameMeasures(ComputedRoute a, ComputedRoute b) =>
      (a.distanceKm - b.distanceKm).abs() <= _measureEpsilonKm &&
      (a.durationSeconds - b.durationSeconds).abs() <= _measureEpsilonSeconds;
}
