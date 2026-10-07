import 'package:casa_loop_engine/models/route_draft.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Persistance de la bibliothèque des trajets sauvegardés : plusieurs
/// trajets indépendants, chacun identifié par [RouteDraft.id].
abstract interface class RouteDraftRepository {
  /// Insère [draft] si `draft.id` est `null`, sinon met à jour le trajet
  /// portant cet identifiant sans affecter les autres. Retourne
  /// l'identifiant du trajet (inchangé pour une mise à jour, nouvellement
  /// attribué pour une insertion).
  Future<String> save(RouteDraft draft);

  /// Charge le trajet [id], ou `null` s'il n'existe pas (ou plus).
  Future<RouteDraft?> load(String id);

  /// Liste tous les trajets sauvegardés, du plus récemment sauvegardé au
  /// plus ancien.
  Future<List<RouteDraft>> listAll();
}

/// Implémentation volatile, utilisée en test ou en secours.
class InMemoryRouteDraftRepository implements RouteDraftRepository {
  final Map<String, RouteDraft> _drafts = {};
  int _nextId = 1;

  @override
  Future<String> save(RouteDraft draft) => Diag.future(
    'InMemoryRouteDraftRepository.save',
    () async {
      final id = draft.id ?? (_nextId++).toString();
      _drafts[id] = RouteDraft(
        id: id,
        name: draft.name,
        createdAt: draft.createdAt,
        savedAt: draft.savedAt,
        targetMode: draft.targetMode,
        targetDistanceKm: draft.targetDistanceKm,
        targetDurationHours: draft.targetDurationHours,
        totalDistanceKm: draft.totalDistanceKm,
        totalDurationHours: draft.totalDurationHours,
        averageSpeedKmh: draft.averageSpeedKmh,
        markers: draft.markers,
        preferences: draft.preferences,
      );
      return id;
    },
    params: 'id=${draft.id ?? "new"} markers=${draft.markers.length}',
    result: (id) => 'id=$id',
  );

  @override
  Future<RouteDraft?> load(String id) => Diag.future(
    'InMemoryRouteDraftRepository.load',
    () async => _drafts[id],
    params: 'id=$id',
    result: (draft) => 'found=${draft != null}',
  );

  @override
  Future<List<RouteDraft>> listAll() => Diag.future(
    'InMemoryRouteDraftRepository.listAll',
    () async => _drafts.values.toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt)),
    result: (drafts) => 'count=${drafts.length}',
  );
}
