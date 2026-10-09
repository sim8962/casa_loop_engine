import 'package:objectbox/objectbox.dart';

@Entity()
class PlaceEntity {
  PlaceEntity({
    this.id = 0,
    required this.osmId,
    required this.name,
    this.nameFr,
    this.nameAr,
    this.nameZgh,
    this.alternativeNames,
    this.placeType,
    required this.latitude,
    required this.longitude,
    this.importance,
    this.population,
    this.searchKey,
    this.dataVersion,
  });

  @Id()
  int id;

  @Unique(onConflict: ConflictStrategy.replace)
  String osmId;

  String name;
  String? nameFr;
  String? nameAr;
  String? nameZgh;

  String? alternativeNames;

  String? placeType;

  double latitude;
  double longitude;

  double? importance;
  int? population;

  @Index()
  String? searchKey;

  String? dataVersion;
}
