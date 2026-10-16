import 'package:casa_loop_engine/models/route_draft.dart';

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

  /// Supprime définitivement le trajet [id] de la bibliothèque. Sans
  /// effet si l'identifiant est invalide ou ne correspond à aucun trajet.
  Future<void> delete(String id);
}
