import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:casa_loop_engine/controllers/route_editor_controller.dart';
import 'package:casa_loop_engine/models/entities/route_draft_entity.dart';
import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/models/route_draft.dart';
import 'package:casa_loop_engine/models/route_draft_segment_preference.dart';
import 'package:casa_loop_engine/services/repositories/objectbox_route_draft_repository.dart';

import '../test_helpers/fake_repositories.dart';
import '../test_helpers/test_harness.dart';

const _markerA = MapMarkerItem(id: 'm1', name: 'Départ', type: 'ville', latitude: 1, longitude: 1);
const _markerB = MapMarkerItem(id: 'm2', name: 'Arrivée', type: 'ville', latitude: 2, longitude: 2);
const _markerC = MapMarkerItem(id: 'm3', name: 'Étape', type: 'ville', latitude: 3, longitude: 3);

RouteDraft _draft({String name = '', required DateTime createdAt}) => RouteDraft(
  name: name,
  createdAt: createdAt,
  savedAt: createdAt,
  targetMode: 'distance',
  targetDistanceKm: 10,
  totalDistanceKm: 10,
  totalDurationHours: 1,
  averageSpeedKmh: 10,
  markers: const [_markerA, _markerB],
  preferences: const [
    RouteDraftSegmentPreference(startMarkerId: 'm1', endMarkerId: 'm2', value: 0),
    RouteDraftSegmentPreference(startMarkerId: 'm2', endMarkerId: 'm1', value: 0),
  ],
);

