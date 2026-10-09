import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/models/route_draft.dart';
import 'package:casa_loop_engine/models/route_draft_segment_preference.dart';
import 'package:casa_loop_engine/services/repositories/marker_repository.dart';
import 'package:casa_loop_engine/services/repositories/route_draft_repository.dart';
import 'package:casa_loop_engine/services/repositories/route_preference_repository.dart';

/// Repository de repères en mémoire, pour les tests : ne touche jamais au
/// disque ni à ObjectBox.
class FakeMarkerRepository implements MarkerRepository {
  List<MapMarkerItem> _markers = [];

  /// Si `true`, le prochain [replaceAll] lève une erreur puis le drapeau
  /// retombe : permet de tester les rollbacks de l'état de travail.
  bool failNextReplaceAll = false;

  @override
  Future<List<MapMarkerItem>> loadAll() async => List.of(_markers);

  @override
  Future<void> save(MapMarkerItem marker) async {
    _markers = [..._markers.where((m) => m.id != marker.id), marker];
  }

  @override
  Future<void> saveAll(List<MapMarkerItem> markers) async {
    final ids = markers.map((m) => m.id).toSet();
    _markers = [..._markers.where((m) => !ids.contains(m.id)), ...markers];
  }

  @override
  Future<void> delete(String markerId) async {
    _markers = _markers.where((m) => m.id != markerId).toList();
  }

  @override
  Future<void> replaceAll(List<MapMarkerItem> markers) async {
    if (failNextReplaceAll) {
      failNextReplaceAll = false;
      throw StateError('Écriture de l\u2019état de travail impossible (test).');
    }
    _markers = List.of(markers);
  }
}

/// Repository de préférences de route en mémoire, pour les tests.
class FakeRoutePreferenceRepository implements RoutePreferenceRepository {
  final Map<String, double> _values = {};

  String _key(String startMarkerId, String endMarkerId) => '$startMarkerId>$endMarkerId';

  @override
  Future<void> save(String startMarkerId, String endMarkerId, double value) async {
    _values[_key(startMarkerId, endMarkerId)] = value;
  }

  @override
  Future<double?> load(String startMarkerId, String endMarkerId) async =>
      _values[_key(startMarkerId, endMarkerId)];

  @override
  Future<void> replaceAll(List<RouteDraftSegmentPreference> preferences) async {
    _values.clear();
    for (final preference in preferences) {
      _values[_key(preference.startMarkerId, preference.endMarkerId)] = preference.value;
    }
  }
}

/// Repository de trajets testable : délègue à [InMemoryRouteDraftRepository]
/// et permet d'injecter des délais et des erreurs pour couvrir les cas
/// de sauvegarde concurrente, d'échec et de double clic.
class TestDraftRepository implements RouteDraftRepository {
  final InMemoryRouteDraftRepository _inner = InMemoryRouteDraftRepository();

  /// Délai inséré avant chaque écriture, pour simuler une sauvegarde
  /// suffisamment longue pour saisir du texte pendant qu'elle se déroule.
  Duration saveDelay = Duration.zero;

  /// Délai inséré avant chaque lecture individuelle.
  Duration loadDelay = Duration.zero;

  /// Si `true`, la prochaine écriture lève une erreur puis le drapeau
  /// retombe.
  bool failNextSave = false;

  /// Si `true`, [listAll] lève une erreur.
  bool failListAll = false;

  /// Si `true`, [load] lève une erreur.
  bool failLoad = false;

  @override
  Future<String> save(RouteDraft draft) async {
    if (saveDelay > Duration.zero) {
      await Future<void>.delayed(saveDelay);
    }
    if (failNextSave) {
      failNextSave = false;
      throw StateError('Écriture impossible (test).');
    }
    return _inner.save(draft);
  }

  @override
  Future<RouteDraft?> load(String id) async {
    if (loadDelay > Duration.zero) {
      await Future<void>.delayed(loadDelay);
    }
    if (failLoad) {
      throw StateError('Lecture impossible (test).');
    }
    return _inner.load(id);
  }

  @override
  Future<List<RouteDraft>> listAll() async {
    if (failListAll) {
      throw StateError('Lecture de la bibliothèque impossible (test).');
    }
    return _inner.listAll();
  }
}
