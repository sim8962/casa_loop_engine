import 'package:flutter_test/flutter_test.dart';

import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/models/route_draft.dart';
import 'package:casa_loop_engine/models/route_draft_segment_preference.dart';
import 'package:casa_loop_engine/services/repositories/route_draft_repository.dart';

RouteDraft _draft({
  String? id,
  required String name,
  required DateTime createdAt,
}) {
  final markerA = MapMarkerItem(id: 'a', name: 'A', type: 'personnalisé', latitude: 1, longitude: 1);
  final markerB = MapMarkerItem(id: 'b', name: 'B', type: 'personnalisé', latitude: 2, longitude: 2);
  return RouteDraft(
    id: id,
    name: name,
    createdAt: createdAt,
    savedAt: createdAt,
    targetMode: 'distance',
    targetDistanceKm: 10,
    totalDistanceKm: 10,
    totalDurationHours: 1,
    averageSpeedKmh: 10,
    markers: [markerA, markerB],
    preferences: const [
      RouteDraftSegmentPreference(startMarkerId: 'a', endMarkerId: 'b', value: 0),
      RouteDraftSegmentPreference(startMarkerId: 'b', endMarkerId: 'a', value: 0),
    ],
  );
}

void main() {
  group('InMemoryRouteDraftRepository', () {
    test('sauvegarde deux trajets indépendants, chacun avec son propre identifiant', () async {
      final repo = InMemoryRouteDraftRepository();
      final createdAt = DateTime(2026, 10, 6, 14, 37);

      final idA = await repo.save(_draft(name: 'Trajet A', createdAt: createdAt));
      final idB = await repo.save(_draft(name: 'Trajet B', createdAt: createdAt));

      expect(idA, isNot(equals(idB)));
      final all = await repo.listAll();
      expect(all.map((d) => d.name).toSet(), {'Trajet A', 'Trajet B'});
    });

    test('une sauvegarde avec un identifiant existant met à jour uniquement ce trajet', () async {
      final repo = InMemoryRouteDraftRepository();
      final createdAt = DateTime(2026, 10, 6, 14, 37);

      final idA = await repo.save(_draft(name: 'Trajet A', createdAt: createdAt));
      final idB = await repo.save(_draft(name: 'Trajet B', createdAt: createdAt));

      await repo.save(_draft(id: idA, name: 'Trajet A renommé', createdAt: createdAt));

      final draftA = await repo.load(idA);
      final draftB = await repo.load(idB);
      expect(draftA?.name, 'Trajet A renommé');
      expect(draftB?.name, 'Trajet B');
    });

    test('listAll retourne les trajets du plus récemment sauvegardé au plus ancien', () async {
      final repo = InMemoryRouteDraftRepository();
      await repo.save(_draft(name: 'Ancien', createdAt: DateTime(2026, 1, 1)));
      await repo.save(_draft(name: 'Récent', createdAt: DateTime(2026, 6, 1)));

      final all = await repo.listAll();
      expect(all.first.name, 'Récent');
      expect(all.last.name, 'Ancien');
    });

    test('load retourne null pour un identifiant inconnu', () async {
      final repo = InMemoryRouteDraftRepository();
      expect(await repo.load('inconnu'), isNull);
    });
  });
}
