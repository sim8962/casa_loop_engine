import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';
import 'package:casa_loop_engine/models/computed_route.dart';

/// Repère utilisateur à inclure dans le GPX comme point de passage
/// complémentaire (`<wpt>`), avec le nom affiché dans l'application.
class GpxWaypoint {
  const GpxWaypoint({required this.name, required this.latitude, required this.longitude});

  final String name;
  final double latitude;
  final double longitude;
}

/// Erreur contrôlée de production d'un export GPX : géométrie absente,
/// coordonnée hors bornes, donnée non finie. Levée avant toute écriture
/// de fichier — jamais de fichier partiel ni de faux succès.
class GpxExportException implements Exception {
  const GpxExportException(this.message);

  final String message;

  @override
  String toString() => 'GpxExportException: $message';
}

/// Issue utilisateur d'un export : partage effectué, annulation explicite
/// de la feuille de partage, ou échec (création du fichier ou partage).
enum GpxExportStatus { shared, cancelled, failed }

/// Bilan d'un export : [status] distingue l'annulation d'un échec —
/// aucun message de réussite ne doit être affiché pour `cancelled` ou
/// `failed`. [fileName] est le nom du fichier écrit (même si le partage
/// a été annulé) ; [errorMessage] décrit l'échec.
class GpxExportResult {
  const GpxExportResult({required this.status, this.fileName, this.errorMessage});

  final GpxExportStatus status;
  final String? fileName;
  final String? errorMessage;
}

/// Document GPX produit par [GpxExportService._buildGpx] : le XML complet
/// et le nombre de `<trkseg>` écrits — supérieur à 1 lorsque des
/// discontinuités de jonction ont été préservées.
class _GpxDocument {
  const _GpxDocument({required this.xml, required this.trackSegmentCount});

  final String xml;
  final int trackSegmentCount;
}

/// Export GPX 1.1 d'une boucle calculée : génération XML pure (aucune
/// dépendance à l'interface ni au partage), écriture dans un dossier
/// temporaire dédié et borné, puis ouverture de la feuille de partage
/// iOS. Hors ligne de bout en bout : aucun calcul moteur, aucune
/// modification du trajet sauvegardé.
///
/// Règles de jonction (voir ROUTE_SAVE_GPX.md) : seuls les doublons
/// consécutifs strictement identiques sont retirés ; deux géométries qui
/// ne se rejoignent pas sont écrites en `<trkseg>` distincts — la
/// discontinuité est préservée et signalée, jamais masquée par une
/// liaison droite inventée.
class GpxExportService {
  /// Nombre maximal de fichiers GPX conservés dans le sous-dossier
  /// d'export du répertoire temporaire : les plus anciens sont supprimés
  /// au début d'un nouvel export — jamais le fichier en cours de
  /// partage, jamais rien hors de ce dossier propre à l'application.
  static const int _maxTempFiles = 10;
  static const String _tempSubdirectory = 'gpx_exports';
  static const String _fileExtension = '.gpx';

  /// Produit le document GPX 1.1 complet de [itinerary] (boucle entière,
  /// retour N→1 inclus) : métadonnées avec nom et emprise, repères
  /// [waypoints] complémentaires, trace routière réelle découpée en
  /// `<trkseg>` aux jonctions discontinues.
  ///
  /// Fonction pure : pas d'interface, pas de partage, pas d'effet de
  /// bord. Lève [GpxExportException] pour toute donnée invalide (aucun
  /// tracé, coordonnée hors bornes ou non finie) — un fichier
  /// partiellement valide n'est jamais produit.
  static _GpxDocument _buildGpx({
    required ComputedItinerary itinerary,
    required String routeName,
    List<GpxWaypoint> waypoints = const [],
  }) {
    if (itinerary.segments.isEmpty) {
      throw const GpxExportException('Aucun tracé à exporter.');
    }
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<gpx version="1.1" creator="CasaLoopEngine" '
        'xmlns="http://www.topografix.com/GPX/1/1" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:schemaLocation="http://www.topografix.com/GPX/1/1 '
        'http://www.topografix.com/GPX/1/1/gpx.xsd">',
      );

    // Assemble les points de la boucle : découpe en trkseg aux
    // discontinuités et collecte l'emprise en une seule passe.
    final trackSegments = _trackSegments(itinerary);
    var minLat = double.infinity;
    var maxLat = -double.infinity;
    var minLon = double.infinity;
    var maxLon = -double.infinity;
    for (final segment in trackSegments) {
      for (final point in segment) {
        if (point.latitude < minLat) minLat = point.latitude;
        if (point.latitude > maxLat) maxLat = point.latitude;
        if (point.longitude < minLon) minLon = point.longitude;
        if (point.longitude > maxLon) maxLon = point.longitude;
      }
    }
    if (!minLat.isFinite) {
      throw const GpxExportException('Géométrie vide : aucun point à exporter.');
    }

