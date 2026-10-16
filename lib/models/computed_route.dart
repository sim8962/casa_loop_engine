import 'dart:math' as math;

/// Identité des deux repères à l'origine d'un segment tracé, capturée au
/// lancement du calcul : identifiants stables et numéros affichés à cet
/// instant (position dans la liste, 1-indexée). Associée au résultat pour
/// que le libellé affiché (`Rep. X → Rep. Y`) reste celui du calcul, même
/// si les repères sont réordonnés ou renommés par la suite — une
/// réorganisation invalide le résultat (nouveau calcul requis) plutôt que
/// de réattribuer de nouveaux numéros à un ancien résultat.
class TracedSegmentIdentity {
  const TracedSegmentIdentity({
    required this.startMarkerId,
    required this.endMarkerId,
    required this.startNumber,
    required this.endNumber,
  });

  final String startMarkerId;
  final String endMarkerId;
  final int startNumber;
  final int endNumber;
}

/// Point géographique d'une géométrie calculée par le moteur.
class ComputedRoutePoint {
  const ComputedRoutePoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  String toString() => '($latitude, $longitude)';
}

/// Résultat d'un calcul A→B par le moteur Valhalla embarqué : géométrie
/// routière réelle et mesures moteur extraites de `trip.summary`, plus la
/// distance d'accrochage des extrémités par rapport aux repères demandés.
///
/// `trip.locations` n'est jamais utilisé comme preuve du snapping : la
/// distance d'accrochage est mesurée entre les extrémités de la géométrie
/// décodée et les points demandés.
class ComputedRoute {
  const ComputedRoute({
    required this.geometry,
    required this.distanceKm,
    required this.durationSeconds,
    required this.startSnapDistanceMeters,
    required this.endSnapDistanceMeters,
  });

  /// Géométrie routière complète du segment, décodée depuis `shape`
  /// (polyline à 6 décimales de précision — format Valhalla).
  final List<ComputedRoutePoint> geometry;

  /// Longueur du trajet selon le moteur, en kilomètres (`units=kilometers`).
  final double distanceKm;

  /// Durée du trajet selon le moteur, en secondes.
  final double durationSeconds;

  /// Distance entre le repère de départ demandé et le début de la géométrie,
  /// en mètres.
  final double startSnapDistanceMeters;

  /// Distance entre le repère d'arrivée demandé et la fin de la géométrie,
  /// en mètres.
  final double endSnapDistanceMeters;

  /// Écart maximal toléré entre une extrémité de la géométrie et le repère
  /// demandé avant de considérer le résultat comme invalide.
  static const double maxSnapDistanceMeters = 1000.0;

  /// Décode une réponse JSON native Valhalla (`route`) : géométrie polyline6
  /// du premier leg et résumé de `trip.summary`. Lève [FormatException] si la
  /// réponse n'a pas la structure attendue.
  factory ComputedRoute.fromValhallaJson(
    Map<String, dynamic> response, {
    required double requestedStartLat,
    required double requestedStartLon,
    required double requestedEndLat,
    required double requestedEndLon,
  }) {
    final trip = response['trip'];
    if (trip is! Map<String, dynamic>) {
      throw const FormatException('Réponse Valhalla sans objet "trip".');
    }
    final summary = trip['summary'];
    if (summary is! Map<String, dynamic>) {
      throw const FormatException('Réponse Valhalla sans "trip.summary".');
    }
    final length = summary['length'];
    final time = summary['time'];
    if (length is! num || time is! num) {
      throw const FormatException('trip.summary sans mesures length/time.');
    }
    final legs = trip['legs'];
    if (legs is! List || legs.isEmpty) {
      throw const FormatException('Réponse Valhalla sans leg.');
    }
    final firstLeg = legs.first;
    if (firstLeg is! Map<String, dynamic> || firstLeg['shape'] is! String) {
      throw const FormatException('Premier leg sans géométrie "shape".');
    }
    final geometry = decodePolyline6(firstLeg['shape'] as String);
    if (geometry.length < 2) {
      throw const FormatException('Géométrie vide ou dégénérée.');
    }
    return ComputedRoute(
      geometry: geometry,
      distanceKm: length.toDouble(),
      durationSeconds: time.toDouble(),
      startSnapDistanceMeters: haversineMeters(
        requestedStartLat,
        requestedStartLon,
        geometry.first.latitude,
        geometry.first.longitude,
      ),
      endSnapDistanceMeters: haversineMeters(
        requestedEndLat,
        requestedEndLon,
        geometry.last.latitude,
        geometry.last.longitude,
      ),
    );
  }

