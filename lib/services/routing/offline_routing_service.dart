import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'package:casa_loop_engine/helpers/constants/app_config.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';
import 'package:casa_loop_engine/models/computed_route.dart';
import 'package:casa_loop_engine/services/routing/route_preference_costing.dart';
import 'package:casa_loop_engine/services/routing/valhalla_route_engine.dart';

/// Catégorie fonctionnelle d'une [OfflineRoutingException] : la couche
/// de préservation la traduit en message utilisateur sans reconnaître
/// l'erreur par recherche de mots dans [OfflineRoutingException.message]
/// — le texte complet (chemins, empreintes) reste destiné aux journaux.
enum OfflineRoutingErrorKind {
  /// Données du pack régional absentes : archive ou gabarit introuvables.
  packMissing,

  /// Données du pack présentes mais inexploitables : vide, empreinte
  /// différente de celle attendue ou gabarit invalide/illisible.
  packInvalid,

  /// Lecture ou écriture des fichiers du pack impossible (copie
  /// interrompue, empreinte illisible…).
  packIo,

  /// Échec ou incohérence du calcul d'un tronçon lui-même (accrochage
  /// trop éloigné, réponse moteur…), distinct des problèmes de pack.
  computation,
}

/// Erreur fonctionnelle du service de calcul hors ligne (graphe absent,
/// configuration impossible, réponse incohérente…). Distincte des
/// [PlatformException] remontées par le canal natif.
class OfflineRoutingException implements Exception {
  const OfflineRoutingException(this.message, {this.kind = OfflineRoutingErrorKind.computation});

  final String message;

  /// Catégorie structurée de l'erreur — voir [OfflineRoutingErrorKind].
  final OfflineRoutingErrorKind kind;

  @override
  String toString() => 'OfflineRoutingException: $message';
}

/// Orchestration du moteur Valhalla embarqué côté Dart : installation des
/// chemins de données dans le stockage applicatif, écriture de la
/// configuration locale, configuration unique du moteur natif, puis calcul
/// A→B avec contrôle de cohérence de la réponse.
///
/// Le graphe est attendu dans `<Documents>/routing/<nom>`. Zone de dépôt
/// reconnue : `<Documents>/<nom>` pour l'archive et le gabarit — fichiers
/// installés en interne par copie vérifiée — ou placement direct dans
/// `routing/` par `simctl`/`devicectl`. Aucun chemin du Mac de
/// développement n'est utilisé à l'exécution.
class OfflineRoutingService {
  OfflineRoutingService();

  final ValhallaRouteEngine _engine = const ValhallaRouteEngine();

  bool _configured = false;

  /// Tentative de configuration en vol : mutualise les appels concurrents
  /// pour que le moteur natif ne soit jamais configuré deux fois, et est
  /// libérée après l'échec pour qu'une nouvelle tentative reste possible.
  Future<void>? _configuring;

  /// Calcule le segment moto [startLat,startLon] → [endLat,endLon] et
  /// retourne géométrie et mesures moteur. Configure le moteur à la
  /// première utilisation. Lève [OfflineRoutingException] pour toute cause
  /// fonctionnelle (graphe manquant, accrochage trop éloigné…).
  ///
  /// [preference] est la préférence de ce segment sur le curseur
  /// 0 (Rapide) → 100 (Trail) : elle est convertie en
  /// `costing_options.motorcycle` par [RoutePreferenceCosting.optionsFor]
  /// et transmise uniquement pour cet appel — jamais réutilisée sur le
  /// segment suivant. Sans préférence explicite, aucune option n'est
  /// envoyée et le moteur applique le comportement motorcycle standard
  /// (utilisé par les scripts de référence).
  Future<ComputedRoute> computeFirstSegment({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
    double? preference,
  }) => Diag.future('OfflineRoutingService.computeFirstSegment', () async {
    await _ensureConfigured();
    final response = await _engine.routeMotorcycle([
      (startLat, startLon),
      (endLat, endLon),
    ], costingOptions: preference == null ? null : RoutePreferenceCosting.optionsFor(preference));
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
  }, params: 'a=($startLat,$startLon) b=($endLat,$endLon) pref=$preference');

