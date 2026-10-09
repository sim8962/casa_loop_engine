import 'package:flutter_test/flutter_test.dart';

import 'package:casa_loop_engine/controllers/route_editor_controller.dart';

void main() {
  group('RouteEditorController.defaultDraftName', () {
    test('formate mois/jour/heure/minute sur deux chiffres chacun', () {
      expect(RouteEditorController.defaultDraftName(DateTime(2026, 10, 6, 14, 37)), 'trajet-10061437');
    });

    test('ajoute un zéro de tête pour les valeurs à un chiffre', () {
      expect(RouteEditorController.defaultDraftName(DateTime(2026, 1, 2, 3, 4)), 'trajet-01020304');
    });

    test('est stable : ne dépend que de la date de création fournie', () {
      final createdAt = DateTime(2026, 10, 6, 14, 37);
      final first = RouteEditorController.defaultDraftName(createdAt);
      final second = RouteEditorController.defaultDraftName(createdAt);
      expect(first, second);
    });
  });
}
