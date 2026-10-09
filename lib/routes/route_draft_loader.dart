import 'package:get/get.dart';

import 'package:casa_loop_engine/routes/app_routes.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Ouvre la bibliothèque des trajets sauvegardés ([RouteLibraryView]).
/// Point d'entrée partagé pour ne jamais dupliquer la navigation entre les
/// écrans qui exposent l'accès à la bibliothèque.
///
/// [origin] identifie l'écran à l'origine du clic dans les traces Diag.
void openRouteLibrary({required String origin}) {
  Diag.event('Ui.tap', 'target=openRouteLibrary origin=$origin');
  Get.toNamed(AppRoutes.routeLibrary);
}
