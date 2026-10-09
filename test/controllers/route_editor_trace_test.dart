import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'package:casa_loop_engine/controllers/route_editor_controller.dart';
import 'package:casa_loop_engine/models/computed_route.dart';
import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/services/repositories/marker_repository.dart';
import 'package:casa_loop_engine/services/repositories/route_draft_repository.dart';
import 'package:casa_loop_engine/services/repositories/route_preference_repository.dart';
import 'package:casa_loop_engine/services/routing/offline_routing_service.dart';

import '../test_helpers/fake_repositories.dart';

/// Service de calcul simulé : n'appelle jamais le canal natif ni le disque.
class _FakeRoutingService extends OfflineRoutingService {
  _FakeRoutingService({this.result, this.error, this.completer});

  final ComputedRoute? result;
  final Object? error;
  final Completer<ComputedRoute>? completer;
  int calls = 0;
  (double, double)? requestedStart;
  (double, double)? requestedEnd;

  @override
  Future<ComputedRoute> computeFirstSegment({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
  }) {
    calls++;
    requestedStart = (startLat, startLon);
    requestedEnd = (endLat, endLon);
    final pending = completer;
    if (pending != null) return pending.future;
    final failure = error;
    if (failure != null) return Future.error(failure);
    return Future.value(result);
  }
}

int _counter = 0;

Future<RouteEditorController> _newEditor({required OfflineRoutingService routingService}) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final tempDir = await Directory.systemTemp.createTemp('casa_loop_trace_test_');
  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => call.method == 'getApplicationDocumentsDirectory' ? tempDir.path : null,
  );
  final containerName = 'GetStorage_trace_test_${_counter++}';
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

MapMarkerItem _marker(String id, double lat, double lon) => MapMarkerItem(
  id: id,
  name: id,
  type: 'personnalisé',
  latitude: lat,
  longitude: lon,
);

void main() {
  group('RouteEditorController.traceRoute', () {
    test('sauvegarde le trajet puis publie géométrie et mesures du premier segment', () async {
      const fakeRoute = ComputedRoute(
        geometry: [
          ComputedRoutePoint(latitude: 33.5898, longitude: -7.5902),
          ComputedRoutePoint(latitude: 33.6, longitude: -7.61),
          ComputedRoutePoint(latitude: 33.6084, longitude: -7.6326),
        ],
        distanceKm: 5.751,
        durationSeconds: 380.165,
        startSnapDistanceMeters: 3.5,
        endSnapDistanceMeters: 4.2,
      );
      final service = _FakeRoutingService(result: fakeRoute);
      final editor = await _newEditor(routingService: service);
      await editor.addValidatedMarker(_marker('a', 33.5898, -7.5902));
      await editor.addValidatedMarker(_marker('b', 33.6084, -7.6326));

      await editor.traceRoute();

      expect(service.calls, 1);
      expect(service.requestedStart, (33.5898, -7.5902));
      expect(service.requestedEnd, (33.6084, -7.6326));
      expect(editor.isTracing.value, isFalse);
      expect(editor.traceError.value, isNull);
      expect(editor.tracedSegment.value, same(fakeRoute));
      // La sauvegarde a bien eu lieu : le trajet courant a un identifiant.
      expect(editor.currentDraftId.value, isNotNull);
    });

    test("une erreur de calcul est exposée sans masquer la sauvegarde ni lever d'exception", () async {
      final service = _FakeRoutingService(error: const OfflineRoutingException('graphe absent'));
      final editor = await _newEditor(routingService: service);
      await editor.addValidatedMarker(_marker('a', 33.5898, -7.5902));
      await editor.addValidatedMarker(_marker('b', 33.6084, -7.6326));

      await editor.traceRoute();

      expect(editor.isTracing.value, isFalse);
      expect(editor.tracedSegment.value, isNull);
      expect(editor.traceError.value, contains('graphe absent'));
      expect(editor.currentDraftId.value, isNotNull);
    });

    test('un changement de repères invalide le résultat affiché', () async {
      final service = _FakeRoutingService(
        result: const ComputedRoute(
          geometry: [
            ComputedRoutePoint(latitude: 0, longitude: 0),
            ComputedRoutePoint(latitude: 1, longitude: 1),
          ],
          distanceKm: 1,
          durationSeconds: 60,
          startSnapDistanceMeters: 0,
          endSnapDistanceMeters: 0,
        ),
      );
      final editor = await _newEditor(routingService: service);
      await editor.addValidatedMarker(_marker('a', 33.5898, -7.5902));
      await editor.addValidatedMarker(_marker('b', 33.6084, -7.6326));
      await editor.traceRoute();
      expect(editor.tracedSegment.value, isNotNull);
      final revision = editor.routeResultRevision.value;

      await editor.addValidatedMarker(_marker('c', 33.60, -7.60));

      expect(editor.tracedSegment.value, isNull);
      expect(editor.traceError.value, isNull);
      expect(editor.routeResultRevision.value, greaterThan(revision));
    });

    test('une double demande pendant le calcul est refusée', () async {
      final completer = Completer<ComputedRoute>();
      final service = _FakeRoutingService(completer: completer);
      final editor = await _newEditor(routingService: service);
      await editor.addValidatedMarker(_marker('a', 33.5898, -7.5902));
      await editor.addValidatedMarker(_marker('b', 33.6084, -7.6326));

      final first = editor.traceRoute();
      // Laisse la sauvegarde se terminer et le calcul partir en vol.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await expectLater(editor.traceRoute(), throwsStateError);

      completer.complete(
        const ComputedRoute(
          geometry: [
            ComputedRoutePoint(latitude: 0, longitude: 0),
            ComputedRoutePoint(latitude: 1, longitude: 1),
          ],
          distanceKm: 1,
          durationSeconds: 60,
          startSnapDistanceMeters: 0,
          endSnapDistanceMeters: 0,
        ),
      );
      await first;
      expect(service.calls, 1);
    });
  });
}
