import 'dart:convert';

import 'package:casa_loop_engine/models/entities/place_entity.dart';
import 'package:casa_loop_engine/services/search/place_search_key_service.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Représentation légère d'une localité telle qu'elle arrivera depuis
/// `places.json`, avant son stockage ObjectBox.
class PlaceImportItem {
  PlaceImportItem({
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
    this.dataVersion,
  });

  factory PlaceImportItem.fromJson(Map<String, dynamic> json) => Diag.frequentSync(
    'PlaceImportItem.fromJson',
    () {
      final osmIdRaw = json['osmId'];
      if (osmIdRaw == null) {
        throw FormatException('osmId est requis', json);
      }

      final nameRaw = json['name'];
      if (nameRaw == null) {
        throw FormatException('name est requis', json);
      }

      final latRaw = json['latitude'];
      final lonRaw = json['longitude'];
      if (latRaw == null || lonRaw == null) {
        throw FormatException('latitude et longitude sont requises', json);
      }

      final alternativeRaw = json['alternativeNames'] as List<dynamic>?;

      return PlaceImportItem(
        osmId: osmIdRaw.toString(),
        name: nameRaw.toString(),
        nameFr: json['nameFr']?.toString(),
        nameAr: json['nameAr']?.toString(),
        nameZgh: json['nameZgh']?.toString(),
        alternativeNames: alternativeRaw?.map((value) => value.toString()).toList(),
        placeType: json['placeType']?.toString(),
        latitude: (latRaw as num).toDouble(),
        longitude: (lonRaw as num).toDouble(),
        importance: (json['importance'] as num?)?.toDouble(),
        population: (json['population'] as num?)?.toInt(),
        dataVersion: json['dataVersion']?.toString(),
      );
    },
    params: 'fields=${json.keys.length}',
    result: (item) => 'osmId=${item.osmId}',
  );

  final String osmId;
  final String name;
  final String? nameFr;
  final String? nameAr;
  final String? nameZgh;
  final List<String>? alternativeNames;
  final String? placeType;
  final double latitude;
  final double longitude;
  final double? importance;
  final int? population;
  final String? dataVersion;

  PlaceEntity toEntity() => Diag.frequentSync(
    'PlaceImportItem.toEntity',
    () => PlaceEntity(
      osmId: osmId,
      name: name,
      nameFr: nameFr,
      nameAr: nameAr,
      nameZgh: nameZgh,
      alternativeNames: alternativeNames == null ? null : jsonEncode(alternativeNames),
      placeType: placeType,
      latitude: latitude,
      longitude: longitude,
      importance: importance,
      population: population,
      searchKey: PlaceSearchKeyService.build(
        name: name,
        nameFr: nameFr,
        nameAr: nameAr,
        nameZgh: nameZgh,
        alternativeNames: alternativeNames,
      ),
      dataVersion: dataVersion,
    ),
    params: 'osmId=$osmId',
  );
}