  /// Calcule le segment A→B et retourne la route principale suivie des
  /// variantes produites par le moteur (`alternates`, plafonné à
  /// `service_limits.max_alternates` de la configuration embarquée = 2).
  /// Même requête, même préférence : les variantes respectent le même
  /// couple dirigé et le même costing — aucune restriction n'est
  /// modifiée. Une seule requête native par appel.
  ///
  /// Une variante dont l'accrochage dépasse la tolérance est ignorée
  /// (inutilisable pour les repères demandés) ; l'accrochage de la route
  /// principale est contrôlé comme dans [computeFirstSegment] et lève
  /// [OfflineRoutingException] au-delà de la tolérance.
  Future<List<ComputedRoute>> computeSegmentVariants({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
    double? preference,
    int maxAlternates = 2,
  }) => Diag.future('OfflineRoutingService.computeSegmentVariants', () async {
    await _ensureConfigured();
    final response = await _engine.routeMotorcycle(
      [(startLat, startLon), (endLat, endLon)],
      costingOptions: preference == null ? null : RoutePreferenceCosting.optionsFor(preference),
      alternates: maxAlternates,
    );
    final routes = ComputedRoute.listFromValhallaJson(
      response,
      requestedStartLat: startLat,
      requestedStartLon: startLon,
      requestedEndLat: endLat,
      requestedEndLon: endLon,
    );
    final main = routes.first;
    if (main.startSnapDistanceMeters > ComputedRoute.maxSnapDistanceMeters ||
        main.endSnapDistanceMeters > ComputedRoute.maxSnapDistanceMeters) {
      throw OfflineRoutingException(
        'Repère trop éloigné du réseau : '
        'départ ${main.startSnapDistanceMeters.toStringAsFixed(0)} m, '
        'arrivée ${main.endSnapDistanceMeters.toStringAsFixed(0)} m.',
      );
    }
    return [
      main,
      for (final variant in routes.skip(1))
        if (variant.startSnapDistanceMeters <= ComputedRoute.maxSnapDistanceMeters &&
            variant.endSnapDistanceMeters <= ComputedRoute.maxSnapDistanceMeters)
          variant,
    ];
  }, params: 'a=($startLat,$startLon) b=($endLat,$endLon) pref=$preference alt=$maxAlternates');

  /// Écrit la configuration locale et configure le moteur une seule fois.
  /// Les appels concurrents partagent la même tentative ; après un échec,
  /// l'état de tentative est libéré et l'appel suivant recommence tout.
  Future<void> _ensureConfigured() => Diag.future('OfflineRoutingService._ensureConfigured', () async {
    if (_configured) return;
    final attempt = _configuring ??= _configure();
    try {
      await attempt;
    } finally {
      if (identical(_configuring, attempt)) _configuring = null;
    }
  });

  /// Corps réel de la configuration : présence et validité des fichiers
  /// du pack (installation depuis la zone de dépôt si nécessaire),
  /// écriture du JSON local, puis configuration native. Jamais appelé en
  /// parallèle (voir [_ensureConfigured]).
  Future<void> _configure() async {
    final documents = await getApplicationDocumentsDirectory();
    final routingDir = Directory('${documents.path}/routing');
    await routingDir.create(recursive: true);
    await _ensureGraphFile(routingDir, documents);
    await _ensureTemplateFile(routingDir, documents);
    await Directory('${routingDir.path}/tiles').create(recursive: true);
    final configFile = File('${routingDir.path}/valhalla.json');
    final templateFile = File('${routingDir.path}/${AppConfig.routingConfigTemplateFileName}');
    await configFile.writeAsString(await _configFor(routingDir.path, templateFile));
    await _engine.configure(configFile.path);
    _configured = true;
  }

  /// Garantit une archive de graphe valide dans `<Documents>/routing/` :
  /// une copie installée dont l'empreinte est conforme est conservée
  /// telle quelle ; une copie absente, vide ou différente est réparée
  /// depuis `<Documents>/<nom>` (zone de dépôt), par copie en flux via
  /// `.partial` dont l'empreinte est vérifiée avant renommage. Un fichier
  /// installé valide n'est jamais remplacé, même si la zone de dépôt en
  /// contient un autre.
  Future<void> _ensureGraphFile(Directory routingDir, Directory documents) async {
    final graphFile = File('${routingDir.path}/${AppConfig.routingGraphFileName}');
    String? installedSha;
    final installedExists = await graphFile.exists();
    if (installedExists && await graphFile.length() > 0) {
      installedSha = await _sha256Of(graphFile);
      if (installedSha == AppConfig.routingGraphSha256) return;
    }
    final source = File('${documents.path}/${AppConfig.routingGraphFileName}');
    if (await source.exists()) {
      await _installGraphFrom(source, graphFile);
      return;
    }
    if (!installedExists) {
      throw OfflineRoutingException(
        'Graphe absent : ${graphFile.path}. '
        'Déposez ${AppConfig.routingGraphFileName} dans le dossier Documents de l’application.',
        kind: OfflineRoutingErrorKind.packMissing,
      );
    }
    if (installedSha == null) {
      throw OfflineRoutingException(
        'Graphe installé vide : ${graphFile.path}. '
        'Déposez ${AppConfig.routingGraphFileName} dans le dossier Documents de l’application.',
        kind: OfflineRoutingErrorKind.packInvalid,
      );
    }
    throw OfflineRoutingException(
      'Empreinte SHA-256 du graphe différente de celle attendue '
      '(attendue ${AppConfig.routingGraphSha256}, lue $installedSha) : '
      'le pack installé ne correspond pas au pack régional de référence.',
      kind: OfflineRoutingErrorKind.packInvalid,
    );
  }

