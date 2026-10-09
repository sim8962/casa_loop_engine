import 'package:casa_loop_engine/models/route_draft_segment_preference.dart';

/// Persistance des préférences de route entre deux repères.
abstract interface class RoutePreferenceRepository {
  Future<void> save(String startMarkerId, String endMarkerId, double value);

  Future<double?> load(String startMarkerId, String endMarkerId);

  Future<void> replaceAll(List<RouteDraftSegmentPreference> preferences);
}
