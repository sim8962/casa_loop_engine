import 'package:objectbox/objectbox.dart';

import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Repère validé, persisté localement.
@Entity()
class MarkerEntity {
  MarkerEntity({
    this.id = 0,
    required this.markerId,
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.roadRef,
    this.orderIndex = 0,
  });

  factory MarkerEntity.fromModel(MapMarkerItem marker) => Diag.frequentSync(
    'MarkerEntity.fromModel',
    () => MarkerEntity(
      id: 0,
      markerId: marker.id,
      name: marker.name,
      type: marker.type,
      latitude: marker.latitude,
      longitude: marker.longitude,
      roadRef: marker.roadRef,
      orderIndex: marker.orderIndex,
    ),
    params: 'markerId=${marker.id}',
  );

  @Id()
  int id;

  /// Identifiant métier du repère, stable entre les sessions.
  @Unique(onConflict: ConflictStrategy.replace)
  String markerId;

  String name;
  String type;
  double latitude;
  double longitude;
  String? roadRef;

  /// Ordre du repère dans la liste numérotée. 0 signifie non ordonné.
  int orderIndex;

  MapMarkerItem toModel() => Diag.frequentSync(
    'MarkerEntity.toModel',
    () => MapMarkerItem(
      id: markerId,
      name: name,
      type: type,
      latitude: latitude,
      longitude: longitude,
      roadRef: roadRef,
      orderIndex: orderIndex,
    ),
    params: 'markerId=$markerId',
  );
}
