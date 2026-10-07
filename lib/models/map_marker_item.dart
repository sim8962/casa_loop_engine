import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Représente un résultat de recherche ou un repère validé sur la carte.
class MapMarkerItem {
  const MapMarkerItem({
    required this.id,
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.roadRef,
    this.orderIndex = 0,
  });

  final String id;
  final String name;
  final String type;
  final double latitude;
  final double longitude;
  final String? roadRef;

  /// Ordre du repère dans la liste numérotée. 0 signifie non ordonné.
  final int orderIndex;

  /// Nom générique attribué à la création d'un repère personnalisé, avant
  /// tout renommage explicite. C'est un nom stocké comme un autre : il ne
  /// sert pas de sentinelle « jamais renommé », et un utilisateur peut
  /// légitimement saisir ce même texte.
  static const String defaultPersonalizedName = 'Repère';

  /// Retourne une copie du repère avec une nouvelle position, un nouveau
  /// nom (renommage) ou un nouvel ordre, par exemple après un déplacement
  /// manuel sur la carte.
  MapMarkerItem copyWith({double? latitude, double? longitude, int? orderIndex, String? name}) =>
      Diag.frequentSync(
        'MapMarkerItem.copyWith',
        () => MapMarkerItem(
          id: id,
          name: name ?? this.name,
          type: type,
          latitude: latitude ?? this.latitude,
          longitude: longitude ?? this.longitude,
          roadRef: roadRef,
          orderIndex: orderIndex ?? this.orderIndex,
        ),
        params: 'id=$id orderIndex=${orderIndex ?? this.orderIndex}',
      );

  @override
  bool operator ==(Object other) => other is MapMarkerItem && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
