import '../../../objectbox.g.dart';

import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Point d'entrée unique du store ObjectBox.
///
/// Un seul `Store` doit être ouvert pour toute l'application : cette classe
/// centralise son ouverture et sa fermeture.
class ObjectBoxStore {
  ObjectBoxStore._(this.store);

  final Store store;

  static Future<ObjectBoxStore> open({String? directory}) => Diag.future(
    'ObjectBoxStore.open',
    () async => ObjectBoxStore._(await openStore(directory: directory)),
    params: 'directory=${directory ?? "default"}',
  );

  void close() => Diag.sync('ObjectBoxStore.close', store.close);
}
