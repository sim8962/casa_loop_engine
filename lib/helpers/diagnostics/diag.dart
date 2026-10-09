import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Journal central de diagnostic du parcours utilisateur.
///
/// Format d'une ligne émise via [debugPrint] :
/// `[HH:MM:SS.mmm][#id][TAG] Classe.methode details`
///
/// - `START` : horodatage, identifiant unique de l'opération, paramètres.
/// - `END`   : même identifiant, `elapsedMs`, résumé du résultat.
/// - `ERROR` : même identifiant, `elapsedMs`, exception et stack trace.
/// - `EVENT` : fait ponctuel (tap, lifecycle, callback) sans durée propre.
///
/// Garde-fous volontaires :
/// - inactif hors mode debug : [enabled] vaut `kDebugMode` par défaut, en
///   release chaque appel se réduit au corps mesuré ;
/// - les callbacks à haute fréquence (caméra, slider, saisie, helpers
///   appelés en boucle) passent par [frequent], [frequentSync] ou
///   [frequentFuture] : en mode normal, au plus une ligne par nom et par
///   [throttleInterval], le nombre d'appels masqués étant reporté
///   explicitement (`(+N masqués)`) ; `Diag.verbose = true` rend le tracé
///   exhaustif (START/END complets à chaque appel) ;
/// - les erreurs ne sont jamais filtrées par la limitation de fréquence ;
/// - chaque message est construit dans un [StringBuffer] local puis affiché :
///   aucun buffer global ne grandit indéfiniment ;
/// - les datasets, géométries et contenus de fichiers ne sont pas imprimés :
///   les appelants ne passent que des compteurs, tailles et résumés.
final class Diag {
  Diag._();

  /// Activation globale. Limitée au mode debug par défaut.
  static bool enabled = kDebugMode;

  /// Mode exhaustif : les opérations fréquentes produisent des paires
  /// START/END complètes au lieu d'un EVENT limité en fréquence.
  static bool verbose = false;

  /// Intervalle minimal entre deux lignes du même nom en mode limité.
  static Duration throttleInterval = const Duration(milliseconds: 250);

  static int _seq = 0;
  static final Map<String, _Throttle> _throttles = {};
  static final Set<String> _firstFrameSeen = {};

  static int _nextId() => ++_seq;

  static String _timestamp() {
    final now = DateTime.now();
    String pad(int value, int width) => value.toString().padLeft(width, '0');
    return '${pad(now.hour, 2)}:${pad(now.minute, 2)}:${pad(now.second, 2)}'
        '.${pad(now.millisecond, 3)}';
  }

  static void _write(int id, String tag, String message) {
    final buffer = StringBuffer()
      ..write('[')
      ..write(_timestamp())
      ..write('][#')
      ..write(id)
      ..write('][')
      ..write(tag)
      ..write('] ')
      ..write(message);
    debugPrint(buffer.toString());
  }

  static void _writeError(
    int id,
    String name,
    int? elapsedMs,
    Object exception,
    StackTrace? stack,
  ) {
    final buffer = StringBuffer()
      ..write(name)
      ..write(elapsedMs == null ? '' : ' elapsedMs=$elapsedMs')
      ..write('\nexception: ')
      ..write(exception)
      ..write('\n')
      ..write(stack ?? StackTrace.current);
    _write(id, 'ERROR', buffer.toString());
  }

  /// Ouvre une opération instrumentée manuellement : l'appelant clôture avec
  /// [DiagSpan.end], [DiagSpan.early] ou [DiagSpan.fail].
  static DiagSpan start(String name, [String? params]) {
    if (!enabled) return DiagSpan.disabled();
    final id = _nextId();
    _write(id, 'START', params == null ? name : '$name $params');
    return DiagSpan._(id, name, Stopwatch()..start());
  }

  /// Fait ponctuel : tap, callback de cycle de vie, choix utilisateur.
  static void event(String name, [String? details]) {
    if (!enabled) return;
    _write(_nextId(), 'EVENT', details == null ? name : '$name $details');
  }

  /// Ligne ERROR autonome, pour les exceptions interceptées et gérées
  /// sur place (catch qui ne re-propage pas).
  static void error(String name, Object exception, [StackTrace? stack]) {
    if (!enabled) return;
    _writeError(_nextId(), name, null, exception, stack);
  }

  /// Version limitée en fréquence de [event]. En mode normal, au plus une
  /// ligne par [throttleInterval] par [name] ; le nombre d'appels masqués
  /// est reporté sur la ligne suivante émise.
  static void frequent(String name, [String? details]) {
    if (!enabled) return;
    if (verbose) {
      event(name, details);
      return;
    }
    _throttled(name, details);
  }

  /// Mesure une opération synchrone : START avant, END/ERROR après, valeur
  /// de retour et exception propagés sans modification.
  static T sync<T>(
    String name,
    T Function() body, {
    String? params,
    String? Function(T value)? result,
  }) {
    if (!enabled) return body();
    final op = start(name, params);
    try {
      final value = body();
      op.end(result?.call(value));
      return value;
    } catch (exception, stack) {
      op.fail(exception, stack);
      rethrow;
    }
  }

