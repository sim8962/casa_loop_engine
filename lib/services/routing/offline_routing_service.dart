import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:casa_loop_engine/helpers/constants/app_config.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';
import 'package:casa_loop_engine/models/computed_route.dart';
import 'package:casa_loop_engine/services/routing/valhalla_route_engine.dart';

/// Erreur fonctionnelle du service de calcul hors ligne (graphe absent,
/// configuration impossible, réponse incohérente…). Distincte des
/// [PlatformException] remontées par le canal natif.
class OfflineRoutingException implements Exception {
  const OfflineRoutingException(this.message);

  final String message;

  @override
  String toString() => 'OfflineRoutingException: $message';
}

/// Orchestration du moteur Valhalla embarqué côté Dart : installation des
/// chemins de données dans le stockage applicatif, écriture de la
/// configuration locale, configuration unique du moteur natif, puis calcul
/// A→B avec contrôle de cohérence de la réponse.
///
/// Le graphe est attendu dans `<Documents>/routing/<nom>` — placé là par
/// `simctl` (simulateur) ou tout moyen d'installation équivalent. Aucun
/// chemin du Mac de développement n'est utilisé à l'exécution.
class OfflineRoutingService {
  OfflineRoutingService({ValhallaRouteEngine? engine, Future<Directory> Function()? documentsDirectory})
    : _engine = engine ?? const ValhallaRouteEngine(),
      _documentsDirectory = documentsDirectory ?? getApplicationDocumentsDirectory;

  final ValhallaRouteEngine _engine;
  final Future<Directory> Function() _documentsDirectory;

  bool _configured = false;

  /// `true` tant que [computeFirstSegment] n'a pas établi la configuration
  /// du moteur ; exposé pour le diagnostic.
  bool get isConfigured => _configured;

  /// Calcule le segment moto [startLat,startLon] → [endLat,endLon] et
  /// retourne géométrie et mesures moteur. Configure le moteur à la
  /// première utilisation. Lève [OfflineRoutingException] pour toute cause
  /// fonctionnelle (graphe manquant, accrochage trop éloigné…).
  Future<ComputedRoute> computeFirstSegment({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
  }) => Diag.future('OfflineRoutingService.computeFirstSegment', () async {
    await _ensureConfigured();
    final response = await _engine.routeMotorcycle([(startLat, startLon), (endLat, endLon)]);
    final route = ComputedRoute.fromValhallaJson(
      response,
      requestedStartLat: startLat,
      requestedStartLon: startLon,
      requestedEndLat: endLat,
      requestedEndLon: endLon,
    );
    if (route.startSnapDistanceMeters > ComputedRoute.maxSnapDistanceMeters ||
        route.endSnapDistanceMeters > ComputedRoute.maxSnapDistanceMeters) {
      throw OfflineRoutingException(
        'Repère trop éloigné du réseau : '
        'départ ${route.startSnapDistanceMeters.toStringAsFixed(0)} m, '
        'arrivée ${route.endSnapDistanceMeters.toStringAsFixed(0)} m.',
      );
    }
    return route;
  }, params: 'a=($startLat,$startLon) b=($endLat,$endLon)');

  /// Écrit la configuration locale et configure le moteur une seule fois.
  Future<void> _ensureConfigured() => Diag.future('OfflineRoutingService._ensureConfigured', () async {
    if (_configured) return;
    final documents = await _documentsDirectory();
    final routingDir = Directory('${documents.path}/routing');
    final graphFile = File('${routingDir.path}/${AppConfig.routingGraphFileName}');
    if (!await graphFile.exists()) {
      throw OfflineRoutingException(
        'Graphe absent : ${graphFile.path}. '
        'Installez ${AppConfig.routingGraphFileName} dans le stockage de l’application.',
      );
    }
    final templateFile = File('${routingDir.path}/${AppConfig.routingConfigTemplateFileName}');
    if (!await templateFile.exists()) {
      throw OfflineRoutingException(
        'Gabarit de configuration absent : ${templateFile.path}. '
        'Installez ${AppConfig.routingConfigTemplateFileName} avec le graphe.',
      );
    }
    await routingDir.create(recursive: true);
    await Directory('${routingDir.path}/tiles').create(recursive: true);
    final configFile = File('${routingDir.path}/valhalla.json');
    await configFile.writeAsString(await _configFor(routingDir.path, templateFile));
    await _engine.configure(configFile.path);
    _configured = true;
  });

  /// Construit la configuration moteur depuis le gabarit produit par
  /// `valhalla_build_config` (installé avec l'archive) : seuls les chemins
  /// sont réécrits vers le stockage applicatif — aucun chemin `/Users/...`
  /// ou `/data/...` ne subsiste — et le cache est dimensionné pour le graphe
  /// de preuve (~28 Mo). Le gabarit garantit que toutes les sections
  /// exigées par le worker (service_limits, meili…) sont présentes.
  static Future<String> _configFor(String routingDir, File templateFile) async {
    final decoded = jsonDecode(await templateFile.readAsString());
    if (decoded is! Map<String, dynamic> || decoded['mjolnir'] is! Map<String, dynamic>) {
      throw OfflineRoutingException('Gabarit de configuration invalide : ${templateFile.path}');
    }
    final mjolnir = decoded['mjolnir'] as Map<String, dynamic>;
    final absentData = '$routingDir/absent';
    mjolnir['tile_dir'] = '$routingDir/tiles';
    mjolnir['tile_extract'] = '$routingDir/${AppConfig.routingGraphFileName}';
    mjolnir['max_cache_size'] = 67108864;
    mjolnir['use_lru_mem_cache'] = false;
    mjolnir['max_concurrent_reader_users'] = 1;
    // Données non fournies par cette preuve : le moteur les ignore quand les
    // fichiers n'existent pas.
    mjolnir['admin'] = '$absentData/admin.sqlite';
    mjolnir['landmarks'] = '$absentData/landmarks.sqlite';
    mjolnir['timezone'] = '$absentData/tz_world.sqlite';
    mjolnir['traffic_extract'] = '$absentData/traffic.tar';
    mjolnir['transit_dir'] = '$absentData/transit';
    mjolnir['transit_feeds_dir'] = '$absentData/transit_feeds';
    final additionalData = decoded['additional_data'];
    if (additionalData is Map<String, dynamic>) {
      additionalData['elevation'] = '$absentData/elevation/';
    }
    final logging = decoded['logging'];
    if (logging is Map<String, dynamic>) {
      logging['type'] = 'std_out';
      logging['color'] = false;
    }
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }
}
