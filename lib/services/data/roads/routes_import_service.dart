import 'dart:convert';
import 'dart:io';

import 'package:casa_loop_engine/objectbox.g.dart';

import 'package:casa_loop_engine/models/entities/road_entity.dart';
import 'package:casa_loop_engine/models/imports/road_import_item.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

enum RoutesImportErrorType { missingFile, invalidJson, invalidRoot, invalidEntry }

class RoutesImportException implements Exception {
  const RoutesImportException(this.type, this.message);

  final RoutesImportErrorType type;
  final String message;

  @override
  String toString() => 'RoutesImportException($type): $message';
}

class RoutesImportResult {
  const RoutesImportResult({required this.importedCount, this.dataVersion});

  final int importedCount;
  final String? dataVersion;
}

class RoutesImportService {
  RoutesImportService(this.roadBox);

  final Box<RoadEntity> roadBox;

  Future<RoutesImportResult> importFromFile(String filePath, {String? dataVersion}) => Diag.future(
    'RoutesImportService.importFromFile',
    () async {
      final file = File(filePath);
      if (!await file.exists()) {
        throw const RoutesImportException(RoutesImportErrorType.missingFile, 'Fichier non trouvé');
      }
      final jsonString = await file.readAsString();
      return importFromString(jsonString, dataVersion: dataVersion);
    },
    params: 'path=$filePath',
    result: (r) => 'imported=${r.importedCount} version=${r.dataVersion}',
  );

  Future<RoutesImportResult> importFromString(String jsonString, {String? dataVersion}) => Diag.future(
    'RoutesImportService.importFromString',
    () async {
      final entities = parseEntities(jsonString, dataVersion: dataVersion);
      roadBox.putMany(entities);

      return RoutesImportResult(
        importedCount: entities.length,
        dataVersion: dataVersion ?? _commonDataVersion(entities),
      );
    },
    params: 'jsonBytes=${jsonString.length}',
    result: (r) => 'imported=${r.importedCount} version=${r.dataVersion}',
  );

  static List<RoadEntity> parseEntities(String jsonString, {String? dataVersion}) => Diag.sync(
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
          final entity = item.toEntity();
          if (dataVersion != null) {
            entity.dataVersion = dataVersion;
          }
          entities.add(entity);
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

  static String? _commonDataVersion(List<RoadEntity> entities) =>
      Diag.sync('RoutesImportService._commonDataVersion', () {
        if (entities.isEmpty) return null;
        final versions = entities.map((e) => e.dataVersion).toSet();
        if (versions.length == 1) return versions.single;
        return null;
      }, params: 'entities=${entities.length}');
}
