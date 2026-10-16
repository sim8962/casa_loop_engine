import 'dart:convert';

import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';
import 'package:casa_loop_engine/models/computed_route.dart';
import 'package:casa_loop_engine/models/saved_route_snapshot.dart';

/// Erreur contrôlée de lecture/écriture d'un snapshot de tracé :
/// structure inattendue, valeur hors domaine, version non prise en
/// charge. Levée à la place de toute erreur brute de conversion pour
/// que l'appelant distingue un snapshot invalide d'une panne de
/// persistance — et récupère les repères du trajet quand même.
class RouteSnapshotFormatException implements Exception {
  const RouteSnapshotFormatException(this.message);

  final String message;

  @override
  String toString() => 'RouteSnapshotFormatException: $message';
}

/// Sérialisation JSON du [SavedRouteSnapshot] stocké avec chaque trajet
/// (champ `snapshotJson` de `RouteDraftEntity`).
///
/// Format versionné ([SavedRouteSnapshot.currentVersion] = 1) : toute
/// version différente lue est rejetée par une
/// [RouteSnapshotFormatException] explicite — jamais par une lecture
/// partielle silencieuse ni un contournement qui inventerait des
/// données. Toutes les valeurs numériques non finies, coordonnées hors
/// bornes et structures incohérentes (chaîne de segments qui ne forme
/// pas une boucle dirigée, géométrie dégénérée) sont rejetées à
/// l'écriture comme à la lecture.
///
/// Les doubles sont sérialisés par `jsonEncode` (représentation la plus
/// courte qui se relit à l'identique) : la précision des coordonnées et
/// des mesures moteur est préservée à l'aller-retour.
abstract final class RouteSnapshotCodec {
  /// Encode [snapshot] en JSON. Lève [RouteSnapshotFormatException] si
  /// le snapshot est incohérent ou porte des valeurs non finies — un
  /// trajet ne stocke jamais un résultat partiellement valide.
  static String encode(SavedRouteSnapshot snapshot) => Diag.sync(
    'RouteSnapshotCodec.encode',
    () {
      _validate(snapshot);
      try {
        return jsonEncode({
          'version': snapshot.version,
          'computedAtMillis': snapshot.computedAt.millisecondsSinceEpoch,
          'engine': snapshot.engineName,
          if (snapshot.packFileName != null) 'packFileName': snapshot.packFileName,
          if (snapshot.packSha256 != null) 'packSha256': snapshot.packSha256,
          'segments': [
            for (final segment in snapshot.segments)
              {
                'startMarkerId': segment.identity.startMarkerId,
                'endMarkerId': segment.identity.endMarkerId,
                'startNumber': segment.identity.startNumber,
                'endNumber': segment.identity.endNumber,
                'preference': segment.preference,
                'distanceKm': segment.route.distanceKm,
                'durationSeconds': segment.route.durationSeconds,
                'startSnapMeters': segment.route.startSnapDistanceMeters,
                'endSnapMeters': segment.route.endSnapDistanceMeters,
                'geometry': [
                  for (final point in segment.route.geometry) [point.latitude, point.longitude],
                ],
              },
          ],
        });
      } on Object catch (error) {
        // Filet de sécurité : la validation précédente devrait déjà
        // avoir rejeté toute valeur non encodable (NaN/∞).
        throw RouteSnapshotFormatException('Snapshot non encodable : $error');
      }
    },
    params: 'segments=${snapshot.segments.length}',
    result: (json) => 'bytes=${json.length}',
  );

  /// Décode [json] en [SavedRouteSnapshot]. Lève
  /// [RouteSnapshotFormatException] — contrôlée — pour JSON malformé,
  /// version non prise en charge ou contenu incohérent ; l'appelant
  /// traite le trajet comme « à recalculer » tout en conservant ses
  /// repères.
  static SavedRouteSnapshot decode(String json) => Diag.sync(
    'RouteSnapshotCodec.decode',
    () {
      final Object? decoded;
      try {
        decoded = jsonDecode(json);
      } on Object catch (error) {
        throw RouteSnapshotFormatException('JSON illisible : $error');
      }
      if (decoded is! Map<String, dynamic>) {
        throw const RouteSnapshotFormatException('Snapshot racine non objet.');
      }
      final version = decoded['version'];
      if (version is! int) {
        throw const RouteSnapshotFormatException('Version de snapshot absente ou invalide.');
      }
      if (version != SavedRouteSnapshot.currentVersion) {
        throw RouteSnapshotFormatException('Version de snapshot non prise en charge : $version.');
      }
      final computedAtMillis = decoded['computedAtMillis'];
      if (computedAtMillis is! int || computedAtMillis <= 0) {
        throw const RouteSnapshotFormatException('Date de calcul absente ou invalide.');
      }
      final engine = decoded['engine'];
      if (engine is! String || engine.isEmpty) {
        throw const RouteSnapshotFormatException('Moteur absent ou invalide.');
      }
      final segmentsJson = decoded['segments'];
      if (segmentsJson is! List) {
        throw const RouteSnapshotFormatException('Segments absents ou invalides.');
      }
      final snapshot = SavedRouteSnapshot(
        version: version,
        computedAt: DateTime.fromMillisecondsSinceEpoch(computedAtMillis),
        engineName: engine,
        packFileName: _optionalString(decoded['packFileName'], 'packFileName'),
        packSha256: _optionalString(decoded['packSha256'], 'packSha256'),
        segments: [for (final entry in segmentsJson) _decodeSegment(entry)],
      );
      _validate(snapshot);
      return snapshot;
    },
    params: 'bytes=${json.length}',
    result: (snapshot) => 'segments=${snapshot.segments.length}',
  );

