import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:casa_loop_engine/models/entities/route_draft_entity.dart';
import 'package:casa_loop_engine/models/route_draft_segment_preference.dart';
import 'package:casa_loop_engine/services/repositories/objectbox_route_draft_repository.dart';

RouteDraftEntity _entity({required String preferencesJson}) => RouteDraftEntity(
  id: 1,
  name: 'Trajet',
  createdAtMillis: 1000,
  savedAtMillis: 1000,
  targetMode: 'distance',
  targetDistanceKm: 10,
  totalDistanceKm: 10,
  totalDurationHours: 1,
  averageSpeedKmh: 10,
  markersJson: jsonEncode([
    {'id': 'a', 'name': 'A', 'type': 'ville', 'latitude': 1.0, 'longitude': 1.0, 'orderIndex': 0},
    {'id': 'b', 'name': 'B', 'type': 'ville', 'latitude': 2.0, 'longitude': 2.0, 'orderIndex': 1},
  ]),
  preferencesJson: preferencesJson,
);

void main() {
  group('SegmentColors', () {
    test('resolve retombe sur la couleur par défaut si null ou invalide', () {
      expect(SegmentColors.resolve(null), SegmentColors.defaultColor);
      expect(SegmentColors.resolve('pas une couleur'), SegmentColors.defaultColor);
      expect(SegmentColors.resolve('#ZZZZZZ'), SegmentColors.defaultColor);
      expect(SegmentColors.resolve('#1E88E5'), '#1E88E5');
    });

    test('isValid accepte uniquement #RRGGBB', () {
      expect(SegmentColors.isValid('#1E88E5'), isTrue);
      expect(SegmentColors.isValid('1E88E5'), isFalse);
      expect(SegmentColors.isValid('#1E88E'), isFalse);
      expect(SegmentColors.isValid(null), isFalse);
    });
  });

  group('routeDraftFromEntity — compatibilité couleur', () {
    test('ancien JSON sans champ couleur : chaque préférence a color=null, résolu en couleur par défaut', () {
      final entity = _entity(
        preferencesJson: jsonEncode([
          {'startMarkerId': 'a', 'endMarkerId': 'b', 'value': 0.0},
          {'startMarkerId': 'b', 'endMarkerId': 'a', 'value': 0.0},
        ]),
      );

      final draft = routeDraftFromEntity(entity);

      expect(draft.preferences, hasLength(2));
      for (final pref in draft.preferences) {
        expect(pref.color, isNull);
        expect(SegmentColors.resolve(pref.color), SegmentColors.defaultColor);
      }
    });

    test('couleur invalide stockée dans le JSON : conservée telle quelle par le décodage, '
        'mais résolue en couleur par défaut à l\u2019affichage', () {
      final entity = _entity(
        preferencesJson: jsonEncode([
          {'startMarkerId': 'a', 'endMarkerId': 'b', 'value': 0.0, 'color': 'not-a-color'},
          {'startMarkerId': 'b', 'endMarkerId': 'a', 'value': 0.0},
        ]),
      );

      final draft = routeDraftFromEntity(entity);

      final aToB = draft.preferences.firstWhere((p) => p.startMarkerId == 'a');
      expect(aToB.color, 'not-a-color');
      expect(SegmentColors.resolve(aToB.color), SegmentColors.defaultColor);
    });

    test('couleur valide stockée dans le JSON : conservée et résolue telle quelle', () {
      final entity = _entity(
        preferencesJson: jsonEncode([
          {'startMarkerId': 'a', 'endMarkerId': 'b', 'value': 0.0, 'color': '#1E88E5'},
          {'startMarkerId': 'b', 'endMarkerId': 'a', 'value': 0.0, 'color': '#2E7D32'},
        ]),
      );

      final draft = routeDraftFromEntity(entity);

      final aToB = draft.preferences.firstWhere((p) => p.startMarkerId == 'a');
      final bToA = draft.preferences.firstWhere((p) => p.startMarkerId == 'b');
      expect(SegmentColors.resolve(aToB.color), '#1E88E5');
      expect(SegmentColors.resolve(bToA.color), '#2E7D32');
    });
  });
}
