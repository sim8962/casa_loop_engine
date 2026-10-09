import 'package:flutter_test/flutter_test.dart';

import 'package:casa_loop_engine/models/map_marker_item.dart';

import '../test_helpers/test_harness.dart';

void main() {
  late RouteEditorTestEnvironment environment;

  setUp(() async {
    environment = await RouteEditorTestEnvironment.start();
  });

  tearDown(() async {
    await environment.dispose();
  });

  Future<void> addTwoMarkers() async {
    final editor = environment.editor;
    await editor.addValidatedMarker(
      const MapMarkerItem(id: 'm1', name: 'Départ', type: 'ville', latitude: 1, longitude: 1),
    );
    await editor.addValidatedMarker(
      const MapMarkerItem(id: 'm2', name: 'Arrivée', type: 'ville', latitude: 2, longitude: 2),
    );
  }

  testWidgets('« Nouveau trajet » réinitialise l\u2019état de travail sans toucher aux trajets sauvegardés', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final editor = environment.editor;
      await addTwoMarkers();
      editor.setDraftName('Trajet existant');
      await editor.saveDraft();
      final savedId = editor.currentDraftId.value;
      expect(savedId, isNotNull);

      await editor.newDraft();

      expect(editor.validatedMarkers, isEmpty);
      expect(editor.currentDraftId.value, isNull);
      expect(editor.draftName.value, '');

      // Le trajet sauvegardé précédemment reste disponible et inchangé.
      final saved = await environment.draftRepository.load(savedId!);
      expect(saved?.name, 'Trajet existant');
    });
  });

  testWidgets('« Enregistrer une copie » crée un trajet indépendant sans modifier le trajet édité', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final editor = environment.editor;
      await addTwoMarkers();
      editor.setDraftName('Original');
      await editor.saveDraft();
      final originalId = editor.currentDraftId.value!;

      await editor.saveDraftAsCopy();
      final copyId = editor.currentDraftId.value!;

      expect(copyId, isNot(equals(originalId)));
      // L'édition en cours pointe désormais vers la copie.
      expect(editor.draftName.value, 'Original (copie)');

      final original = await environment.draftRepository.load(originalId);
      final copy = await environment.draftRepository.load(copyId);
      expect(original?.name, 'Original');
      expect(copy?.name, 'Original (copie)');

      final all = await environment.draftRepository.listAll();
      expect(all.length, 2);
    });
  });
}
