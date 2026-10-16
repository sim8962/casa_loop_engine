import 'dart:convert';

import 'package:casa_loop_engine/objectbox.g.dart';

import 'package:casa_loop_engine/models/entities/road_entity.dart';
import 'package:casa_loop_engine/models/imports/road_import_item.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

enum RoutesImportErrorType { invalidJson, invalidRoot, invalidEntry }

class RoutesImportException implements Exception {
  const RoutesImportException(this.type, this.message);

  final RoutesImportErrorType type;
  final String message;

  @override
  String toString() => 'RoutesImportException($type): $message';
}

class RoutesImportService {
  RoutesImportService(this.roadBox);

  final Box<RoadEntity> roadBox;

  Future<void> importFromString(String jsonString, {required String dataVersion}) =>
      Diag.future('RoutesImportService.importFromString', () async {
        final entities = _parseEntities(jsonString, dataVersion: dataVersion);
        roadBox.putMany(entities);
      }, params: 'jsonBytes=${jsonString.length} version=$dataVersion');

  static List<RoadEntity> _parseEntities(String jsonString, {required String dataVersion}) => Diag.sync(
    'RoutesImportService.parseEntities',
    () {
      final Object? decoded;
      try {
        decoded = jsonDecode(jsonString);
      } on FormatException catch (e) {
        throw RoutesImportException(RoutesImportErrorType.invalidJson, 'JSON invalide: ${e.message}');
      }

      if (decoded is! List<dynamic>) {
        throw const RoutesImportException(
          RoutesImportErrorType.invalidRoot,
          'La racine JSON doit être une liste',
        );
      }

      final entities = <RoadEntity>[];
      final errors = <String>[];

      for (var i = 0; i < decoded.length; i++) {
        final raw = decoded[i];
        if (raw is! Map<String, dynamic>) {
          errors.add('Élément $i : doit être un objet JSON');
          continue;
        }
        try {
          final item = RoadImportItem.fromJson(raw);
          _validateCoordinates(item);
          entities.add(item.toEntity(dataVersion: dataVersion));
        } on FormatException catch (e) {
          errors.add('Élément $i : ${e.message}');
        } on TypeError {
          errors.add('Élément $i : type numérique invalide');
        }
      }

      if (errors.isNotEmpty) {
        throw RoutesImportException(RoutesImportErrorType.invalidEntry, errors.join('; '));
      }

      return entities;
    },
    params: 'jsonBytes=${jsonString.length}',
    result: (entities) => 'parsed=${entities.length}',
  );

  static void _validateCoordinates(RoadImportItem item) =>
      Diag.frequentSync('RoutesImportService._validateCoordinates', () {
        if (item.latitude < -90 || item.latitude > 90 || item.latitude.isNaN) {
          throw FormatException('latitude invalide pour ${item.reference} : ${item.latitude}');
        }
        if (item.longitude < -180 || item.longitude > 180 || item.longitude.isNaN) {
          throw FormatException('longitude invalide pour ${item.reference} : ${item.longitude}');
        }
      }, params: 'reference=${item.reference}');
}
