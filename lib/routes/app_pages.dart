import 'package:get/get.dart';

import 'package:casa_loop_engine/routes/app_routes.dart';
import 'package:casa_loop_engine/routes/route_library_view.dart';
import 'package:casa_loop_engine/views/map/views/map_view.dart';
import 'package:casa_loop_engine/views/selected_markers/views/selected_markers_view.dart';

/// Table de routage de [GetMaterialApp] : route initiale et déclaration des
/// écrans. Les contrôleurs sont injectés par `AppBinding` (initialBinding),
/// aucune page ne déclare de binding propre.
abstract final class AppPages {
  /// Écran affiché au démarrage : la carte.
  static const String initial = AppRoutes.map;

  static final List<GetPage<dynamic>> pages = [
    GetPage(name: AppRoutes.map, page: () => const MapView()),
    GetPage(name: AppRoutes.selectedMarkers, page: () => const SelectedMarkersView()),
    GetPage(name: AppRoutes.routeLibrary, page: () => const RouteLibraryView()),
  ];
}
