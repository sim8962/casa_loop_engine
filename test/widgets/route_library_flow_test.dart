import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:casa_loop_engine/controllers/route_editor_controller.dart';
import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/models/route_draft.dart';
import 'package:casa_loop_engine/models/route_draft_segment_preference.dart';
import 'package:casa_loop_engine/services/repositories/route_draft_repository.dart';

import '../test_helpers/pump_app.dart';
import '../test_helpers/test_harness.dart';

RouteDraft _seedDraft({String name = '', required DateTime createdAt}) {
  final markerA = MapMarkerItem(
    id: 'a-${createdAt.microsecondsSinceEpoch}',
    name: 'Départ',
    type: 'ville',
    latitude: 1,
    longitude: 1,
  );
  final markerB = MapMarkerItem(
    id: 'b-${createdAt.microsecondsSinceEpoch}',
    name: 'Arrivée',
    type: 'ville',
    latitude: 2,
    longitude: 2,
  );
  return RouteDraft(
    name: name,
    createdAt: createdAt,
    savedAt: createdAt,
    targetMode: 'distance',
    targetDistanceKm: 20,
    totalDistanceKm: 20,
    totalDurationHours: 1,
    averageSpeedKmh: 20,
    markers: [markerA, markerB],
    preferences: [
      RouteDraftSegmentPreference(startMarkerId: markerA.id, endMarkerId: markerB.id, value: 0),
      RouteDraftSegmentPreference(startMarkerId: markerB.id, endMarkerId: markerA.id, value: 0),
    ],
  );
}

void main() {
  late RouteDraftRepository draftRepository;
  late RouteEditorTestEnvironment environment;
  late String idA;
  late String idB;
  late DateTime createdAtB;

  setUp(() async {
    draftRepository = InMemoryRouteDraftRepository();
    createdAtB = DateTime(2026, 10, 6, 14, 37);
    idA = await draftRepository.save(
      _seedDraft(name: 'Trajet matinal', createdAt: DateTime(2026, 9, 1, 8, 0)),
    );
    idB = await draftRepository.save(_seedDraft(createdAt: createdAtB));
    environment = await RouteEditorTestEnvironment.start(draftRepository: draftRepository);
  });

  tearDown(() async {
    await environment.dispose();
  });

  testWidgets('bouton « Charger mes trajets » ouvre la bibliothèque listant les trajets par leur nom', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pumpRouteLibraryTestApp(tester, environment.editor);

      expect(find.byKey(const Key('map-load-draft-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('map-load-draft-button')));
      await tester.pumpAndSettle();

      expect(find.text('Mes trajets'), findsOneWidget);
      expect(find.byKey(Key('route-library-item-$idA')), findsOneWidget);
      expect(find.text('Trajet matinal'), findsOneWidget);
      // Le trajet B n'a jamais été renommé : le nom par défaut, stable et
      // dérivé de sa création, est affiché dans la liste.
      expect(find.text(RouteEditorController.defaultDraftName(createdAtB)), findsOneWidget);
    });
  });

  testWidgets('un clic sur un trajet charge ses choix puis ouvre directement l\u2019éditeur, '
      'avec le nom du trajet visible et correctement restauré', (tester) async {
    await tester.runAsync(() async {
      await pumpRouteLibraryTestApp(tester, environment.editor);
      await tester.tap(find.byKey(const Key('map-load-draft-button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('route-library-item-$idA')));
      await tester.pumpAndSettle();

      // L'ancien dialogue de confirmation a disparu : l'éditeur s'ouvre
      // directement, avec le champ « Nom du trajet » visible et restauré.
      expect(find.text('Charger le trajet sauvegardé ?'), findsNothing);
      expect(find.text('Repères choisis'), findsOneWidget);
      final nameField = tester.widget<TextField>(find.byKey(const Key('route-name-field')));
      expect(nameField.controller?.text, 'Trajet matinal');
      expect(find.text('Sauvegarder'), findsOneWidget);
      expect(find.text('Tracer'), findsOneWidget);
    });
  });

  testWidgets('renommer puis sauvegarder met à jour uniquement le trajet édité ; '
      'le renommage est retrouvé dans la liste et l\u2019autre trajet reste intact', (tester) async {
    await tester.runAsync(() async {
      await pumpRouteLibraryTestApp(tester, environment.editor);
      await tester.tap(find.byKey(const Key('map-load-draft-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('route-library-item-$idA')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('route-name-field')), 'Trajet matinal renommé');
      await tester.pump();
      await tester.tap(find.text('Sauvegarder'));
      await tester.pumpAndSettle();

      final draftA = await draftRepository.load(idA);
      final draftB = await draftRepository.load(idB);
      expect(draftA?.name, 'Trajet matinal renommé');
      // Le trajet B, jamais chargé ni touché, reste disponible et inchangé.
      expect(draftB?.name, '');
      expect(draftB?.markers.length, 2);

      // Retour à la carte puis réouverture de la bibliothèque : le nouveau
      // nom y apparaît, et le trajet B est toujours listé séparément.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('map-load-draft-button')));
      await tester.pumpAndSettle();

      expect(find.text('Trajet matinal renommé'), findsOneWidget);
      expect(find.text('Trajet matinal'), findsNothing);
      expect(find.byKey(Key('route-library-item-$idB')), findsOneWidget);
    });
  });
}
