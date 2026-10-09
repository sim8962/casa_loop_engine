import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'package:casa_loop_engine/controllers/route_editor_controller.dart';
import 'package:casa_loop_engine/services/repositories/marker_repository.dart';
import 'package:casa_loop_engine/services/repositories/route_draft_repository.dart';
import 'package:casa_loop_engine/services/repositories/route_preference_repository.dart';
import 'package:casa_loop_engine/views/selected_markers/controllers/selected_markers_controller.dart';

import 'fake_repositories.dart';

/// Environnement de test isolé pour [RouteEditorController] et
/// [SelectedMarkersController] : GetStorage pointé sur un répertoire
/// temporaire (jamais le vrai stockage de l'appareil), repositories en
/// mémoire (jamais ObjectBox), aucune dépendance à la carte.
///
/// Chaque appel attend la fin de l'initialisation asynchrone du
/// controller avant de retourner, pour que les tests n'aient pas à gérer
/// cette latence.
class RouteEditorTestEnvironment {
  RouteEditorTestEnvironment._(
    this.tempDir,
    this._storageContainerName,
    this._markerRepository,
    this._routePreferenceRepository,
    this.draftRepository,
    this.editor,
    this.selectedMarkers,
  );

  final Directory tempDir;
  final String _storageContainerName;
  final MarkerRepository _markerRepository;
  final RoutePreferenceRepository _routePreferenceRepository;
  final RouteDraftRepository draftRepository;

  /// Repository de repères en mémoire : exposé pour injecter des erreurs
  /// de persistance de l'état de travail dans les tests de rollback.
  MarkerRepository get markerRepository => _markerRepository;
  final RouteEditorController editor;
  final SelectedMarkersController selectedMarkers;

  /// Conteneur GetStorage isolé utilisé par cet environnement : chaque
  /// environnement a un nom de conteneur unique, car la bibliothèque met
  /// en cache une instance par nom indépendamment du chemin fourni.
  GetStorage get storage => GetStorage(_storageContainerName);

  /// Nom du conteneur, également préfixe du fichier `<nom>.gs` sur disque.
  String get storageContainerName => _storageContainerName;

  static Future<RouteEditorTestEnvironment> start({RouteDraftRepository? draftRepository}) async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final tempDir = await Directory.systemTemp.createTemp('casa_loop_test_');
    // `GetStorage` interroge toujours `path_provider` avant d'utiliser le
    // chemin explicite fourni ci-dessous ; sous le binding de test, aucun
    // plugin natif n'est enregistré pour répondre à cet appel. On simule
    // la réponse pour ne jamais dépendre du vrai stockage de l'appareil.
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') return tempDir.path;
        return null;
      },
    );
    // Conteneur GetStorage unique par environnement : la bibliothèque met
    // en cache une instance par nom de conteneur (indépendamment du
    // chemin), donc un nom distinct isole chaque test sur son répertoire
    // temporaire — aucune lecture/écriture ne touche le stockage réel de
    // l'appareil ni celui d'un autre test.
    final containerName = 'GetStorage_test_${_environmentCounter++}';
    final storage = GetStorage(containerName, tempDir.path);
    await storage.initStorage;
    await storage.erase();

    await Get.deleteAll(force: true);
    final markerRepo = FakeMarkerRepository();
    final routePrefRepo = FakeRoutePreferenceRepository();
    final repo = draftRepository ?? InMemoryRouteDraftRepository();
    Get.put<MarkerRepository>(markerRepo, permanent: true);
    Get.put<RoutePreferenceRepository>(routePrefRepo, permanent: true);
    Get.put<RouteDraftRepository>(repo, permanent: true);
    final editor = Get.put<RouteEditorController>(
      RouteEditorController(markerRepo, routePrefRepo, storageContainerName: containerName),
      permanent: true,
    );
    final selectedMarkers = Get.put<SelectedMarkersController>(
      SelectedMarkersController(editor),
      permanent: true,
    );

    while (editor.isInitializing.value) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    return RouteEditorTestEnvironment._(
      tempDir,
      containerName,
      markerRepo,
      routePrefRepo,
      repo,
      editor,
      selectedMarkers,
    );
  }

  static int _environmentCounter = 0;

  /// Simule un redémarrage de l'application : les controllers sont
  /// supprimés puis recréés, les repositories conservent leurs données et
  /// le conteneur GetStorage sur le répertoire temporaire n'est pas effacé.
  /// Le retour contient les nouvelles instances des controllers.
  Future<RouteEditorTestEnvironment> restart() async {
    await Get.deleteAll(force: true);
    Get.put<MarkerRepository>(_markerRepository, permanent: true);
    Get.put<RoutePreferenceRepository>(_routePreferenceRepository, permanent: true);
    Get.put<RouteDraftRepository>(draftRepository, permanent: true);
    final editor = Get.put<RouteEditorController>(
      RouteEditorController(
        _markerRepository,
        _routePreferenceRepository,
        storageContainerName: _storageContainerName,
      ),
      permanent: true,
    );
    final selectedMarkers = Get.put<SelectedMarkersController>(
      SelectedMarkersController(editor),
      permanent: true,
    );
    while (editor.isInitializing.value) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    return RouteEditorTestEnvironment._(
      tempDir,
      _storageContainerName,
      _markerRepository,
      _routePreferenceRepository,
      draftRepository,
      editor,
      selectedMarkers,
    );
  }

  Future<void> dispose() async {
    await Get.deleteAll(force: true);
    await GetStorage(_storageContainerName).erase();
    await tempDir.delete(recursive: true);
  }
}
