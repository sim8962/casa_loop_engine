import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'package:casa_loop_engine/controllers/route_editor_controller.dart';
import 'package:casa_loop_engine/models/computed_route.dart';
import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/models/route_draft_segment_preference.dart';
import 'package:casa_loop_engine/services/repositories/marker_repository.dart';
import 'package:casa_loop_engine/services/repositories/route_draft_repository.dart';
import 'package:casa_loop_engine/services/repositories/route_preference_repository.dart';
import 'package:casa_loop_engine/services/routing/offline_routing_service.dart';

import '../test_helpers/fake_repositories.dart';
import '../test_helpers/test_harness.dart';

const _markerA = MapMarkerItem(id: 'm1', name: 'Départ', type: 'ville', latitude: 1, longitude: 1);
const _markerB = MapMarkerItem(id: 'm2', name: 'Arrivée', type: 'ville', latitude: 2, longitude: 2);
const _markerC = MapMarkerItem(id: 'm3', name: 'Étape', type: 'ville', latitude: 3, longitude: 3);

/// Service de calcul simulé : compte les appels pour vérifier qu'un
/// changement de couleur ne rappelle jamais le moteur.
class _CountingRoutingService extends OfflineRoutingService {
  _CountingRoutingService(this.result);

  final ComputedRoute result;
  int calls = 0;

  @override
  Future<ComputedRoute> computeFirstSegment({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
  }) {
    calls++;
    return Future.value(result);
  }
}

int _counter = 0;

Future<RouteEditorController> _newEditorWithRouting(OfflineRoutingService routingService) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final tempDir = await Directory.systemTemp.createTemp('casa_loop_rename_color_test_');
  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => call.method == 'getApplicationDocumentsDirectory' ? tempDir.path : null,
  );
  final containerName = 'GetStorage_rename_color_test_${_counter++}';
  final storage = GetStorage(containerName, tempDir.path);
  await storage.initStorage;
  await storage.erase();

  await Get.deleteAll(force: true);
  final markerRepo = FakeMarkerRepository();
  final routePrefRepo = FakeRoutePreferenceRepository();
  Get.put<MarkerRepository>(markerRepo, permanent: true);
  Get.put<RoutePreferenceRepository>(routePrefRepo, permanent: true);
  Get.put<RouteDraftRepository>(InMemoryRouteDraftRepository(), permanent: true);
  final editor = Get.put<RouteEditorController>(
    RouteEditorController(
      markerRepo,
      routePrefRepo,
      routingService: routingService,
      storageContainerName: containerName,
    ),
    permanent: true,
  );
  while (editor.isInitializing.value) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  return editor;
}

