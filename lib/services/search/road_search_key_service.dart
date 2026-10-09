import 'package:casa_loop_engine/services/search/place_search_key_service.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Construction et normalisation de la clé de recherche pour les routes.
///
/// Réutilise la normalisation multilingue établie pour `PlaceSearchKeyService`
/// et ajoute les formes canoniques et alias (N1, Pxxxx).
class RoadSearchKeyService {
  RoadSearchKeyService._();

  static final _digitAlias = RegExp(r'^(n|p)(\d+)$');

  static String normalize(String raw) => PlaceSearchKeyService.normalize(raw);

  /// Transforme une requête utilisateur en référence canonique si c'est un
  /// alias non ambigu : `N1 → RN1`, `P3602 → RP3602`.
  /// Les formes `Rxxx` restent inchangées car ambiguës (RR ou RP).
  static String canonicalizeReference(String query) => Diag.frequentSync(
    'RoadSearchKeyService.canonicalizeReference',
    () {
      final lower = normalize(query);
      final match = _digitAlias.firstMatch(lower);
      if (match != null) {
        final prefix = match.group(1);
        final digits = match.group(2);
        if (prefix == 'n') return 'rn$digits';
        if (prefix == 'p') return 'rp$digits';
      }
      return lower;
    },
    params: 'query="$query"',
    result: (term) => 'term="$term"',
  );

  /// Construit une clé de recherche à partir des champs textuels de la route.
  static String build({
    required String reference,
    required String normalizedReference,
    required String roadClass,
    String? name,
    String? nameFr,
    String? nameAr,
    String? nameZgh,
    List<String>? alternativeNames,
  }) => Diag.frequentSync(
    'RoadSearchKeyService.build',
    () {
      final tokens = <String>{};

      void add(String? raw) {
        if (raw == null || raw.isEmpty) return;
        final normalized = normalize(raw);
        if (normalized.isEmpty) return;
        tokens.add(normalized);
      }

      add(reference);
      add(normalizedReference);
      add(roadClass);

      // Alias canoniques : N1 → n1, P3602 → p3602, etc.
      final alias = _aliasToken(reference);
      if (alias != null) {
        add(alias);
      }

      add(name);
      add(nameFr);
      add(nameAr);
      add(nameZgh);
      alternativeNames?.forEach(add);

      return tokens.join(' ');
    },
    params: 'reference=$reference class=$roadClass',
    result: (key) => 'keyBytes=${key.length}',
  );

  static String? _aliasToken(String reference) => Diag.frequentSync('RoadSearchKeyService._aliasToken', () {
    final lower = normalize(reference);
    if (lower.startsWith('rn')) return lower.substring(1); // n1, n7...
    if (lower.startsWith('rp')) return lower.substring(1); // p3602...
    return null;
  }, params: 'reference=$reference');
}
