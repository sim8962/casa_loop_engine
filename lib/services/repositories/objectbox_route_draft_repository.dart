import 'dart:convert';

import '../../../objectbox.g.dart';

import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/models/route_draft.dart';
import 'package:casa_loop_engine/models/route_draft_segment_preference.dart';
import 'package:casa_loop_engine/services/repositories/route_draft_repository.dart';
import 'package:casa_loop_engine/models/entities/route_draft_entity.dart';
import 'package:casa_loop_engine/services/objectbox/objectbox_store.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Persistance du brouillon de trajet dans ObjectBox.
class ObjectBoxRouteDraftRepository implements RouteDraftRepository {
  ObjectBoxRouteDraftRepository(ObjectBoxStore objectBox) : _box = objectBox.store.box<RouteDraftEntity>();

  final Box<RouteDraftEntity> _box;

  @override
  Future<String> save(RouteDraft draft) => Diag.future(
    'ObjectBoxRouteDraftRepository.save',
    () async {
      // Un identifiant déjà attribué met à jour ce trajet précis ; `0`
      // (identifiant absent ou invalide) insère un nouveau trajet, sans
      // jamais affecter les autres trajets de la boîte.
      final existingId = draft.id == null ? 0 : (int.tryParse(draft.id!) ?? 0);
      final entity = RouteDraftEntity(
        id: existingId,
        name: draft.name,
        createdAtMillis: draft.createdAt.millisecondsSinceEpoch,
        savedAtMillis: draft.savedAt.millisecondsSinceEpoch,
        targetMode: draft.targetMode,
        targetDistanceKm: draft.targetDistanceKm,
        targetDurationHours: draft.targetDurationHours,
        totalDistanceKm: draft.totalDistanceKm,
        totalDurationHours: draft.totalDurationHours,
        averageSpeedKmh: draft.averageSpeedKmh,
        markersJson: _encodeMarkers(draft.markers),
        preferencesJson: _encodePreferences(draft.preferences),
      );
      final id = await _box.putAsync(entity);
      return id.toString();
    },
    params:
        'id=${draft.id} markers=${draft.markers.length} '
        'preferences=${draft.preferences.length} mode=${draft.targetMode}',
    result: (id) => 'id=$id',
  );

  @override
  Future<RouteDraft?> load(String id) => Diag.future(
    'ObjectBoxRouteDraftRepository.load',
    () async {
      final boxId = int.tryParse(id);
      if (boxId == null) return null;
      final entity = await _box.getAsync(boxId);
      if (entity == null) return null;
      return _toDraft(entity);
    },
    params: 'id=$id',
    result: (draft) => draft == null
        ? 'found=false'
        : 'found=true markers=${draft.markers.length} '
              'preferences=${draft.preferences.length}',
  );

  @override
  Future<List<RouteDraft>> listAll() => Diag.future('ObjectBoxRouteDraftRepository.listAll', () async {
    final entities = await _box.getAllAsync();
    final drafts = entities.map(_toDraft).toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return drafts;
  }, result: (drafts) => 'count=${drafts.length}');

  RouteDraft _toDraft(RouteDraftEntity entity) => routeDraftFromEntity(entity);

  String _encodeMarkers(List<MapMarkerItem> markers) => Diag.sync(
    'ObjectBoxRouteDraftRepository._encodeMarkers',
    () {
      final list = markers
          .map(
            (m) => {
              'id': m.id,
              'name': m.name,
              'type': m.type,
              'latitude': m.latitude,
              'longitude': m.longitude,
              'roadRef': m.roadRef,
              'orderIndex': m.orderIndex,
            },
          )
          .toList();
      return jsonEncode(list);
    },
    params: 'count=${markers.length}',
    result: (json) => 'bytes=${json.length}',
  );

  String _encodePreferences(List<RouteDraftSegmentPreference> preferences) => Diag.sync(
    'ObjectBoxRouteDraftRepository._encodePreferences',
    () {
      final list = preferences
          .map(
            (p) => {
              'startMarkerId': p.startMarkerId,
              'endMarkerId': p.endMarkerId,
              'value': p.value,
              // Absente des trajets sauvegardés avant l'ajout de la couleur
              // de segment : `_decodePreferences` retombe alors sur `null`.
              if (p.color != null) 'color': p.color,
            },
          )
          .toList();
      return jsonEncode(list);
    },
    params: 'count=${preferences.length}',
    result: (json) => 'bytes=${json.length}',
  );
}

/// Convertit une entité ObjectBox en [RouteDraft], isolée du repository
/// pour être testable sans dépendance native.
///
/// Ancienne entrée écrite avant l'ajout de `createdAtMillis` : le champ
/// vaut `0`. On retombe alors sur `savedAtMillis` comme base stable du
/// nom par défaut ; cette valeur est conservée à la première modification
/// (le controller réécrit la même date à la sauvegarde suivante).
RouteDraft routeDraftFromEntity(RouteDraftEntity entity) => RouteDraft(
  id: entity.id.toString(),
  name: entity.name,
  createdAt: DateTime.fromMillisecondsSinceEpoch(
    entity.createdAtMillis == 0 ? entity.savedAtMillis : entity.createdAtMillis,
  ),
  savedAt: DateTime.fromMillisecondsSinceEpoch(entity.savedAtMillis),
  targetMode: entity.targetMode,
  targetDistanceKm: entity.targetDistanceKm,
  targetDurationHours: entity.targetDurationHours,
  totalDistanceKm: entity.totalDistanceKm,
  totalDurationHours: entity.totalDurationHours,
  averageSpeedKmh: entity.averageSpeedKmh,
  markers: _decodeMarkers(entity.markersJson),
  preferences: _decodePreferences(entity.preferencesJson),
);

List<MapMarkerItem> _decodeMarkers(String json) => Diag.sync(
  'ObjectBoxRouteDraftRepository._decodeMarkers',
  () {
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((m) {
      final map = m as Map<String, dynamic>;
      return MapMarkerItem(
        id: map['id'] as String,
        name: map['name'] as String,
        type: map['type'] as String,
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        roadRef: map['roadRef'] as String?,
        orderIndex: map['orderIndex'] as int,
      );
    }).toList();
  },
  params: 'jsonBytes=${json.length}',
  result: (markers) => 'count=${markers.length}',
);

List<RouteDraftSegmentPreference> _decodePreferences(String json) => Diag.sync(
  'ObjectBoxRouteDraftRepository._decodePreferences',
  () {
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((p) {
      final map = p as Map<String, dynamic>;
      return RouteDraftSegmentPreference(
        startMarkerId: map['startMarkerId'] as String,
        endMarkerId: map['endMarkerId'] as String,
        value: (map['value'] as num).toDouble(),
        // Absente dans le JSON des trajets sauvegardés avant l'ajout de la
        // couleur de segment : `map['color']` vaut alors `null` sans accès
        // à une clé manquante, et sans jamais lever d'erreur.
        color: map['color'] as String?,
      );
    }).toList();
  },
  params: 'jsonBytes=${json.length}',
  result: (prefs) => 'count=${prefs.length}',
);
