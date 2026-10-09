import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:casa_loop_engine/routes/route_library_view.dart';
import 'package:casa_loop_engine/controllers/route_editor_controller.dart';
import 'package:casa_loop_engine/routes/app_routes.dart';
import 'package:casa_loop_engine/views/map/widgets/map_load_draft_button.dart';
import 'package:casa_loop_engine/views/selected_markers/views/selected_markers_view.dart';

const testMapRoute = '/test-map';

/// Application minimale pour les tests de la bibliothèque des trajets :
/// un écran « carte » réduit au seul [MapLoadDraftButton], la vraie
/// [RouteLibraryView] et le vrai [SelectedMarkersView], câblés sur les
/// mêmes routes nommées que l'application ([AppRoutes]). Évite toute
/// dépendance à `MapLibreMap` (plugin natif indisponible en test).
Future<void> pumpRouteLibraryTestApp(WidgetTester tester, RouteEditorController editor) async {
  await tester.pumpWidget(
    GetMaterialApp(
      initialRoute: testMapRoute,
      getPages: [
        GetPage(
          name: testMapRoute,
          page: () => Scaffold(
            body: Center(child: MapLoadDraftButton(controller: editor)),
          ),
        ),
        GetPage(name: AppRoutes.routeLibrary, page: () => const RouteLibraryView()),
        GetPage(name: AppRoutes.selectedMarkers, page: () => const SelectedMarkersView()),
      ],
    ),
  );
  await tester.pumpAndSettle();
}
