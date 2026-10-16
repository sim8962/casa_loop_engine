import 'package:get/get.dart';

import 'package:casa_loop_engine/controllers/route_editor_controller.dart';
import 'package:casa_loop_engine/models/computed_route.dart';
import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/views/map/controllers/map_controller.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Interactions propres à l'écran « Repères choisis ».
///
/// Ne détient aucun état réactif propre : la même instance unique de
/// [RouteEditorController] que celle utilisée par l'écran carte est exposée
/// ici sous forme de délégations, pour que la vue ne lise jamais
/// `controller` ailleurs. Seul le recentrage passe par [MapController],
/// résolu à la demande et tolérant à son absence (écran ouvert sans carte,
/// ou tests).
class SelectedMarkersController extends GetxController {
  SelectedMarkersController(this._editor);

  static SelectedMarkersController get instance => Get.find<SelectedMarkersController>();

  /// Instance partagée unique, injectée par le binding : identique à celle
  /// utilisée par [MapController]. Aucun état réactif n'est dupliqué.
  final RouteEditorController _editor;

  RxList<MapMarkerItem> get validatedMarkers => _editor.validatedMarkers;
  RxList<double> get segmentRoutePreferences => _editor.segmentRoutePreferences;
  RxString get loopSummary => _editor.loopSummary;
  RxnDouble get targetDistanceKm => _editor.targetDistanceKm;
  RxnDouble get targetDurationHours => _editor.targetDurationHours;
  Rx<LoopTargetMode> get loopTargetMode => _editor.loopTargetMode;
  RxInt get draftRestoreVersion => _editor.draftRestoreVersion;
  RxBool get isSavingDraft => _editor.isSavingDraft;
  RxBool get isTracing => _editor.isTracing;
  RxnString get traceError => _editor.traceError;
  Rxn<ComputedItinerary> get tracedItinerary => _editor.tracedItinerary;
  bool get mutationsBlocked => _editor.mutationsBlocked;

  /// Nom affiché pour le trajet en cours d'édition : le nom personnalisé,
  /// ou à défaut le nom par défaut stable dérivé de sa création.
  String get displayDraftName => _editor.displayDraftName;

  String markerDisplayName(int index) => _editor.markerDisplayName(index);
  String roadPreferenceLabel(double value) => _editor.roadPreferenceLabel(value);

  /// Palette proposée par le sélecteur de couleur de segment.
  List<String> get segmentColorPalette => _editor.segmentColorPalette;

  /// Couleur effective du segment d'index [segmentIndex] (couple dirigé),
  /// résolue en couleur par défaut si aucune n'a été choisie ou si la
  /// valeur enregistrée est invalide.
  String colorForSegment(int segmentIndex) => _editor.colorForSegment(segmentIndex);

  /// Choisit la couleur du segment d'index [segmentIndex] ; n'appelle
  /// jamais le moteur de calcul.
  void setSegmentColor(int segmentIndex, String colorHex) => _editor.setSegmentColor(segmentIndex, colorHex);

  void setRoutePreference(int segmentIndex, double value) => _editor.setRoutePreference(segmentIndex, value);
  void setLoopTargetMode(LoopTargetMode mode) => _editor.setLoopTargetMode(mode);
  void setTargetDistanceKm(double? value) => _editor.setTargetDistanceKm(value);
  void setTargetDurationHours(double? value) => _editor.setTargetDurationHours(value);
  void setDraftName(String value) => _editor.setDraftName(value);

  Future<void> flushWorkingState() => _editor.flushWorkingState();
  Future<void> saveDraft() => _editor.saveDraft();
  Future<void> saveDraftAsCopy({String? name}) => _editor.saveDraftAsCopy(name: name);
  Future<void> newDraft({bool discardUnsavedResult = false}) =>
      _editor.newDraft(discardUnsavedResult: discardUnsavedResult);
  Future<void> traceRoute() => _editor.traceRoute();

  /// Recentre la carte sur [marker] si un [MapController] est enregistré ;
  /// sans effet sinon (la carte n'existe pas encore, ou test sans carte).
  Future<void> centerOnMarker(MapMarkerItem marker) {
    if (!Get.isRegistered<MapController>()) {
      Diag.event('SelectedMarkersController.centerOnMarker.early', 'noController');
      return Future<void>.value();
    }
    return MapController.instance.centerOn(marker);
  }
}
