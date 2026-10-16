import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Client Dart du canal natif `casa/routing` (cf. `RoutingBridge.swift`).
///
/// Le pont natif exécute `configure` et `route` sur une file série hors
/// thread principal et réutilise une seule instance du moteur. Les erreurs
/// natives arrivent ici en [PlatformException].
class ValhallaRouteEngine {
  const ValhallaRouteEngine();

  static const MethodChannel _channel = MethodChannel('casa/routing');

  /// Configure le moteur natif à partir du fichier JSON Valhalla situé à
  /// [configPath] (chemin absolu dans le stockage de l'application). À
  /// appeler une fois avant [routeRaw] ; idempotent côté natif, une nouvelle
  /// instance remplace l'ancienne.
  Future<void> configure(String configPath) => Diag.future('ValhallaRouteEngine.configure', () async {
    await _channel.invokeMethod<void>('configure', <String, Object>{'configPath': configPath});
  }, params: 'configPath=$configPath');

  /// Construit la requête JSON native Valhalla pour un calcul A→B moto :
  /// `motorcycle`, `units=kilometers`, `directions_type=none`. Les points
  /// sont des records `(lat, lon)` dans l'ordre demandé.
  ///
  /// [costingOptions], quand il est fourni, est émis tel quel sous
  /// `costing_options.motorcycle` — seules des options prises en charge
  /// par le costing motorcycle embarqué doivent y figurer (voir
  /// `RoutePreferenceCosting`). Sans option explicite, aucune clé
  /// `costing_options` n'est envoyée : le moteur applique ses valeurs
  /// motorcycle standard.
  ///
  /// [alternates], quand il est fourni, est émis sous `alternates` :
  /// le moteur retourne alors jusqu'à `service_limits.max_alternates`
  /// routes de remplacement pour le même couple — forcé à 0 par le
  /// moteur si la requête porte plus de 2 localisations (vérifié dans
  /// `src/worker.cc`), donc réservé aux appels A→B à 2 points.
  static String buildMotorcycleRequest(
    List<(double, double)> points, {
    Map<String, Object>? costingOptions,
    int? alternates,
  }) => jsonEncode(<String, Object?>{
    'locations': [
      for (final (lat, lon) in points) <String, Object?>{'lat': lat, 'lon': lon, 'type': 'break'},
    ],
    'costing': 'motorcycle',
    if (costingOptions != null) 'costing_options': <String, Object>{'motorcycle': costingOptions},
    'alternates': ?alternates,
    'units': 'kilometers',
    'directions_type': 'none',
  });

  /// Exécute une requête `route` brute et retourne le JSON de réponse
  /// décodé. Lève [PlatformException] si le moteur natif échoue.
  Future<Map<String, dynamic>> routeRaw(String requestJson) => Diag.future(
    'ValhallaRouteEngine.routeRaw',
    () async {
      final response = await _channel.invokeMethod<String>('route', <String, Object>{'request': requestJson});
      if (response == null) {
        throw StateError('Réponse nulle du moteur de calcul.');
      }
      final decoded = jsonDecode(response);
      if (decoded is! Map<String, dynamic>) {
        throw FormatException('Réponse inattendue du moteur : ${decoded.runtimeType}.');
      }
      return decoded;
    },
    params: 'requestBytes=${requestJson.length}',
  );

  /// Raccourci : construit la requête moto pour [points] puis l'exécute.
  /// [costingOptions] et [alternates] suivent la même convention que
  /// [buildMotorcycleRequest].
  Future<Map<String, dynamic>> routeMotorcycle(
    List<(double, double)> points, {
    Map<String, Object>? costingOptions,
    int? alternates,
  }) => routeRaw(buildMotorcycleRequest(points, costingOptions: costingOptions, alternates: alternates));
}
