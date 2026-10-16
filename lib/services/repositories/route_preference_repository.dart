/// Persistance des préférences de route entre deux repères.
abstract interface class RoutePreferenceRepository {
  Future<double?> load(String startMarkerId, String endMarkerId);
}
