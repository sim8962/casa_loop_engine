import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:casa_loop_engine/models/computed_route.dart';
import 'package:casa_loop_engine/services/routing/valhalla_route_engine.dart';

/// Paire de référence de la preuve : Casa Voyageurs → Mosquée Hassan II.
const _refStartLat = 33.5898;
const _refStartLon = -7.5902;
const _refEndLat = 33.6084;
const _refEndLon = -7.6326;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ValhallaRouteEngine.buildMotorcycleRequest', () {
    test('produit le contrat JSON natif attendu', () {
      final json = ValhallaRouteEngine.buildMotorcycleRequest([
        (_refStartLat, _refStartLon),
        (_refEndLat, _refEndLon),
      ]);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['costing'], 'motorcycle');
      expect(decoded['units'], 'kilometers');
      expect(decoded['directions_type'], 'none');
      final locations = decoded['locations'] as List<dynamic>;
      expect(locations, hasLength(2));
      expect(locations[0], {'lat': _refStartLat, 'lon': _refStartLon, 'type': 'break'});
      expect(locations[1], {'lat': _refEndLat, 'lon': _refEndLon, 'type': 'break'});
    });
  });

  group('ValhallaRouteEngine canal natif', () {
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('casa/routing'),
        null,
      );
    });

    test('configure transmet le chemin au canal', () async {
      String? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('casa/routing'),
        (call) async {
          if (call.method == 'configure') {
            received = (call.arguments as Map)['configPath'] as String;
            return null;
          }
          return null;
        },
      );
      await const ValhallaRouteEngine().configure('/documents/routing/valhalla.json');
      expect(received, '/documents/routing/valhalla.json');
    });

    test('routeRaw envoie la requête brute et décode la réponse', () async {
      String? sentRequest;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('casa/routing'),
        (call) async {
          if (call.method == 'route') {
            sentRequest = (call.arguments as Map)['request'] as String;
            return '{"trip":{"summary":{"length":1.0,"time":2.0},"legs":[{"shape":"_p~iF~ps|U_ulLnnqC_mqNvxq`@"}],"locations":[]}}';
          }
          return null;
        },
      );
      final response = await const ValhallaRouteEngine().routeRaw('{"x":1}');
      expect(sentRequest, '{"x":1}');
      expect(response['trip'], isA<Map<String, dynamic>>());
    });

    test('routeRaw propage la PlatformException native', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('casa/routing'),
        (call) async => throw PlatformException(code: 'route_failed', message: 'natif ko'),
      );
      expect(
        () => const ValhallaRouteEngine().routeRaw('{}'),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'route_failed')),
      );
    });
  });

  group('ComputedRoute', () {
    test('haversine utilise des distances de référence indépendantes', () {
      expect(ComputedRoute.haversineMeters(33.5, -7.6, 33.5, -7.6), 0);
      expect(ComputedRoute.haversineMeters(0, 0, 0, 1), closeTo(111195, 1));
      final distance = ComputedRoute.haversineMeters(0, 0, 0, 0.01);
      expect(distance, closeTo(1111.95, 0.1));
      expect(distance, greaterThan(ComputedRoute.maxSnapDistanceMeters));
    });

    test('décode la réponse Mac de référence (polyline6 + summary)', () {
      final file = File('tool/routing_proof/results/response_casa_voyageurs_hassan2.json');
      final response = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final route = ComputedRoute.fromValhallaJson(
        response,
        requestedStartLat: _refStartLat,
        requestedStartLon: _refStartLon,
        requestedEndLat: _refEndLat,
        requestedEndLon: _refEndLon,
      );
      expect(route.distanceKm, closeTo(5.751, 0.001));
      expect(route.durationSeconds, closeTo(380.165, 0.01));
      expect(route.geometry.length, greaterThan(10));
      // Extrémités vérifiées dans la polyline de référence ; les écarts
      // sont calculés indépendamment, pas depuis trip.locations.
      expect(route.geometry.first.latitude, closeTo(33.590468, 0.000001));
      expect(route.geometry.first.longitude, closeTo(-7.590891, 0.000001));
      expect(route.geometry.last.latitude, closeTo(33.607037, 0.000001));
      expect(route.geometry.last.longitude, closeTo(-7.631805, 0.000001));
      expect(route.startSnapDistanceMeters, closeTo(98.05, 0.1));
      expect(route.endSnapDistanceMeters, closeTo(168.49, 0.1));
    });

    test('rejette une réponse sans trip', () {
      expect(
        () => ComputedRoute.fromValhallaJson(
          const {},
          requestedStartLat: 0,
          requestedStartLon: 0,
          requestedEndLat: 0,
          requestedEndLon: 0,
        ),
        throwsFormatException,
      );
    });
  });
}