  static String? _optionalString(Object? value, String field) {
    if (value == null) return null;
    if (value is String) return value;
    throw RouteSnapshotFormatException('Champ $field invalide.');
  }

  static SavedRouteSegment _decodeSegment(Object? entry) {
    if (entry is! Map<String, dynamic>) {
      throw const RouteSnapshotFormatException('Segment non objet.');
    }
    final startMarkerId = entry['startMarkerId'];
    final endMarkerId = entry['endMarkerId'];
    final startNumber = entry['startNumber'];
    final endNumber = entry['endNumber'];
    if (startMarkerId is! String || startMarkerId.isEmpty || endMarkerId is! String || endMarkerId.isEmpty) {
      throw const RouteSnapshotFormatException('Identité de segment invalide.');
    }
    if (startNumber is! int || startNumber <= 0 || endNumber is! int || endNumber <= 0) {
      throw const RouteSnapshotFormatException('Numéros de repères invalides.');
    }
    final geometryJson = entry['geometry'];
    if (geometryJson is! List) {
      throw const RouteSnapshotFormatException('Géométrie de segment absente ou invalide.');
    }
    final geometry = <ComputedRoutePoint>[
      for (final point in geometryJson) _decodePoint(point),
    ];
    return SavedRouteSegment(
      identity: TracedSegmentIdentity(
        startMarkerId: startMarkerId,
        endMarkerId: endMarkerId,
        startNumber: startNumber,
        endNumber: endNumber,
      ),
      preference: _requiredDouble(entry['preference'], 'preference'),
      route: ComputedRoute(
        geometry: geometry,
        distanceKm: _requiredDouble(entry['distanceKm'], 'distanceKm'),
        durationSeconds: _requiredDouble(entry['durationSeconds'], 'durationSeconds'),
        startSnapDistanceMeters: _requiredDouble(entry['startSnapMeters'], 'startSnapMeters'),
        endSnapDistanceMeters: _requiredDouble(entry['endSnapMeters'], 'endSnapMeters'),
      ),
    );
  }

  static ComputedRoutePoint _decodePoint(Object? point) {
    if (point is! List || point.length != 2) {
      throw const RouteSnapshotFormatException('Point de géométrie invalide.');
    }
    return ComputedRoutePoint(
      latitude: _requiredDouble(point[0], 'latitude'),
      longitude: _requiredDouble(point[1], 'longitude'),
    );
  }

  static double _requiredDouble(Object? value, String field) {
    if (value is num) return value.toDouble();
    throw RouteSnapshotFormatException('Champ $field absent ou non numérique.');
  }

  /// Rejette toute structure incohérente ou valeur hors domaine, à
  /// l'écriture comme à la lecture : boucle dirigée non fermée, segment
  /// trop court, valeurs non finies ou hors bornes.
  static void _validate(SavedRouteSnapshot snapshot) {
    if (snapshot.version != SavedRouteSnapshot.currentVersion) {
      throw RouteSnapshotFormatException('Version de snapshot non écrivable : ${snapshot.version}.');
    }
    if (snapshot.engineName.isEmpty) {
      throw const RouteSnapshotFormatException('Moteur vide.');
    }
    final segments = snapshot.segments;
    if (segments.length < 2) {
      throw const RouteSnapshotFormatException('Une boucle complète exige au moins 2 segments.');
    }
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final identity = segment.identity;
      if (identity.startMarkerId.isEmpty || identity.endMarkerId.isEmpty) {
        throw const RouteSnapshotFormatException('Identité de segment vide.');
      }
      if (identity.startNumber <= 0 || identity.endNumber <= 0) {
        throw const RouteSnapshotFormatException('Numéros de repères invalides.');
      }
      // La chaîne dirigée doit refermer la boucle : la fin de chaque
      // segment est le début du suivant, retour N→1 compris.
      if (identity.endMarkerId != segments[(i + 1) % segments.length].identity.startMarkerId) {
        throw const RouteSnapshotFormatException('Segments non enchaînés en boucle dirigée.');
      }
      _require(segment.preference.isFinite && segment.preference >= 0 && segment.preference <= 100,
          'Préférence hors bornes [0, 100].');
      _require(segment.route.distanceKm.isFinite && segment.route.distanceKm >= 0,
          'Distance moteur invalide.');
      _require(segment.route.durationSeconds.isFinite && segment.route.durationSeconds >= 0,
          'Durée moteur invalide.');
      _require(
          segment.route.startSnapDistanceMeters.isFinite &&
              segment.route.startSnapDistanceMeters >= 0 &&
              segment.route.endSnapDistanceMeters.isFinite &&
              segment.route.endSnapDistanceMeters >= 0,
          'Distance d\u2019accrochage invalide.');
      if (segment.route.geometry.length < 2) {
        throw const RouteSnapshotFormatException('Géométrie de segment dégénérée.');
      }
      for (final point in segment.route.geometry) {
        _require(
            point.latitude.isFinite && point.latitude >= -90 && point.latitude <= 90,
            'Latitude hors bornes : ${point.latitude}.');
        _require(
            point.longitude.isFinite && point.longitude >= -180 && point.longitude <= 180,
            'Longitude hors bornes : ${point.longitude}.');
      }
    }
  }

  static void _require(bool condition, String message) {
    if (!condition) throw RouteSnapshotFormatException(message);
  }
}