    buffer
      ..writeln('  <metadata>')
      ..writeln('    <name>${_escapeXml(routeName)}</name>')
      ..writeln(
        '    <desc>Boucle calculée — mesures moteur '
        '(durées hors pauses, estimées) : '
        '${itinerary.totalDistanceKm.toStringAsFixed(1)} km — '
        '${_formatDuration(itinerary.totalDurationSeconds)}'
        '${trackSegments.length > 1 ? ' — ${trackSegments.length} portions, jonctions discontinues préservées' : ''}</desc>',
      );
    final stamp = DateTime.now();
    buffer.writeln('    <time>${stamp.toUtc().toIso8601String()}</time>');
    buffer
      ..writeln(
        '    <bounds minlat="${_coord(minLat)}" minlon="${_coord(minLon)}" '
        'maxlat="${_coord(maxLat)}" maxlon="${_coord(maxLon)}"/>',
      )
      ..writeln('  </metadata>');

    for (final waypoint in waypoints) {
      _validatePoint(waypoint.latitude, waypoint.longitude);
      buffer
        ..writeln('  <wpt lat="${_coord(waypoint.latitude)}" lon="${_coord(waypoint.longitude)}">')
        ..writeln('    <name>${_escapeXml(waypoint.name)}</name>')
        ..writeln('  </wpt>');
    }

