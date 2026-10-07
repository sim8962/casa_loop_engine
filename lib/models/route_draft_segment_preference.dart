/// Préférence de route persistée dans un brouillon de trajet.
class RouteDraftSegmentPreference {
  const RouteDraftSegmentPreference({
    required this.startMarkerId,
    required this.endMarkerId,
    required this.value,
    this.color,
  });

  final String startMarkerId;
  final String endMarkerId;
  final double value;

  /// Couleur du tracé pour ce couple dirigé (`startMarkerId` → `endMarkerId`),
  /// en notation hexadécimale `#RRGGBB`. `null` tant que l'utilisateur n'a
  /// jamais choisi de couleur pour ce segment : [SegmentColors.resolve]
  /// retombe alors sur [SegmentColors.defaultColor].
  final String? color;
}

/// Palette et résolution des couleurs de segment, partagées entre le
/// sélecteur de couleur de l'éditeur et le rendu de la carte.
abstract final class SegmentColors {
  /// Couleur utilisée quand aucune couleur valide n'est enregistrée pour un
  /// segment : identique à l'ancienne couleur fixe du tracé, pour ne pas
  /// changer l'apparence des trajets existants non personnalisés.
  static const String defaultColor = '#D81B60';

  /// Petite palette de couleurs contrastées proposée dans le sélecteur.
  static const List<String> palette = [defaultColor, '#1E88E5', '#2E7D32', '#F57C00', '#6A1B9A', '#00838F'];

  static final RegExp _hexPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');

  /// `true` si [value] est une couleur hexadécimale `#RRGGBB` valide.
  static bool isValid(String? value) => value != null && _hexPattern.hasMatch(value);

  /// Couleur effective pour [value] : [value] lui-même s'il est valide,
  /// sinon [defaultColor]. Couvre à la fois l'absence de couleur
  /// enregistrée et une valeur corrompue ou invalide.
  static String resolve(String? value) => isValid(value) ? value! : defaultColor;
}
