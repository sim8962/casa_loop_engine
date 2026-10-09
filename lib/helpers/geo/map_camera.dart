import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Contraintes de caméra dérivées de l'emprise réelle du MBTiles V4.
///
/// Ces valeurs sont validées avec le pack cartographique en place : les
/// modifier revient à changer la zone navigable et le cadrage de la carte.
abstract final class MapCamera {
  static const double west = -9.51416015625;
  static const double south = 31.87755764334002;
  static const double east = -4.119873046875;
  static const double north = 34.25267611710151;

  static const double minZoom = 7;
  static const double maxZoom = 15;
  static const double initialZoom = 12;

  /// Emprise de contenu utilisée pour le cadrage et la navigation.
  static final LatLngBounds contentBounds = LatLngBounds(
    southwest: const LatLng(south, west),
    northeast: const LatLng(north, east),
  );

  static final LatLng contentCenter = LatLng(
    (contentBounds.southwest.latitude + contentBounds.northeast.latitude) / 2,
    (contentBounds.southwest.longitude + contentBounds.northeast.longitude) / 2,
  );

  static double clampZoom(double currentZoom, double delta) => Diag.frequentSync(
    'MapCamera.clampZoom',
    () => (currentZoom + delta).clamp(minZoom, maxZoom).toDouble(),
    params: 'zoom=$currentZoom delta=$delta',
    result: (zoom) => 'clamped=$zoom',
  );
}
