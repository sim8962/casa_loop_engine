import 'dart:convert';

import 'package:casa_loop_engine/objectbox.g.dart';

import 'package:casa_loop_engine/models/entities/place_entity.dart';
import 'package:casa_loop_engine/models/imports/place_import_item.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

enum PlacesImportErrorType { invalidJson, invalidRoot, invalidEntry }

class PlacesImportException implements Exception {
  const PlacesImportException(this.type, this.message);

  final PlacesImportErrorType type;
  final String message;

  @override
  String toString() => 'PlacesImportException($type): $message';
}

class PlacesImportService {
  PlacesImportService(this.placeBox);

  final Box<PlaceEntity> placeBox;

  Future<void> importFromString(String jsonString, {required String dataVersion}) =>
      Diag.future('PlacesImportService.importFromString', () async {
        final entities = _parseEntities(jsonString, dataVersion: dataVersion);
        placeBox.putMany(entities);
      }, params: 'jsonBytes=${jsonString.length} version=$dataVersion');

  static List<PlaceEntity> _parseEntities(String jsonString, {required String dataVersion}) => Diag.sync(
    'PlacesImportService.parseEntities',
    () {
      final Object? decoded;
      try {
        decoded = jsonDecode(jsonString);
      } on FormatException catch (e) {
        throw PlacesImportException(PlacesImportErrorType.invalidJson, 'JSON invalide: ${e.message}');
      }

      if (decoded is! List<dynamic>) {
        throw const PlacesImportException(
          PlacesImportErrorType.invalidRoot,
          'La racine JSON doit être une liste',
        );
      }

      final entities = <PlaceEntity>[];
      final errors = <String>[];

      for (var i = 0; i < decoded.length; i++) {
        final raw = decoded[i];
        if (raw is! Map<String, dynamic>) {
          errors.add('Élément $i : doit être un objet JSON');
          continue;
        }
        try {
          final item = PlaceImportItem.fromJson(raw);
          _validateCoordinates(item);
          entities.add(item.toEntity(dataVersion: dataVersion));
        } on FormatException catch (e) {
          errors.add('Élément $i : ${e.message}');
        } on TypeError {
          errors.add('Élément $i : type numérique invalide');
        }
      }

      if (errors.isNotEmpty) {
        throw PlacesImportException(PlacesImportErrorType.invalidEntry, errors.join('; '));
      }

      return entities;
    },
    params: 'jsonBytes=${jsonString.length}',
    result: (entities) => 'parsed=${entities.length}',
  );

  static void _validateCoordinates(PlaceImportItem item) =>
      Diag.frequentSync('PlacesImportService._validateCoordinates', () {
        if (item.latitude < -90 || item.latitude > 90 || item.latitude.isNaN) {
          throw FormatException('latitude invalide pour ${item.osmId} : ${item.latitude}');
        }
        if (item.longitude < -180 || item.longitude > 180 || item.longitude.isNaN) {
          throw FormatException('longitude invalide pour ${item.osmId} : ${item.longitude}');
        }
      }, params: 'osmId=${item.osmId}');
}
