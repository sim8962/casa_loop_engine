import 'package:objectbox/objectbox.dart';

import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Route numérotée (RN, RR, RP) stockée dans ObjectBox.
@Entity()
class RoadEntity {
  RoadEntity({
    this.id = 0,
    required this.reference,
    required this.normalizedReference,
    required this.roadClass,
    this.name,
    this.nameFr,
    this.nameAr,
    this.nameZgh,
    this.alternativeNames,
    required this.latitude,
    required this.longitude,
    this.searchKey,
    this.dataVersion,
  });

  @Id()
  int id;

  /// Référence canonique, par exemple `RN1`.
  @Unique(onConflict: ConflictStrategy.replace)
  String reference;

  /// Référence en minuscules, utilisée pour la recherche.
  @Index()
  String normalizedReference;

  /// `Route nationale`, `Route régionale` ou `Route provinciale`.
  String roadClass;

  String? name;
  String? nameFr;
  String? nameAr;
  String? nameZgh;

  /// Noms alternatifs encodés en JSON.
  String? alternativeNames;

  double latitude;
  double longitude;

  /// Clé de recherche normalisée (noms + références + aliases).
  @Index()
  String? searchKey;

  String? dataVersion;

  MapMarkerItem toMapMarker() => Diag.frequentSync(
    'RoadEntity.toMapMarker',
    () => MapMarkerItem(
      id: reference,
      name: reference,
      type: roadClass,
      latitude: latitude,
      longitude: longitude,
      roadRef: reference,
    ),
    params: 'reference=$reference',
  );
}
