import 'dart:convert';
import 'dart:io';

import 'package:casa_loop_engine/objectbox.g.dart';

import 'package:casa_loop_engine/models/entities/place_entity.dart';
import 'package:casa_loop_engine/models/imports/place_import_item.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

enum PlacesImportErrorType { missingFile, invalidJson, invalidRoot, invalidEntry }

class PlacesImportException implements Exception {
  const PlacesImportException(this.type, this.message);

  final PlacesImportErrorType type;
  final String message;

  @override
  String toString() => 'PlacesImportException($type): $message';
}

class PlacesImportResult {
  const PlacesImportResult({required this.importedCount, this.dataVersion});

  final int importedCount;
  final String? dataVersion;
}

class PlacesImportService {
  PlacesImportService(this.placeBox);

  final Box<PlaceEntity> placeBox;

  Future<PlacesImportResult> importFromFile(String filePath, {String? dataVersion}) => Diag.future(
    'PlacesImportService.importFromFile',
    () async {
      final file = File(filePath);
      if (!await file.exists()) {
        throw const PlacesImportException(PlacesImportErrorType.missingFile, 'Fichier non trouvé');
      }
      final jsonString = await file.readAsString();
      return importFromString(jsonString, dataVersion: dataVersion);
    },
    params: 'path=$filePath',
    result: (r) => 'imported=${r.importedCount} version=${r.dataVersion}',
  );

  Future<PlacesImportResult> importFromString(String jsonString, {String? dataVersion}) => Diag.future(
    'PlacesImportService.importFromString',
    () async {
      final entities = parseEntities(jsonString, dataVersion: dataVersion);
      placeBox.putMany(entities);

      return PlacesImportResult(
        importedCount: entities.length,
        dataVersion: dataVersion ?? _commonDataVersion(entities),
      );
    },
    params: 'jsonBytes=${jsonString.length}',
    result: (r) => 'imported=${r.importedCount} version=${r.dataVersion}',
  );

  static List<PlaceEntity> parseEntities(String jsonString, {String? dataVersion}) => Diag.sync(
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

  static String? _commonDataVersion(List<PlaceEntity> entities) =>
      Diag.sync('PlacesImportService._commonDataVersion', () {
        if (entities.isEmpty) return null;
        final versions = entities.map((e) => e.dataVersion).toSet();
        if (versions.length == 1) return versions.single;
        return null;
      }, params: 'entities=${entities.length}');
}
