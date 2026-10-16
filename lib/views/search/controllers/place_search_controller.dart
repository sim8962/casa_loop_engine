import 'package:get/get.dart';

import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/services/repositories/place_repository.dart';
import 'package:casa_loop_engine/services/repositories/road_repository.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// État de la recherche de lieux et de routes.
///
/// La vue ne fait que saisir du texte et afficher les listes : le filtrage est
/// délégué aux repositories ObjectBox.
class PlaceSearchController extends GetxController {
  PlaceSearchController(this._placeRepository, this._roadRepository);

  final PlaceRepository _placeRepository;
  final RoadRepository _roadRepository;

  String _query = '';
  final RxList<MapMarkerItem> places = <MapMarkerItem>[].obs;
  final RxList<MapMarkerItem> roads = <MapMarkerItem>[].obs;

  @override
  void onInit() {
    super.onInit();
    Diag.event('PlaceSearchController.onInit');
    search('');
  }

  /// Réinitialise la recherche, à chaque nouvelle ouverture de l'écran.
  Future<void> reset() => Diag.future('PlaceSearchController.reset', () => search(''));

  /// Appelée à chaque frappe : callback à haute fréquence, tracé limité sauf
  /// en mode `Diag.verbose`.
  Future<void> search(String value) => Diag.frequentFuture(
    'PlaceSearchController.search',
    () async {
      _query = value;
      final results = await Future.wait([_placeRepository.search(value), _roadRepository.search(value)]);
      if (isClosed || _query != value) {
        Diag.event('PlaceSearchController.search.early', 'stale closed=$isClosed query="$_query"');
        return;
      }
      places.assignAll(results.first);
      roads.assignAll(results.last);
    },
    params: 'query="$value"',
    result: (_) => 'places=${places.length} roads=${roads.length}',
  );
}