    buffer
      ..writeln('  <trk>')
      ..writeln('    <name>${_escapeXml(routeName)}</name>')
      ..writeln(
        '    <desc>${itinerary.segments.length} segments dirigés, retour inclus — mesures moteur</desc>',
      );
    for (final segment in trackSegments) {
      buffer.writeln('    <trkseg>');
      for (final point in segment) {
        buffer.writeln('      <trkpt lat="${_coord(point.latitude)}" lon="${_coord(point.longitude)}"/>');
      }
      buffer.writeln('    </trkseg>');
    }
    buffer
      ..writeln('  </trk>')
      ..write('</gpx>');
    return _GpxDocument(xml: buffer.toString(), trackSegmentCount: trackSegments.length);
  }

  /// Assemble les géométries des segments dirigés en `<trkseg>` :
  /// itère les segments dans l'ordre (retour compris), retire un point
  /// strictement identique au précédent émis (jonction exacte) et ouvre
  /// un nouveau trkseg lorsque la géométrie suivante ne rejoint pas la
  /// précédente — discontinuité préservée, aucune liaison droite
  /// inventée. Un doublon de fermeture (dernier point identique au
  /// premier émis) est retiré sans forcer la boucle.
  static List<List<ComputedRoutePoint>> _trackSegments(ComputedItinerary itinerary) {
    final trackSegments = <List<ComputedRoutePoint>>[];
    var current = <ComputedRoutePoint>[];
    trackSegments.add(current);
    // `true` au premier point non dédupliqué de chaque géométrie : la
    // discontinuité ne se juge qu'à la jonction entre segments, jamais
    // entre deux points d'une même géométrie.
    var firstPointOfGeometry = true;
    for (final segment in itinerary.segments) {
      for (final point in segment.route.geometry) {
        _validatePoint(point.latitude, point.longitude);
        if (current.isNotEmpty && _samePoint(current.last, point)) {
          // Doublon consécutif strictement identique (jonction exacte
          // ou répétition interne) : retiré — et la géométrie est bien
          // jointe à la précédente, aucun trkseg à ouvrir.
          firstPointOfGeometry = false;
          continue;
        }
        if (firstPointOfGeometry && current.isNotEmpty) {
          // La nouvelle géométrie ne rejoint pas la fin de la
          // précédente : nouveau trkseg — la discontinuité reste
          // visible, aucune liaison droite n'est inventée.
          current = <ComputedRoutePoint>[];
          trackSegments.add(current);
        }
        current.add(point);
        firstPointOfGeometry = false;
      }
      firstPointOfGeometry = true;
    }
    return trackSegments;
  }

  static bool _samePoint(ComputedRoutePoint a, ComputedRoutePoint b) =>
      a.latitude == b.latitude && a.longitude == b.longitude;

  static void _validatePoint(double latitude, double longitude) {
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw GpxExportException('Latitude invalide : $latitude.');
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw GpxExportException('Longitude invalide : $longitude.');
    }
  }

  /// Coordonnée avec 7 décimales fixes : préserve la précision des
  /// géométries polyline6 (6 décimales) et n'émet jamais de notation
  /// exponentielle, invalide pour `xsd:decimal`.
  static String _coord(double value) => value.toStringAsFixed(7);

  static String _escapeXml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _formatDuration(double seconds) {
    final totalMinutes = (seconds / 60).round();
    if (totalMinutes < 60) return '$totalMinutes min';
    return '${totalMinutes ~/ 60} h ${(totalMinutes % 60).toString().padLeft(2, '0')}';
  }

  /// Export complet : génération du XML, écriture dans
  /// `<temp>/gpx_exports/` puis partage iOS. Distingue toujours
  /// annulation et échec ; le trajet sauvegardé n'est jamais modifié.
  /// Le fichier écrit n'est supprimé ni avant ni pendant le partage ;
  /// seuls les anciens fichiers du dossier dédié sont élagués au
  /// démarrage (borne [_maxTempFiles]).
  Future<GpxExportResult> export({
    required ComputedItinerary itinerary,
    required String routeName,
    List<GpxWaypoint> waypoints = const [],
    Rect? shareOrigin,
  }) => Diag.future('GpxExportService.export', () async {
    final document = _buildGpx(itinerary: itinerary, routeName: routeName, waypoints: waypoints);
    if (document.trackSegmentCount > 1) {
      Diag.event(
        'GpxExportService.export.discontinuity',
        'trackSegments=${document.trackSegmentCount} — discontinuités préservées',
      );
    }
    final Directory tempDir;
    final File file;
    try {
      tempDir = await getTemporaryDirectory();
      final exportDir = Directory('${tempDir.path}/$_tempSubdirectory');
      await exportDir.create(recursive: true);
      await _pruneTempExports(exportDir);
      file = File('${exportDir.path}/${_fileName(routeName, DateTime.now())}');
      await file.writeAsString(document.xml, flush: true);
      // Chemin complet du fichier écrit — permet de le lire hors de
      // l'app (bac à sable du simulateur : Library/Caches/gpx_exports).
      debugPrint('GPX écrit : ${file.path}');
    } on Object catch (error, stack) {
      Diag.error('GpxExportService.export.write', error, stack);
      return GpxExportResult(status: GpxExportStatus.failed, errorMessage: 'écriture impossible : $error');
    }
    final GpxExportStatus status;
    try {
      status = await _shareWithSystem(file.path, shareOrigin: shareOrigin);
    } on Object catch (error, stack) {
      Diag.error('GpxExportService.export.share', error, stack);
      return GpxExportResult(
        status: GpxExportStatus.failed,
        fileName: file.uri.pathSegments.last,
        errorMessage: 'partage impossible : $error',
      );
    }
    return GpxExportResult(status: status, fileName: file.uri.pathSegments.last);
  }, params: 'route="$routeName" waypoints=${waypoints.length}');

  /// Supprime les plus anciens fichiers `.gpx` du dossier dédié pour
  /// rester sous [maxTempFiles] après l'écriture à venir. Un échec de
  /// suppression est tracé sans faire échouer l'export ; aucun fichier
  /// hors du dossier n'est touché.
  Future<void> _pruneTempExports(Directory exportDir) async {
    try {
      final files = <File>[];
      await for (final entity in exportDir.list()) {
        if (entity is File && entity.path.endsWith(_fileExtension)) files.add(entity);
      }
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      for (var i = _maxTempFiles - 1; i < files.length; i++) {
        try {
          await files[i].delete();
        } on Object catch (error) {
          Diag.error('GpxExportService.prune.file', error);
        }
      }
    } on Object catch (error) {
      Diag.error('GpxExportService.prune', error);
    }
  }

  /// Nom de fichier utilisable : lettres, chiffres, `_`, `-`, `.`
  /// conservés (accents compris) ; tout le reste replacé par `_` ; nom
  /// suffixé par un horodatage pour ne jamais écraser un fichier encore
  /// consommé par un partage précédent.
  static String _fileName(String routeName, DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${at.year}${two(at.month)}${two(at.day)}-${two(at.hour)}${two(at.minute)}${two(at.second)}';
    final sanitized = routeName
        .replaceAll(RegExp(r'[^\p{L}\p{N}._-]+', unicode: true), '_')
        .replaceAll(RegExp('_+'), '_')
        .replaceAll(RegExp(r'^[_.]+|[_.]+$'), '');
    final base = sanitized.isEmpty ? 'trajet' : sanitized;
    final trimmed = base.length > 80 ? base.substring(0, 80) : base;
    return '${trimmed}_$stamp$_fileExtension';
  }

  /// Partage système via `share_plus` : le fichier est partagé comme
  /// fichier `.gpx` (pas de copie textuelle) avec ancre iPad.
  static Future<GpxExportStatus> _shareWithSystem(String filePath, {Rect? shareOrigin}) async {
    final result = await SharePlus.instance.share(
      ShareParams(files: [XFile(filePath)], sharePositionOrigin: shareOrigin),
    );
    return switch (result.status) {
      ShareResultStatus.success => GpxExportStatus.shared,
      ShareResultStatus.dismissed => GpxExportStatus.cancelled,
      ShareResultStatus.unavailable => GpxExportStatus.failed,
    };
  }
}
