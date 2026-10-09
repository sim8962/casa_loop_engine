import 'package:flutter/services.dart';

import 'package:casa_loop_engine/models/entities/road_entity.dart';
import 'package:casa_loop_engine/objectbox.g.dart';

import 'package:casa_loop_engine/services/data/roads/routes_import_service.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Initialise le dataset Routes dans ObjectBox au démarrage.
///
/// L'import n'est exécuté que si aucune route de la version attendue n'est
/// déjà présente. Une version différente déclenche un nouvel import : les
/// entités avec la même `reference` sont remplacées, les anciennes versions
/// restent en base jusqu'à un nettoyage éventuel.
class RoutesDataInitializer {
  RoutesDataInitializer(this._roadBox);

  static const String _assetPath = 'assets/data/routes.json';
  static const String _dataVersion = '2026.08.22-casa-trail-routes-v1';

  final Box<RoadEntity> _roadBox;

  /// Renvoie `true` si au moins une route de la version attendue existe.
  bool isCurrentVersionInStore() => Diag.sync(
    'RoutesDataInitializer.isCurrentVersionInStore',
    () {
      final query = _roadBox.query(RoadEntity_.dataVersion.equals(_dataVersion)).build();
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
  ///
  /// [assetJson] est réservé aux tests ; en production la méthode lit
  /// automatiquement `rootBundle`.
  Future<RoutesImportResult> initialize({String? assetJson}) => Diag.future(
    'RoutesDataInitializer.initialize',
    () async {
      if (isCurrentVersionInStore()) {
        Diag.event('RoutesDataInitializer.initialize.upToDate');
        return const RoutesImportResult(importedCount: 0, dataVersion: _dataVersion);
      }

      final jsonString = assetJson ?? await rootBundle.loadString(_assetPath);
      final service = RoutesImportService(_roadBox);
      return service.importFromString(jsonString, dataVersion: _dataVersion);
    },
    params: 'asset=$_assetPath injectedJson=${assetJson != null}',
    result: (r) => 'imported=${r.importedCount} version=${r.dataVersion}',
  );
}
