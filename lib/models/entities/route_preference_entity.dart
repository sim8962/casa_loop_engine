import 'package:objectbox/objectbox.dart';

/// Préférence de route (en %) entre deux repères consécutifs validés.
@Entity()
class RoutePreferenceEntity {
  RoutePreferenceEntity({
    this.id = 0,
    required this.startMarkerId,
    required this.endMarkerId,
    required this.value,
  });

  @Id()
  int id;

  /// Identifiant métier du repère de départ.
  @Index()
  String startMarkerId;

  /// Identifiant métier du repère d'arrivée.
  @Index()
  String endMarkerId;

  /// Pourcentage de 0 (autoroute/national) à 100 (non classée/piste).
  double value;
}
