import 'package:flutter/services.dart';

import 'package:casa_loop_engine/models/entities/place_entity.dart';
import 'package:casa_loop_engine/objectbox.g.dart';

import 'package:casa_loop_engine/services/data/places/places_import_service.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Initialise le dataset Places dans ObjectBox au démarrage.
///
/// L'import n'est exécuté que si aucune localité de la version attendue n'est
/// déjà présente. Une version différente déclenche un nouvel import : les
/// entités avec le même `osmId` sont remplacées, les anciennes versions restent
/// en base jusqu'à un nettoyage éventuel.
class PlacesDataInitializer {
  PlacesDataInitializer(this._placeBox);

  static const String _assetPath = 'assets/data/places.json';
  static const String _dataVersion = '2026.08.22-casa-trail-places-v1';

  final Box<PlaceEntity> _placeBox;

  /// Renvoie `true` si au moins une localité de la version attendue existe.
  bool isCurrentVersionInStore() => Diag.sync(
    'PlacesDataInitializer.isCurrentVersionInStore',
    () {
      final query = _placeBox.query(PlaceEntity_.dataVersion.equals(_dataVersion)).build();
      try {
        return query.findFirst() != null;
      } finally {
        query.close();
      }
    },
    params: 'version=$_dataVersion',
    result: (found) => 'found=$found',
  );

  /// Importe le dataset depuis l'asset s'il n'est pas déjà à jour.
  Future<void> initialize() => Diag.future('PlacesDataInitializer.initialize', () async {
    if (isCurrentVersionInStore()) {
      Diag.event('PlacesDataInitializer.initialize.upToDate');
      return;
    }

    final jsonString = await rootBundle.loadString(_assetPath);
    final service = PlacesImportService(_placeBox);
    await service.importFromString(jsonString, dataVersion: _dataVersion);
  }, params: 'asset=$_assetPath');
}
