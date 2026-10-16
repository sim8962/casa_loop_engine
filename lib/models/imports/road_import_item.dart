import 'dart:convert';

import 'package:casa_loop_engine/models/entities/road_entity.dart';
import 'package:casa_loop_engine/services/search/road_search_key_service.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Représentation légère d'une route telle qu'elle arrive depuis
/// `routes.json`, avant son stockage ObjectBox.
class RoadImportItem {
  RoadImportItem({
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
  });

  factory RoadImportItem.fromJson(Map<String, dynamic> json) => Diag.frequentSync(
    'RoadImportItem.fromJson',
    () {
      final referenceRaw = json['reference'];
      if (referenceRaw == null) {
        throw FormatException('reference est requise', json);
      }

      final latRaw = json['latitude'];
      final lonRaw = json['longitude'];
      if (latRaw == null || lonRaw == null) {
        throw FormatException('latitude et longitude sont requises', json);
      }

      final alternativeRaw = json['alternativeNames'] as List<dynamic>?;
      final reference = referenceRaw.toString();

      return RoadImportItem(
        reference: reference,
        normalizedReference: (json['normalizedReference'] as String? ?? reference.toLowerCase()).toString(),
        roadClass: (json['roadClass'] ?? 'Route').toString(),
        name: json['name']?.toString(),
        nameFr: json['nameFr']?.toString(),
        nameAr: json['nameAr']?.toString(),
        nameZgh: json['nameZgh']?.toString(),
        alternativeNames: alternativeRaw?.map((value) => value.toString()).toList(),
        latitude: (latRaw as num).toDouble(),
        longitude: (lonRaw as num).toDouble(),
      );
    },
    params: 'fields=${json.keys.length}',
    result: (item) => 'reference=${item.reference}',
  );

  final String reference;
  final String normalizedReference;
  final String roadClass;
  final String? name;
  final String? nameFr;
  final String? nameAr;
  final String? nameZgh;
  final List<String>? alternativeNames;
  final double latitude;
  final double longitude;

  RoadEntity toEntity({required String dataVersion}) => Diag.frequentSync(
    'RoadImportItem.toEntity',
    () => RoadEntity(
      reference: reference,
      normalizedReference: normalizedReference,
      roadClass: roadClass,
      name: name,
      nameFr: nameFr,
      nameAr: nameAr,
      nameZgh: nameZgh,
      alternativeNames: alternativeNames == null ? null : jsonEncode(alternativeNames),
      latitude: latitude,
      longitude: longitude,
      searchKey: RoadSearchKeyService.build(
        reference: reference,
        normalizedReference: normalizedReference,
        roadClass: roadClass,
        name: name,
        nameFr: nameFr,
        nameAr: nameAr,
        nameZgh: nameZgh,
        alternativeNames: alternativeNames,
      ),
      dataVersion: dataVersion,
    ),
    params: 'reference=$reference',
  );
}
