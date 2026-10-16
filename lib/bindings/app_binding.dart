import 'package:casa_loop_engine/services/repositories/objectbox_working_state_repository.dart';
import 'package:get/get.dart';

import 'package:casa_loop_engine/helpers/constants/app_config.dart';
import 'package:casa_loop_engine/models/entities/place_entity.dart';
import 'package:casa_loop_engine/models/entities/road_entity.dart';
import 'package:casa_loop_engine/services/data/places/places_data_initializer.dart';
import 'package:casa_loop_engine/services/data/roads/routes_data_initializer.dart';
import 'package:casa_loop_engine/services/map/offline_map_service.dart';
import 'package:casa_loop_engine/services/objectbox/objectbox_lifecycle.dart';
import 'package:casa_loop_engine/services/objectbox/objectbox_store.dart';
import 'package:casa_loop_engine/services/repositories/marker_repository.dart';
import 'package:casa_loop_engine/services/repositories/place_repository.dart';
import 'package:casa_loop_engine/services/repositories/road_repository.dart';
import 'package:casa_loop_engine/services/repositories/route_draft_repository.dart';
import 'package:casa_loop_engine/services/repositories/route_preference_repository.dart';
import 'package:casa_loop_engine/services/repositories/objectbox_marker_repository.dart';
import 'package:casa_loop_engine/services/repositories/objectbox_place_repository.dart';
import 'package:casa_loop_engine/services/repositories/objectbox_road_repository.dart';
import 'package:casa_loop_engine/services/repositories/objectbox_route_draft_repository.dart';
import 'package:casa_loop_engine/services/repositories/objectbox_route_preference_repository.dart';
import 'package:casa_loop_engine/services/routing/offline_routing_service.dart';
import 'package:casa_loop_engine/controllers/route_editor_controller.dart';
import 'package:casa_loop_engine/views/map/controllers/map_controller.dart';
import 'package:casa_loop_engine/views/selected_markers/controllers/selected_markers_controller.dart';
import 'package:casa_loop_engine/views/search/controllers/place_search_controller.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Initialisation globale et injection GetX centralisée.
///
/// Durées de vie choisies :
/// - repositories, store et cycle de vie ObjectBox : `permanent`, ouverts
///   avant `runApp` dans [initializeGlobalServices] ;
/// - [RouteEditorController] : `permanent`, instance unique créée au
///   démarrage — l'état de travail (sélection, réglages, brouillon) survit
///   à toute navigation et n'est jamais supprimé ;
/// - [MapController] : `lazyPut` — créé avec l'écran `/map`, route initiale
///   qui n'est jamais dépilée pendant une session ;
/// - [SelectedMarkersController] : `lazyPut(fenix: true)` — façade sans
///   état, instanciée pendant la vie de `/selected_markers`. À la
///   fermeture du GetPageRoute, SmartManagement supprime l'instance ;
///   `fenix` conserve la factory pour la recréer à la réouverture ;
/// - [PlaceSearchController] : `lazyPut` — instancié pendant le panneau
///   `showModalBottomSheet` (ModalRoute natif). Sa fermeture ne supprime
///   pas la factory (markAsDirty seulement) ; la vue appelle `reset()` à
///   chaque ouverture.
class AppBinding implements Bindings {
  static Future<void> initializeGlobalServices() =>
      Diag.future('AppBinding.initializeGlobalServices', () async {
        final (markerRepo, routePrefRepo) = await _openRepositories();
        Get.put<MarkerRepository>(markerRepo, permanent: true);
        Get.put<RoutePreferenceRepository>(routePrefRepo, permanent: true);
      });

  static Future<(MarkerRepository, RoutePreferenceRepository)> _openRepositories() async {
    final op = Diag.start('AppBinding._openRepositories');
    try {
      final objectBox = await ObjectBoxStore.open();
      final markerRepo = ObjectBoxMarkerRepository(objectBox);
      final routePrefRepo = ObjectBoxRoutePreferenceRepository(objectBox);
      final draftRepo = ObjectBoxRouteDraftRepository(objectBox);
      final placeBox = objectBox.store.box<PlaceEntity>();
      final placeRepo = ObjectBoxPlaceRepository(objectBox);
      final placesInitializer = PlacesDataInitializer(placeBox);
      final roadBox = objectBox.store.box<RoadEntity>();
      final roadRepo = ObjectBoxRoadRepository(objectBox);
      final routesInitializer = RoutesDataInitializer(roadBox);

      await placesInitializer.initialize();
      await routesInitializer.initialize();

      Get.put(ObjectBoxWorkingStateRepository(objectBox), permanent: true);
      Get.put(ObjectBoxLifecycle(objectBox)..listen(), permanent: true);
      Get.put<RouteDraftRepository>(draftRepo, permanent: true);
      Get.put<PlaceRepository>(placeRepo, permanent: true);
      Get.put<RoadRepository>(roadRepo, permanent: true);

      op.end('repositories=objectbox');
      return (markerRepo, routePrefRepo);
    } catch (exception, stack) {
      op.fail(exception, stack);
      rethrow;
    }
  }

  @override
  void dependencies() {
    Diag.event('AppBinding.dependencies');
    Get.lazyPut<OfflineMapService>(
      () => Diag.sync(
        'AppBinding.create OfflineMapService',
        () => OfflineMapService(sourcePath: AppConfig.mbtilesSourcePath),
      ),
    );
    Get.lazyPut<OfflineRoutingService>(
      () => Diag.sync('AppBinding.create OfflineRoutingService', () => OfflineRoutingService()),
    );
    Get.put<RouteEditorController>(
      Diag.sync(
        'AppBinding.create RouteEditorController',
        () => RouteEditorController(Get.find<MarkerRepository>(), Get.find<RoutePreferenceRepository>()),
      ),
      permanent: true,
    );
    Get.lazyPut<MapController>(
      () => Diag.sync(
        'AppBinding.create MapController',
        () => MapController(Get.find<OfflineMapService>(), Get.find<RouteEditorController>()),
      ),
    );
    Get.lazyPut<SelectedMarkersController>(
      () => Diag.sync(
        'AppBinding.create SelectedMarkersController',
        () => SelectedMarkersController(Get.find<RouteEditorController>()),
      ),
      fenix: true,
    );
    Get.lazyPut<PlaceSearchController>(
      () => Diag.sync(
        'AppBinding.create PlaceSearchController',
        () => PlaceSearchController(Get.find<PlaceRepository>(), Get.find<RoadRepository>()),
      ),
    );
  }
}
