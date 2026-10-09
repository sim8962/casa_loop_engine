import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/models/route_draft.dart';
import 'package:casa_loop_engine/models/route_draft_segment_preference.dart';
import 'package:casa_loop_engine/routes/app_routes.dart';
import 'package:casa_loop_engine/views/selected_markers/views/selected_markers_view.dart';

import '../test_helpers/fake_repositories.dart';
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

/// Ouvre le menu de l'éditeur et sélectionne l'entrée [label].
Future<void> _openMenuAndTap(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('route-menu-button')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// Attend qu'un widget apparaisse : les opérations du controller sont
/// réellement asynchrones (IO disque) et ne sont pas couvertes par
/// pumpAndSettle, qui ne fait avancer que les frames.
Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 200; i++) {
    await tester.pump();
    if (tester.any(finder)) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Widget introuvable après attente : $finder');
}

void main() {
  late TestDraftRepository draftRepository;
  late RouteEditorTestEnvironment environment;
  late String idA;
  late String idB;

  setUp(() async {
    draftRepository = TestDraftRepository();
    idA = await draftRepository.save(_seedDraft(name: 'Trajet A', createdAt: DateTime(2026, 9, 1, 8, 0)));
    idB = await draftRepository.save(_seedDraft(name: 'Trajet B', createdAt: DateTime(2026, 10, 6, 14, 37)));
    environment = await RouteEditorTestEnvironment.start(draftRepository: draftRepository);
  });

  tearDown(() async {
    await environment.dispose();
  });

  testWidgets('bibliothèque : date et nombre de repères affichés, Réessayer recharge après une erreur', (
    tester,
  ) async {
    await tester.runAsync(() async {
      draftRepository.failListAll = true;
      await pumpRouteLibraryTestApp(tester, environment.editor);
      await tester.tap(find.byKey(const Key('map-load-draft-button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Chargement impossible'), findsOneWidget);
      expect(find.byKey(const Key('route-library-retry')), findsOneWidget);

      draftRepository.failListAll = false;
      await tester.tap(find.byKey(const Key('route-library-retry')));
      await tester.pumpAndSettle();

      expect(find.text('Trajet A'), findsOneWidget);
      expect(find.textContaining('2 repères'), findsWidgets);
      expect(find.textContaining('06/10/2026 14:37'), findsOneWidget);
    });
  });

  testWidgets(
    'menu « Nouveau trajet » : Annuler préserve l\u2019état, Abandonner le vide, Sauvegarder enregistre d\u2019abord',
    (tester) async {
      await tester.runAsync(() async {
        await pumpRouteLibraryTestApp(tester, environment.editor);
        await tester.tap(find.byKey(const Key('map-load-draft-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('route-library-item-$idA')));
        await tester.pumpAndSettle();

        // Annuler : le trajet chargé reste intact et affiché.
        await _openMenuAndTap(tester, 'Nouveau trajet');
        expect(find.text('Que faire du trajet en cours ?'), findsOneWidget);
        await tester.tap(find.byKey(const Key('new-draft-cancel')));
        await tester.pumpAndSettle();
        expect(environment.editor.validatedMarkers.length, 2);
        expect(environment.editor.currentDraftId.value, idA);

        // Abandonner : l'état est vidé sans créer de sauvegarde.
        await _openMenuAndTap(tester, 'Nouveau trajet');
        await tester.tap(find.byKey(const Key('new-draft-discard')));
        await tester.pumpAndSettle();
        expect(environment.editor.validatedMarkers, isEmpty);
        expect(environment.editor.currentDraftId.value, isNull);
        expect(find.text('Aucun repère choisi'), findsOneWidget);
        expect((await draftRepository.listAll()).length, 2);

        // Sauvegarder : repères restaurés dans le trajet chargé, puis vidés.
        await environment.editor.loadDraft(idB);
        await tester.pumpAndSettle();
        await _openMenuAndTap(tester, 'Nouveau trajet');
        await tester.tap(find.byKey(const Key('new-draft-save')));
        await tester.pumpAndSettle();
        final saved = await draftRepository.load(idB);
        expect(saved?.markers.length, 2);
        expect(environment.editor.validatedMarkers, isEmpty);
        expect(environment.editor.currentDraftId.value, isNull);
      });
    },
  );

  testWidgets('« Enregistrer une copie » : le nom choisi est utilisé et le champ affiche la copie active', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pumpRouteLibraryTestApp(tester, environment.editor);
      await tester.tap(find.byKey(const Key('map-load-draft-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('route-library-item-$idA')));
      await tester.pumpAndSettle();

      await _openMenuAndTap(tester, 'Enregistrer une copie');
      expect(find.text('Nom de la copie'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('copy-name-field')), 'Ma copie');
      await tester.tap(find.byKey(const Key('copy-confirm')));
      await tester.pumpAndSettle();

      final nameField = tester.widget<TextField>(find.byKey(const Key('route-name-field')));
      expect(nameField.controller?.text, 'Ma copie');
      final all = await draftRepository.listAll();
      expect(all.length, 3);
      final original = await draftRepository.load(idA);
      expect(original?.name, 'Trajet A');
      expect(all.any((d) => d.name == 'Ma copie' && d.id != idA), isTrue);
    });
  });

  testWidgets(
    '« Nouveau trajet » en échec : nom, objectifs et repères affichent tous les anciennes valeurs',
    (tester) async {
      await tester.runAsync(() async {
        await pumpRouteLibraryTestApp(tester, environment.editor);
        await tester.tap(find.byKey(const Key('map-load-draft-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('route-library-item-$idA')));
        await tester.pumpAndSettle();

        // La persistance de l'état de travail échoue pendant la
        // réinitialisation.
        (environment.markerRepository as FakeMarkerRepository).failNextReplaceAll = true;
        await _openMenuAndTap(tester, 'Nouveau trajet');
        await tester.tap(find.byKey(const Key('new-draft-discard')));
        await _waitFor(tester, find.textContaining('Nouveau trajet impossible'));
        await tester.pump();
        // Le rollback notifie les champs après restauration de l'identité :
        // tous affichent les valeurs du trajet précédent.
        final nameField = tester.widget<TextField>(find.byKey(const Key('route-name-field')));
        expect(nameField.controller?.text, 'Trajet A');
        expect(find.textContaining('Départ'), findsWidgets);
        expect(find.textContaining('Arrivée'), findsWidgets);
        final texts = tester
            .widgetList<TextField>(find.byType(TextField))
            .map((field) => field.controller?.text ?? '')
            .toList();
        expect(texts, contains('20'));
      });
    },
  );

  testWidgets(
    'depuis l\u2019éditeur, « Charger un trajet » charge dans l\u2019éditeur existant sans en empiler un second',
    (tester) async {
      await tester.runAsync(() async {
        await pumpRouteLibraryTestApp(tester, environment.editor);
        await tester.tap(find.byKey(const Key('map-load-draft-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('route-library-item-$idA')));
        await tester.pumpAndSettle();
        expect(find.byType(SelectedMarkersView), findsOneWidget);

        await _openMenuAndTap(tester, 'Charger un trajet');
        await tester.pumpAndSettle();
        expect(find.text('Mes trajets'), findsOneWidget);

        await tester.tap(find.byKey(Key('route-library-item-$idB')));
        await tester.pumpAndSettle();

        // Retour à l'éditeur déjà ouvert : un seul éditeur dans la pile, le
        // nom du trajet B affiché.
        expect(find.byType(SelectedMarkersView), findsOneWidget);
        expect(Get.currentRoute, AppRoutes.selectedMarkers);
        final nameField = tester.widget<TextField>(find.byKey(const Key('route-name-field')));
        expect(nameField.controller?.text, 'Trajet B');

        // Un seul retour arrière ramène à la carte : aucun second éditeur.
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('map-load-draft-button')), findsOneWidget);
        expect(find.byType(SelectedMarkersView), findsNothing);
      });
    },
  );
}