void main() {
  late TestDraftRepository draftRepository;
  late RouteEditorTestEnvironment environment;

  setUp(() async {
    draftRepository = TestDraftRepository();
    environment = await RouteEditorTestEnvironment.start(draftRepository: draftRepository);
  });

  tearDown(() async {
    await environment.dispose();
  });

  Future<void> addTwoMarkers() async {
    await environment.editor.addValidatedMarker(_markerA);
    await environment.editor.addValidatedMarker(_markerB);
  }

  testWidgets(
    'ancienne entrée ObjectBox : createdAtMillis=0 converti depuis savedAt, nom par défaut stable après sauvegarde et rechargement',
    (tester) async {
      await tester.runAsync(() async {
        final legacySavedAt = DateTime(2026, 8, 20, 9, 5);
        // Entrée réellement écrite avant l'ajout du champ : createdAtMillis
        // vaut 0 et name est vide.
        final entity = RouteDraftEntity(
          id: 7,
          name: '',
          createdAtMillis: 0,
          savedAtMillis: legacySavedAt.millisecondsSinceEpoch,
          targetMode: 'distance',
          targetDistanceKm: 10,
          totalDistanceKm: 10,
          totalDurationHours: 1,
          averageSpeedKmh: 10,
          markersJson: jsonEncode([
            {
              'id': 'm1',
              'name': 'Départ',
              'type': 'ville',
              'latitude': 1.0,
              'longitude': 1.0,
              'orderIndex': 0,
            },
            {
              'id': 'm2',
              'name': 'Arrivée',
              'type': 'ville',
              'latitude': 2.0,
              'longitude': 2.0,
              'orderIndex': 1,
            },
          ]),
          preferencesJson: jsonEncode([
            {'startMarkerId': 'm1', 'endMarkerId': 'm2', 'value': 0.0},
            {'startMarkerId': 'm2', 'endMarkerId': 'm1', 'value': 0.0},
          ]),
        );

        // La conversion isolée applique le repli sur savedAtMillis.
        final converted = routeDraftFromEntity(entity);
        expect(converted.id, '7');
        expect(converted.name, '');
        expect(converted.createdAt, legacySavedAt);
        expect(converted.savedAt, legacySavedAt);
        expect(converted.markers.length, 2);

        final expectedName = RouteEditorController.defaultDraftName(legacySavedAt);
        await draftRepository.save(converted);
        await environment.editor.loadDraft('7');
        expect(environment.editor.displayDraftName, expectedName);

        // Première modification : la date de création reconduite est
        // conservée et le nom par défaut reste identique après
        // sauvegarde/rechargement.
        await environment.editor.saveDraft();
        final reloaded = await draftRepository.load('7');
        expect(reloaded?.createdAt, legacySavedAt);
        expect(reloaded?.name, expectedName);
        await environment.editor.loadDraft('7');
        expect(environment.editor.displayDraftName, expectedName);
      });
    },
  );

  testWidgets('un nom saisi pendant la sauvegarde n\u2019est pas écrasé par le nom du snapshot', (
    tester,
  ) async {
    await tester.runAsync(() async {
      draftRepository.saveDelay = const Duration(milliseconds: 300);
      await addTwoMarkers();
      environment.editor.setDraftName('Avant');

      final save = environment.editor.saveDraft();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      environment.editor.setDraftName('Pendant');
      await save;

      // Le trajet écrit porte le nom du snapshot ; l'état de travail
      // conserve la saisie plus récente, également persistée.
      final saved = await draftRepository.listAll();
      expect(saved.single.name, 'Avant');
      expect(environment.editor.draftName.value, 'Pendant');
      expect(environment.storage.read<String>('currentDraftName'), 'Pendant');
    });
  });

  /// Lit le fichier GetStorage.gs en attendant que le flush différé de la
  /// bibliothèque ait propagé [expectedKey] = [expectedValue] sur disque.
  /// GetStorage.write() n'attend pas la fin réelle du flush interne : on
  /// sonde donc le fichier plutôt que de le lire immédiatement.
  Future<Map<String, dynamic>> readStorageFile(String key, Object? expectedValue) async {
    final file = File('${environment.tempDir.path}/${environment.storageContainerName}.gs');
    for (var i = 0; i < 200; i++) {
      if (file.existsSync()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final data = jsonDecode(content) as Map<String, dynamic>;
          if (data[key] == expectedValue) return data;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    throw StateError('Clé $key absente du fichier GetStorage.gs après attente.');
  }

  testWidgets(
    'première sauvegarde et copie : identité persistée dans GetStorage, retrouvée après redémarrage',
    (tester) async {
      await tester.runAsync(() async {
        await addTwoMarkers();
        environment.editor.setDraftName('Original');
        await environment.editor.saveDraft();
        final originalId = environment.editor.currentDraftId.value!;

        // Les valeurs atteignent réellement le fichier GetStorage du
        // répertoire temporaire, pas seulement la mémoire du processus.
        final onDisk = await readStorageFile('currentDraftId', originalId);
        expect(onDisk['currentDraftName'], 'Original');

        await environment.editor.saveDraftAsCopy(name: 'Copie X');
        final copyId = environment.editor.currentDraftId.value!;
        expect(copyId, isNot(equals(originalId)));
        final onDiskAfterCopy = await readStorageFile('currentDraftId', copyId);
        expect(onDiskAfterCopy['currentDraftName'], 'Copie X');

        final restarted = await environment.restart();
        expect(restarted.editor.currentDraftId.value, copyId);
        expect(restarted.editor.draftName.value, 'Copie X');
        expect(restarted.editor.validatedMarkers.length, 2);
      });
    },
  );

  testWidgets('chargement impossible : trajet inconnu ou erreur de lecture laissent l\u2019état inchangé', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await addTwoMarkers();
      environment.editor.setDraftName('État courant');

      await expectLater(environment.editor.loadDraft('inconnu'), throwsStateError);
      expect(environment.editor.validatedMarkers.length, 2);
      expect(environment.editor.draftName.value, 'État courant');
      expect(environment.editor.isLoadingDraft.value, isFalse);

      final realId = await draftRepository.save(_draft(name: 'Sauvegardé', createdAt: DateTime(2026, 10, 1)));
      draftRepository.failLoad = true;
      await expectLater(environment.editor.loadDraft(realId), throwsStateError);
      expect(environment.editor.validatedMarkers.length, 2);
      expect(environment.editor.draftName.value, 'État courant');
      draftRepository.failLoad = false;
    });
  });

  testWidgets('doubles clics : sauvegarde ou chargement concurrent rejeté', (tester) async {
    await tester.runAsync(() async {
      draftRepository.saveDelay = const Duration(milliseconds: 300);
      final existingId = await draftRepository.save(
        _draft(name: 'Existant', createdAt: DateTime(2026, 10, 1)),
      );
      await addTwoMarkers();

      final firstSave = environment.editor.saveDraft();
      await expectLater(environment.editor.saveDraft(), throwsStateError);
      // Un chargement pendant la sauvegarde est également refusé.
      await expectLater(environment.editor.loadDraft(existingId), throwsStateError);
      await firstSave;

      // Pendant un chargement long, un second chargement est refusé.
      draftRepository.loadDelay = const Duration(milliseconds: 300);
      final firstLoad = environment.editor.loadDraft(existingId);
      await expectLater(environment.editor.loadDraft(existingId), throwsStateError);
      await firstLoad;
    });
  });

  testWidgets('le chargement d\u2019un trajet plus court remplace intégralement l\u2019état de travail', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await addTwoMarkers();
      await environment.editor.addValidatedMarker(_markerC);
      expect(environment.editor.segmentRoutePreferences.length, 3);

      final shortId = await draftRepository.save(_draft(name: 'Court', createdAt: DateTime(2026, 10, 1)));
      await environment.editor.loadDraft(shortId);

      expect(environment.editor.validatedMarkers.length, 2);
      expect(environment.editor.segmentRoutePreferences.length, 2);
      expect(environment.editor.currentDraftId.value, shortId);
    });
  });

  testWidgets(
    'l\u2019autosauvegarde de l\u2019état de travail ne crée ni ne modifie aucun trajet de la bibliothèque',
    (tester) async {
      await tester.runAsync(() async {
        final seededId = await draftRepository.save(_draft(name: 'Seed', createdAt: DateTime(2026, 10, 1)));
        await addTwoMarkers();
        environment.editor.setRoutePreference(0, 50);
        await environment.editor.flushWorkingState();

        final all = await draftRepository.listAll();
        expect(all.length, 1);
        final seeded = await draftRepository.load(seededId);
        expect(seeded?.name, 'Seed');
        expect(seeded?.markers.length, 2);
      });
    },
  );

  testWidgets('« Nouveau trajet » en échec : état, identité, nom et objectifs restaurés', (tester) async {
    await tester.runAsync(() async {
      await addTwoMarkers();
      environment.editor.setDraftName('Avant échec');
      await environment.editor.saveDraft();
      final savedId = environment.editor.currentDraftId.value;

      (environment.markerRepository as FakeMarkerRepository).failNextReplaceAll = true;
      await expectLater(environment.editor.newDraft(), throwsStateError);

      expect(environment.editor.validatedMarkers.length, 2);
      expect(environment.editor.currentDraftId.value, savedId);
      expect(environment.editor.draftName.value, 'Avant échec');
    });
  });
}
