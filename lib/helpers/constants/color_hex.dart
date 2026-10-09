/// Couleurs de l'application en notation hexadécimale.
///
/// Volontairement sans dépendance Flutter : ces valeurs sont consommées à la
/// fois par la couche UI (via `AppColors`) et par la couche données, où le
/// style MapLibre et les annotations attendent des chaînes hexadécimales.
abstract final class ColorHex {
  static const String canvas = '#F8F8F5';
  static const String pendingMarker = '#FF9800';
  static const String validatedMarker = '#673AB7';
  static const String markerStroke = '#FFFFFF';
}
