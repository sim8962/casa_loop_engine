/// Correspondance entre le curseur de préférence de segment
/// (0 = Rapide, 100 = Trail) et les options `costing_options.motorcycle`
/// réellement prises en charge par la version Valhalla embarquée.
///
/// Options retenues — vérifiées dans le sous-module (lecture seule) :
///
/// - `use_highways` (float [0,1], défaut 0.5) :
///   `src/sif/motorcyclecost.cc` — borne `kUseHighwaysRange` l. 54, parse
///   l. 614, calcul de `highway_factor_` l. 314-321, application
///   `highway_factor_ * kHighwayFactor[classification]` l. 435 avec
///   `kHighwayFactor` l. 60-69 : seules les classes Motorway (1.0) et
///   Trunk (0.5) sont pondérées. < 0.5 pénalise les autoroutes et
///   voies rapides jusqu'à `kMaxHighwayBiasFactor` = 8
///   (`valhalla/sif/dynamiccost.h` l. 199) ; > 0.5 les favorise
///   légèrement (jusqu'à -0.125).
///
/// - `use_tracks` (float [0,1], défaut 0.5) : option de base —
///   `src/sif/dynamiccost.cc` parse l. 596, `set_use_tracks` l. 420-431
///   (pénalité d'entrée jusqu'à 300 s et facteur de coût 0.8 à 4),
///   appliquée dans `motorcyclecost.cc` l. 442-443 (`Use::kTrack`) et
///   `dynamiccost.h` l. 1589 (`track_penalty_` à la transition).
///   < 0.5 évite les pistes `highway=track` ; > 0.5 les favorise
///   légèrement.
///
/// - `use_trails` (float [0,1], défaut 0.0 pour motorcycle) :
///   `src/sif/motorcyclecost.cc` — borne `kUseTrailsRange` l. 56, parse
///   l. 616, calcul de `surface_factor_` l. 340-346, application
///   `surface_factor_ * kSurfaceFactor[surface]` l. 436 avec
///   `kSurfaceFactor` l. 73-81 (kCompacted 0.1 … kPath 1.0). < 0.5
///   pénalise les revêtements dégradés/non revêtus (facteur entier
///   jusqu'à 8) ; > 0.5 les favorise légèrement (jusqu'à -0.125).
///
/// Limites assumées (voir `ROUTING_PREFERENCES.md`) : aucune de ces
/// options ne garantit un type de route — elles pondèrent le coût, sans
/// jamais ouvrir une voie interdite ni garantir une piste disponible ;
/// tolérer un revêtement n'est pas une autorisation d'accès ; aucun
/// mécanisme « routes sinueuses » n'existe dans cette version, donc
/// aucune position du curseur ne promet de virages.
///
/// Les options `ignore_*` (restrictions, sens uniques, accès) ne sont
/// jamais transmises : les restrictions d'accès, de virage et les sens
/// uniques restent appliqués quelle que soit la préférence.
class RoutePreferenceCosting {
  RoutePreferenceCosting._();

  /// Position du curseur : 0 = Rapide, 100 = Trail.
  static const double min = 0;
  static const double max = 100;

  /// Options `costing_options.motorcycle` pour la préférence
  /// [preference]. Le mapping est linéaire et symétrique :
  /// `use_highways` décroît de 1 à 0 tandis que `use_tracks` et
  /// `use_trails` croissent de 0 à 1 — la position 50 produit donc un
  /// profil neutre (les trois options à 0.5).
  ///
  /// Valeurs aux positions de repère :
  ///
  /// | préf. | use_highways | use_tracks | use_trails |
  /// |-------|--------------|------------|------------|
  /// | 0     | 1.0          | 0.0        | 0.0        |
  /// | 25    | 0.75         | 0.25       | 0.25       |
  /// | 50    | 0.5          | 0.5        | 0.5        |
  /// | 75    | 0.25         | 0.75       | 0.75       |
  /// | 100   | 0.0          | 1.0        | 1.0        |
  ///
  /// Les positions intermédiaires suivent la même interpolation
  /// linéaire ; les valeurs hors bornes sont bornées à [min, max] et
  /// une valeur non finie lève [ArgumentError] — jamais d'option
  /// silencieusement fausse.
  static Map<String, Object> optionsFor(double preference) {
    if (!preference.isFinite) {
      throw ArgumentError.value(preference, 'preference', 'Préférence non finie.');
    }
    // (max − p)/max plutôt que 1 − p/max : la division produit la valeur
    // double la plus proche (ex. 0.2 au lieu de 0.19999999999999996),
    // pour une requête JSON lisible et stable.
    final p = preference.clamp(min, max);
    return <String, Object>{'use_highways': (max - p) / max, 'use_tracks': p / max, 'use_trails': p / max};
  }
}