void main() {
  group('RouteEditorController.renameMarker', () {
    late TestDraftRepository draftRepository;
    late RouteEditorTestEnvironment environment;

    setUp(() async {
      draftRepository = TestDraftRepository();
      environment = await RouteEditorTestEnvironment.start(draftRepository: draftRepository);
    });

    tearDown(() async {
      await environment.dispose();
    });

    testWidgets('renomme un repère, persiste et restaure après redémarrage', (tester) async {
      await tester.runAsync(() async {
        await environment.editor.addValidatedMarker(_markerA);
        await environment.editor.addValidatedMarker(_markerB);

        await environment.editor.renameMarker(_markerA, 'Nouveau départ');

        expect(environment.editor.validatedMarkers[0].name, 'Nouveau départ');
        expect(
          environment.editor.markerDisplayNameFor(environment.editor.validatedMarkers[0], 0),
          'Nouveau départ',
        );

        final restarted = await environment.restart();
        expect(restarted.editor.validatedMarkers[0].name, 'Nouveau départ');
      });
    });

    testWidgets('« Repère » saisi explicitement reste « Repère » après réorganisation et restauration', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await environment.editor.addValidatedMarker(_markerA);
        await environment.editor.addValidatedMarker(_markerB);
        await environment.editor.addValidatedMarker(_markerC);

        await environment.editor.renameMarker(_markerA, 'Repère');
        expect(environment.editor.validatedMarkers[0].name, 'Repère');
        expect(environment.editor.markerDisplayNameFor(environment.editor.validatedMarkers[0], 0), 'Repère');

        // Réordonne [m1, m2, m3] en [m3, m1, m2] : le nom stocké suit le
        // repère, pas la position.
        environment.editor.reorderMarkers(2, 0);
        await environment.editor.flushWorkingState();
        final indexOfM1 = environment.editor.validatedMarkers.indexWhere((m) => m.id == 'm1');
        expect(environment.editor.validatedMarkers[indexOfM1].name, 'Repère');
        expect(
          environment.editor.markerDisplayNameFor(environment.editor.validatedMarkers[indexOfM1], indexOfM1),
          'Repère',
        );

        final restarted = await environment.restart();
        final restoredIndex = restarted.editor.validatedMarkers.indexWhere((m) => m.id == 'm1');
        expect(restarted.editor.validatedMarkers[restoredIndex].name, 'Repère');
      });
    });

    testWidgets('un nom vide (après trim) est refusé sans aucune mutation', (tester) async {
      await tester.runAsync(() async {
        await environment.editor.addValidatedMarker(_markerA);
        await environment.editor.addValidatedMarker(_markerB);

        await expectLater(
          environment.editor.renameMarker(_markerA, '   '),
          throwsA(isA<InvalidRouteDraftException>()),
        );

        expect(environment.editor.validatedMarkers[0].name, 'Départ');
      });
    });

    testWidgets('Annuler (ne pas appeler renameMarker) ne produit aucune modification', (tester) async {
      await tester.runAsync(() async {
        await environment.editor.addValidatedMarker(_markerA);
        await environment.editor.addValidatedMarker(_markerB);

        // Simule l'« Annuler » du dialogue de renommage : aucun appel à
        // renameMarker n'est effectué.
        expect(environment.editor.validatedMarkers[0].name, 'Départ');
      });
    });

    testWidgets('un échec de persistance restaure le nom précédent et ne masque pas l\u2019erreur', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await environment.editor.addValidatedMarker(_markerA);
        await environment.editor.addValidatedMarker(_markerB);

        (environment.markerRepository as FakeMarkerRepository).failNextReplaceAll = true;

        await expectLater(environment.editor.renameMarker(_markerA, 'Échec attendu'), throwsStateError);

        expect(environment.editor.validatedMarkers[0].name, 'Départ');
      });
    });

    testWidgets('sauvegarde, chargement et copie conservent le nom renommé', (tester) async {
      await tester.runAsync(() async {
        await environment.editor.addValidatedMarker(_markerA);
        await environment.editor.addValidatedMarker(_markerB);
        await environment.editor.renameMarker(_markerA, 'Renommé');
        await environment.editor.saveDraft();
        final originalId = environment.editor.currentDraftId.value!;

        await environment.editor.saveDraftAsCopy(name: 'Copie');
        final copyId = environment.editor.currentDraftId.value!;

        await environment.editor.loadDraft(originalId);
        expect(environment.editor.validatedMarkers[0].name, 'Renommé');

        await environment.editor.loadDraft(copyId);
        expect(environment.editor.validatedMarkers[0].name, 'Renommé');
      });
    });
  });

  group('RouteEditorController — couleurs de segment', () {
    late TestDraftRepository draftRepository;
    late RouteEditorTestEnvironment environment;

    setUp(() async {
      draftRepository = TestDraftRepository();
      environment = await RouteEditorTestEnvironment.start(draftRepository: draftRepository);
    });

    tearDown(() async {
      await environment.dispose();
    });

    testWidgets('couleur par défaut quand rien n\u2019est enregistré', (tester) async {
      await tester.runAsync(() async {
        await environment.editor.addValidatedMarker(_markerA);
        await environment.editor.addValidatedMarker(_markerB);

        expect(environment.editor.colorForSegment(0), SegmentColors.defaultColor);
      });
    });

    testWidgets('une couleur invalide retombe sur la couleur par défaut', (tester) async {
      await tester.runAsync(() async {
        await environment.editor.addValidatedMarker(_markerA);
        await environment.editor.addValidatedMarker(_markerB);

        environment.editor.setSegmentColor(0, 'pas-une-couleur');

        expect(environment.editor.colorForSegment(0), SegmentColors.defaultColor);
      });
    });

    testWidgets('une couleur choisie persiste et se restaure après redémarrage', (tester) async {
      await tester.runAsync(() async {
        await environment.editor.addValidatedMarker(_markerA);
        await environment.editor.addValidatedMarker(_markerB);

        environment.editor.setSegmentColor(0, '#1E88E5');
        await environment.editor.flushWorkingState();

        final restarted = await environment.restart();
        expect(restarted.editor.colorForSegment(0), '#1E88E5');
      });
    });

    testWidgets('la couleur suit le couple dirigé, pas l\u2019index, après réorganisation', (tester) async {
      await tester.runAsync(() async {
        await environment.editor.addValidatedMarker(_markerA);
        await environment.editor.addValidatedMarker(_markerB);
        await environment.editor.addValidatedMarker(_markerC);

        // Segment 0 : m1 → m2.
        environment.editor.setSegmentColor(0, '#2E7D32');
        await environment.editor.flushWorkingState();

        // Réordonne [m1, m2, m3] en [m3, m1, m2] : le couple dirigé m1→m2
        // est préservé (désormais au segment 1), le reste change de place.
        environment.editor.reorderMarkers(2, 0);
        await environment.editor.flushWorkingState();

        final ids = environment.editor.validatedMarkers.map((m) => m.id).toList();
        final newIndexOfM1ToM2 = ids.indexOf('m1');
        expect(environment.editor.validatedMarkers[newIndexOfM1ToM2].id, 'm1');
        expect(environment.editor.validatedMarkers[(newIndexOfM1ToM2 + 1) % ids.length].id, 'm2');
        expect(environment.editor.colorForSegment(newIndexOfM1ToM2), '#2E7D32');

        // Le nouveau couple créé par la réorganisation reçoit la couleur
        // par défaut, jamais celle de l'ancien segment 0.
        final otherSegmentIndex = (newIndexOfM1ToM2 + 1) % ids.length;
        if (otherSegmentIndex != newIndexOfM1ToM2) {
          expect(environment.editor.colorForSegment(otherSegmentIndex), SegmentColors.defaultColor);
        }
      });
    });

    testWidgets('sauvegarde, chargement et copie conservent la couleur de segment', (tester) async {
      await tester.runAsync(() async {
        await environment.editor.addValidatedMarker(_markerA);
        await environment.editor.addValidatedMarker(_markerB);
        environment.editor.setSegmentColor(0, '#6A1B9A');
        await environment.editor.saveDraft();
        final originalId = environment.editor.currentDraftId.value!;

        await environment.editor.saveDraftAsCopy(name: 'Copie couleur');
        final copyId = environment.editor.currentDraftId.value!;

        await environment.editor.loadDraft(originalId);
        expect(environment.editor.colorForSegment(0), '#6A1B9A');

        await environment.editor.loadDraft(copyId);
        expect(environment.editor.colorForSegment(0), '#6A1B9A');
      });
    });

    testWidgets('ancien trajet sans couleur enregistrée se charge avec la couleur par défaut', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await environment.editor.addValidatedMarker(_markerA);
        await environment.editor.addValidatedMarker(_markerB);
        await environment.editor.saveDraft();
        final id = environment.editor.currentDraftId.value!;

        await environment.editor.newDraft();
        await environment.editor.loadDraft(id);

        expect(environment.editor.colorForSegment(0), SegmentColors.defaultColor);
      });
    });
  });

  group('Interaction renommage/couleur avec le résultat tracé', () {
    test('un renommage ne déclenche pas de nouveau calcul ni n\u2019invalide le résultat affiché', () async {
      const fakeRoute = ComputedRoute(
        geometry: [
          ComputedRoutePoint(latitude: 1, longitude: 1),
          ComputedRoutePoint(latitude: 2, longitude: 2),
        ],
        distanceKm: 5,
        durationSeconds: 300,
        startSnapDistanceMeters: 1,
        endSnapDistanceMeters: 1,
      );
      final service = _CountingRoutingService(fakeRoute);
      final editor = await _newEditorWithRouting(service);
      await editor.addValidatedMarker(_markerA);
      await editor.addValidatedMarker(_markerB);
      await editor.traceRoute();
      expect(service.calls, 1);
      expect(editor.tracedSegment.value, isNotNull);
      final identity = editor.tracedSegmentIdentity.value;
      expect(identity?.startMarkerId, 'm1');
      expect(identity?.endMarkerId, 'm2');
      expect(identity?.startNumber, 1);
      expect(identity?.endNumber, 2);
      final revision = editor.routeResultRevision.value;

      await editor.renameMarker(_markerA, 'Départ renommé');

      expect(service.calls, 1);
      expect(editor.tracedSegment.value, same(fakeRoute));
      expect(editor.routeResultRevision.value, revision);
      expect(editor.tracedSegmentIdentity.value, same(identity));
    });

    test('un changement de couleur n\u2019appelle jamais le moteur de calcul', () async {
      const fakeRoute = ComputedRoute(
        geometry: [
          ComputedRoutePoint(latitude: 1, longitude: 1),
          ComputedRoutePoint(latitude: 2, longitude: 2),
        ],
        distanceKm: 5,
        durationSeconds: 300,
        startSnapDistanceMeters: 1,
        endSnapDistanceMeters: 1,
      );
      final service = _CountingRoutingService(fakeRoute);
      final editor = await _newEditorWithRouting(service);
      await editor.addValidatedMarker(_markerA);
      await editor.addValidatedMarker(_markerB);
      await editor.traceRoute();
      expect(service.calls, 1);

      editor.setSegmentColor(0, '#00838F');

      expect(service.calls, 1);
      expect(editor.tracedSegment.value, same(fakeRoute));
    });
  });
}
