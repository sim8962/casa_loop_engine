import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Construit une clé de recherche normalisée à partir des noms connus d'un
/// lieu. La clé est déterministe, sans dépendance externe, et reste simple
/// (pas de fuzzy-search pour l'instant).
///
/// La normalisation applique : trim, minuscules, espaces réduits, repli des
/// accents latins. L'arabe, l'amazighe et l'unicode hors latin sont conservés
/// tels quels.
class PlaceSearchKeyService {
  PlaceSearchKeyService._();

  static final _whitespace = RegExp(r'\s+');

  static final _accentedRunes = [
    0x00E0,
    0x00E1,
    0x00E2,
    0x00E3,
    0x00E4,
    0x00E5,
    0x00E6,
    0x00E7,
    0x00E8,
    0x00E9,
    0x00EA,
    0x00EB,
    0x00EC,
    0x00ED,
    0x00EE,
    0x00EF,
    0x00F1,
    0x00F2,
    0x00F3,
    0x00F4,
    0x00F5,
    0x00F6,
    0x00F8,
    0x00F9,
    0x00FA,
    0x00FB,
    0x00FC,
    0x00FD,
    0x00FF,
    0x0101,
    0x0103,
    0x0105,
    0x0107,
    0x010D,
    0x0113,
    0x0117,
    0x0119,
    0x012B,
    0x012F,
    0x0142,
    0x0144,
    0x0148,
    0x014D,
    0x0153,
    0x015B,
    0x015F,
    0x0161,
    0x016B,
    0x0173,
    0x017A,
    0x017C,
    0x017E,
    0x0219,
    0x021B,
  ];

  static final _baseReplacements = [
    'a',
    'a',
    'a',
    'a',
    'a',
    'a',
    'ae',
    'c',
    'e',
    'e',
    'e',
    'e',
    'i',
    'i',
    'i',
    'i',
    'n',
    'o',
    'o',
    'o',
    'o',
    'o',
    'o',
    'u',
    'u',
    'u',
    'u',
    'y',
    'y',
    'a',
    'a',
    'a',
    'c',
    'c',
    'e',
    'e',
    'e',
    'i',
    'i',
    'l',
    'n',
    'n',
    'o',
    'oe',
    's',
    's',
    's',
    'u',
    'u',
    'z',
    'z',
    'z',
    's',
    't',
  ];

  static final _foldMap = Map<int, String>.fromIterables(_accentedRunes, _baseReplacements);

  /// Normalise une requête ou un nom unique de la même manière que la clé
  /// construite par [build].
  static String normalize(String raw) => Diag.frequentSync('PlaceSearchKeyService.normalize', () {
    if (raw.isEmpty) return '';

    return _foldAccents(raw.trim().toLowerCase().replaceAll(_whitespace, ' ').trim());
  }, params: 'in="$raw"');

  static String build({
    required String name,
    String? nameFr,
    String? nameAr,
    String? nameZgh,
    List<String>? alternativeNames,
  }) => Diag.frequentSync(
    'PlaceSearchKeyService.build',
    () {
      final tokens = <String>{};

      void add(String? raw) {
        if (raw == null || raw.isEmpty) return;

        final normalized = normalize(raw);
        if (normalized.isEmpty) return;

        tokens.add(normalized);
      }

      add(name);
      add(nameFr);
      add(nameAr);
      add(nameZgh);
      alternativeNames?.forEach(add);

      return tokens.join(' ');
    },
    params: 'name="$name" altNames=${alternativeNames?.length ?? 0}',
    result: (key) => 'keyBytes=${key.length}',
  );

  /// Repli léger des accents latins. L'arabe, l'amazighe et le reste de
  /// l'unicode sont conservés sans modification.
  static String _foldAccents(String input) => Diag.frequentSync('PlaceSearchKeyService._foldAccents', () {
    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      final rune = c.codeUnitAt(0);
      final replacement = _foldMap[rune];
      buffer.write(replacement ?? c);
    }
    return buffer.toString();
  }, params: 'len=${input.length}');
}
