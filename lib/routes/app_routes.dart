/// Noms des routes de navigation GetX de l'application.
///
/// Référence unique : les écrans et les tests ne doivent jamais écrire
/// une chaîne de route en dur — ils passent toujours par ces constantes
/// pour que la navigation reste cohérente et renommable en un seul point.
abstract final class AppRoutes {
  static const String map = '/map';
  static const String selectedMarkers = '/selected_markers';
  static const String routeLibrary = '/route_library';
}