  /// Décode une réponse pouvant contenir des variantes `alternates`
  /// (demandées avec `alternates: n` sur une requête à 2 localisations —
  /// le moteur force 0 au-delà) : la route principale suivie de chaque
  /// variante `{ "trip": … }` sérialisée par le moteur sous
  /// `response['alternates']`. Une variante malformée est ignorée sans
  /// compromettre la route principale ; le `trip` principal, lui, lève
  /// [FormatException] comme [fromValhallaJson].
  static List<ComputedRoute> listFromValhallaJson(
    Map<String, dynamic> response, {
    required double requestedStartLat,
    required double requestedStartLon,
    required double requestedEndLat,
    required double requestedEndLon,
  }) {
    final routes = <ComputedRoute>[
      ComputedRoute.fromValhallaJson(
        response,
        requestedStartLat: requestedStartLat,
        requestedStartLon: requestedStartLon,
        requestedEndLat: requestedEndLat,
        requestedEndLon: requestedEndLon,
      ),
    ];
    final alternates = response['alternates'];
    if (alternates is List) {
      for (final alternate in alternates) {
        if (alternate is! Map<String, dynamic>) continue;
        try {
          routes.add(
            ComputedRoute.fromValhallaJson(
              alternate,
              requestedStartLat: requestedStartLat,
              requestedStartLon: requestedStartLon,
              requestedEndLat: requestedEndLat,
              requestedEndLon: requestedEndLon,
            ),
          );
        } on FormatException {
          // Variante inutilisable : ignorée, les autres restent valides.
        }
      }
    }
    return routes;
  }

  /// Décode une polyline encodée à 6 décimales de précision (format de
  /// géométrie produit par Valhalla dans `legs[].shape`).
  static List<ComputedRoutePoint> decodePolyline6(String encoded) {
    final points = <ComputedRoutePoint>[];
    var index = 0;
    var latitude = 0;
    var longitude = 0;
    while (index < encoded.length) {
      var result = 0;
      var shift = 0;
      int byte;
      do {
        if (index >= encoded.length) {
          throw const FormatException('Polyline tronquée.');
        }
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      final deltaLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      latitude += deltaLat;

      result = 0;
      shift = 0;
      do {
        if (index >= encoded.length) {
          throw const FormatException('Polyline tronquée.');
        }
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      final deltaLon = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      longitude += deltaLon;

      points.add(ComputedRoutePoint(latitude: latitude / 1e6, longitude: longitude / 1e6));
    }
    return points;
  }

  /// Distance orthodromique en mètres entre deux points WGS84.
  static double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusMeters = 6371000.0;
    const degToRad = 3.141592653589793 / 180.0;
    final dLat = (lat2 - lat1) * degToRad;
    final dLon = (lon2 - lon1) * degToRad;
    final sinDLat = math.sin(dLat / 2);
    final sinDLon = math.sin(dLon / 2);
    final a = sinDLat * sinDLat + math.cos(lat1 * degToRad) * math.cos(lat2 * degToRad) * sinDLon * sinDLon;
    final c = 2 * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
    return earthRadiusMeters * c;
  }
}

/// Un segment du trajet calculé par « Tracer » : géométrie et mesures
/// moteur retournées pour le couple dirigé décrit par [identity].
class TracedSegment {
  const TracedSegment({required this.identity, required this.route});

  /// Couple dirigé (identifiants stables et numéros affichés au lancement
  /// du calcul) à l'origine de [route]. Sert aussi à retrouver la couleur
  /// choisie pour ce couple, indépendamment de la position du segment.
  final TracedSegmentIdentity identity;

  /// Résultat moteur du segment.
  final ComputedRoute route;
}

/// Résultat complet d'un « Tracer » : les N segments de la boucle
/// 1→2→…→N→1 (segments consécutifs puis retour obligatoire du dernier
/// repère au départ), chacun conservé avec son identité dirigée. Les
/// totaux sont la somme exacte des distances et durées moteur de tous
/// les segments, retour compris.
class ComputedItinerary {
  const ComputedItinerary({required this.segments, required this.computedAt});

  /// Segments calculés, dans l'ordre des repères au lancement du calcul.
  final List<TracedSegment> segments;

  /// Date à laquelle le contenu de cette boucle a été calculé/fixé par
  /// le moteur : l'instant de publication d'un « Tracer » complet, ou
  /// celui de la recherche qui a produit une variante retenue ; pour un
  /// résultat restauré depuis la bibliothèque, la date du calcul initial
  /// enregistrée dans le snapshot. Distincte de la date de sauvegarde
  /// du trajet.
  final DateTime computedAt;

  /// Somme des distances moteur ([ComputedRoute.distanceKm]), en km.
  double get totalDistanceKm {
    var total = 0.0;
    for (final segment in segments) {
      total += segment.route.distanceKm;
    }
    return total;
  }

  /// Somme des durées moteur ([ComputedRoute.durationSeconds]), en secondes.
  double get totalDurationSeconds {
    var total = 0.0;
    for (final segment in segments) {
      total += segment.route.durationSeconds;
    }
    return total;
  }
}