  /// Installe l'archive déposée à son emplacement d'usage : copie en flux
  /// vers `.partial`, contrôle de taille copiée et d'empreinte avant le
  /// renommage — une interruption ne laisse jamais d'archive tronquée à
  /// la place du graphe.
  Future<void> _installGraphFrom(File source, File destination) async {
    if (await source.length() == 0) {
      throw OfflineRoutingException(
        'Graphe fourni vide : ${source.path}',
        kind: OfflineRoutingErrorKind.packInvalid,
      );
    }
    final partial = File('${destination.path}.partial');
    try {
      if (await partial.exists()) {
        await partial.delete();
      }
      await source.openRead().pipe(partial.openWrite());
      final copiedLength = await partial.length();
      if (copiedLength != await source.length()) {
        throw OfflineRoutingException(
          'Copie du graphe incomplète ($copiedLength octets) : ${partial.path}',
          kind: OfflineRoutingErrorKind.packIo,
        );
      }
      final copiedSha = await _sha256Of(partial);
      if (copiedSha != AppConfig.routingGraphSha256) {
        throw OfflineRoutingException(
          'Le graphe déposé ne correspond pas au pack régional attendu '
          '(SHA-256 attendu ${AppConfig.routingGraphSha256}, lu $copiedSha) : ${source.path}',
          kind: OfflineRoutingErrorKind.packInvalid,
        );
      }
      await partial.rename(destination.path);
    } catch (_) {
      if (await partial.exists()) {
        await partial.delete();
      }
      rethrow;
    }
  }

  /// Empreinte SHA-256 d'un fichier, lue en flux — jamais chargé en
  /// entier en mémoire. Une lecture impossible est rapportée en
  /// [OfflineRoutingException] explicite.
  Future<String> _sha256Of(File file) async {
    try {
      return (await sha256.bind(file.openRead()).first).toString();
    } catch (error) {
      throw OfflineRoutingException(
        'Empreinte du graphe illisible : ${file.path} — $error',
        kind: OfflineRoutingErrorKind.packIo,
      );
    }
  }

  /// Garantit un gabarit de configuration exploitable dans
  /// `<Documents>/routing/` : un gabarit installé et valide est conservé ;
  /// un gabarit absent ou invalide est remplacé par celui déposé dans la
  /// zone de dépôt, après vérification qu'il est lui-même valide.
  Future<void> _ensureTemplateFile(Directory routingDir, Directory documents) async {
    final templateFile = File('${routingDir.path}/${AppConfig.routingConfigTemplateFileName}');
    final installedExists = await templateFile.exists();
    if (installedExists && await _isValidTemplate(templateFile)) return;
    final source = File('${documents.path}/${AppConfig.routingConfigTemplateFileName}');
    if (await source.exists()) {
      if (!await _isValidTemplate(source)) {
        throw OfflineRoutingException(
          'Gabarit de configuration fourni invalide : ${source.path}',
          kind: OfflineRoutingErrorKind.packInvalid,
        );
      }
      final partial = File('${templateFile.path}.partial');
      try {
        if (await partial.exists()) {
          await partial.delete();
        }
        await source.copy(partial.path);
        await partial.rename(templateFile.path);
      } catch (_) {
        if (await partial.exists()) {
          await partial.delete();
        }
        rethrow;
      }
      return;
    }
    if (installedExists) {
      throw OfflineRoutingException(
        'Gabarit de configuration invalide : ${templateFile.path}',
        kind: OfflineRoutingErrorKind.packInvalid,
      );
    }
    throw OfflineRoutingException(
      'Gabarit de configuration absent : ${templateFile.path}. '
      'Déposez ${AppConfig.routingConfigTemplateFileName} dans le dossier Documents de l’application.',
      kind: OfflineRoutingErrorKind.packMissing,
    );
  }

  /// Un gabarit exploitable est un JSON objet portant une section
  /// `mjolnir` objet — même critère que [_configFor] à l'usage.
  static Future<bool> _isValidTemplate(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> && decoded['mjolnir'] is Map<String, dynamic>;
    } catch (_) {
      return false;
    }
  }

  /// Construit la configuration moteur depuis le gabarit produit par
  /// `valhalla_build_config` (installé avec l'archive) : seuls les chemins
  /// sont réécrits vers le stockage applicatif — aucun chemin `/Users/...`
  /// ou `/data/...` ne subsiste — et le cache est dimensionné pour le
  /// graphe régional (~86 Mo). Le gabarit garantit que toutes les sections
  /// exigées par le worker (service_limits, meili…) sont présentes.
  static Future<String> _configFor(String routingDir, File templateFile) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(await templateFile.readAsString());
    } catch (error) {
      throw OfflineRoutingException(
        'Gabarit de configuration illisible : ${templateFile.path} — $error',
        kind: OfflineRoutingErrorKind.packInvalid,
      );
    }
    if (decoded is! Map<String, dynamic> || decoded['mjolnir'] is! Map<String, dynamic>) {
      throw OfflineRoutingException(
        'Gabarit de configuration invalide : ${templateFile.path}',
        kind: OfflineRoutingErrorKind.packInvalid,
      );
    }
    final mjolnir = decoded['mjolnir'] as Map<String, dynamic>;
    final absentData = '$routingDir/absent';
    mjolnir['tile_dir'] = '$routingDir/tiles';
    mjolnir['tile_extract'] = '$routingDir/${AppConfig.routingGraphFileName}';
    mjolnir['max_cache_size'] = 134217728;
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