  /// Mesure une opération asynchrone jusqu'à la complétion réelle du Future.
  /// Valeur et exception propagées sans modification.
  static Future<T> future<T>(
    String name,
    Future<T> Function() body, {
    String? params,
    String? Function(T value)? result,
  }) async {
    if (!enabled) return body();
    final op = start(name, params);
    try {
      final value = await body();
      op.end(result?.call(value));
      return value;
    } catch (exception, stack) {
      op.fail(exception, stack);
      rethrow;
    }
  }

  /// [sync] pour les opérations à haute fréquence. Mode normal : le corps
  /// est exécuté et mesuré à chaque appel, mais seul un EVENT limité en
  /// fréquence (avec `elapsedMs`) est émis. Mode [verbose] : START/END
  /// complets à chaque appel. Les erreurs ne sont jamais limitées.
  static T frequentSync<T>(
    String name,
    T Function() body, {
    String? params,
    String? Function(T value)? result,
  }) {
    if (!enabled || verbose) {
      return sync(name, body, params: params, result: result);
    }
    final watch = Stopwatch()..start();
    try {
      final value = body();
      watch.stop();
      _throttled(
        name,
        'elapsedMs=${watch.elapsedMilliseconds}'
        '${result == null ? '' : ' ${result(value)}'}',
      );
      return value;
    } catch (exception, stack) {
      watch.stop();
      _writeError(_nextId(), name, watch.elapsedMilliseconds, exception, stack);
      rethrow;
    }
  }

  /// [future] pour les opérations asynchrones à haute fréquence : la durée
  /// couvre la complétion réelle du Future, mais l'émission est limitée en
  /// fréquence sauf en mode [verbose]. Les erreurs ne sont jamais limitées.
  static Future<T> frequentFuture<T>(
    String name,
    Future<T> Function() body, {
    String? params,
    String? Function(T value)? result,
  }) async {
    if (!enabled || verbose) {
      return future(name, body, params: params, result: result);
    }
    final watch = Stopwatch()..start();
    try {
      final value = await body();
      watch.stop();
      _throttled(
        name,
        'elapsedMs=${watch.elapsedMilliseconds}'
        '${result == null ? '' : ' ${result(value)}'}',
      );
      return value;
    } catch (exception, stack) {
      watch.stop();
      _writeError(_nextId(), name, watch.elapsedMilliseconds, exception, stack);
      rethrow;
    }
  }

  /// Mesure le délai entre l'appel et la fin de la première frame rendue.
  ///
  /// Distinct de la durée de construction d'un widget, qui se mesure avec
  /// [sync] autour de `build` : ici on mesure l'attente avant le rendu
  /// effectif (préparation, layout, rasterisation). Avec `once` (défaut),
  /// seul le premier appel du même [name] est mesuré.
  static void untilFirstFrame(String name, {String? params, bool once = true}) {
    if (!enabled) return;
    if (once && !_firstFrameSeen.add(name)) return;
    final op = start(name, params);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      op.end('firstFrame');
    });
  }

  static void _throttled(String name, String? details) {
    final now = DateTime.now();
    final bucket = _throttles.putIfAbsent(name, _Throttle.new);
    if (now.difference(bucket.lastEmit) < throttleInterval) {
      bucket.suppressed++;
      return;
    }
    final suppressed = bucket.suppressed;
    bucket
      ..lastEmit = now
      ..suppressed = 0;
    final suffix = suppressed == 0 ? '' : ' (+$suppressed masqués)';
    _write(
      _nextId(),
      'EVENT',
      '$name${details == null ? '' : ' $details'}$suffix',
    );
  }


}

/// Opération ouverte par [Diag.start] : l'identifiant est partagé entre le
/// START initial et le END/ERROR de clôture. `end` est idempotent : seule
/// la première clôture émet une ligne.
final class DiagSpan {
  DiagSpan._(this.id, this.name, this._watch);

  /// Span inerte retourné quand [Diag.enabled] est faux.
  DiagSpan.disabled() : id = -1, name = '', _watch = null;

  final int id;
  final String name;
  final Stopwatch? _watch;
  bool _closed = false;

  /// Clôture normale. [result] est un résumé court (compteurs, tailles).
  void end([String? result]) {
    final watch = _watch;
    if (watch == null || _closed) return;
    _closed = true;
    watch.stop();
    Diag._write(
      id,
      'END',
      '$name elapsedMs=${watch.elapsedMilliseconds}'
          '${result == null ? '' : ' $result'}',
    );
  }

  /// Clôture sur sortie anticipée (garde, return précoce) : distinguée par
  /// le marqueur `early=`.
  void early(String reason) => end('early=$reason');

  /// Clôture sur erreur : durée, exception et stack trace. La propagation
  /// reste à la charge de l'appelant.
  void fail(Object exception, [StackTrace? stack]) {
    final watch = _watch;
    if (watch == null || _closed) return;
    _closed = true;
    watch.stop();
    Diag._writeError(id, name, watch.elapsedMilliseconds, exception, stack);
  }
}

final class _Throttle {
  _Throttle() : lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime lastEmit;
  int suppressed = 0;
}
