import 'package:flutter/material.dart';

import 'package:casa_loop_engine/controllers/route_editor_controller.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Choix commun aux dialogues de protection de l'état de travail :
/// « Sauvegarder » persiste d'abord, « Abandonner » autorise le
/// remplacement, « Annuler » (et la fermeture sans choix) laisse tout
/// en l'état.
enum RouteActionChoice { save, discard, cancel }

/// Propose « Enregistrer le tracé / Abandonner / Annuler » avant tout
/// chargement ou démarrage qui remplacerait un résultat calculé pas
/// encore enregistré.
Future<RouteActionChoice?> showUnsavedTraceDialog(BuildContext context) {
  Diag.event('Ui.dialog', 'target=unsavedTracedResult');
  return showDialog<RouteActionChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Tracé non enregistré'),
      content: const Text(
        'Un tracé calculé n\u2019est pas encore enregistré et serait remplacé par le chargement.',
      ),
      actions: [
        TextButton(
          key: const Key('load-draft-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(RouteActionChoice.cancel),
          child: const Text('Annuler'),
        ),
        TextButton(
          key: const Key('load-draft-discard'),
          onPressed: () => Navigator.of(dialogContext).pop(RouteActionChoice.discard),
          child: const Text('Abandonner'),
        ),
        TextButton(
          key: const Key('load-draft-save'),
          onPressed: () => Navigator.of(dialogContext).pop(RouteActionChoice.save),
          child: const Text('Enregistrer le tracé'),
        ),
      ],
    ),
  );
}

/// Propose « Sauvegarder / Abandonner / Annuler » pour le trajet en cours
/// avant le démarrage d'un nouveau trajet.
Future<RouteActionChoice?> showNewDraftDialog(BuildContext context) {
  Diag.event('Ui.dialog', 'target=newDraft');
  return showDialog<RouteActionChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Nouveau trajet'),
      content: const Text('Que faire du trajet en cours ?'),
      actions: [
        TextButton(
          key: const Key('new-draft-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(RouteActionChoice.cancel),
          child: const Text('Annuler'),
        ),
        TextButton(
          key: const Key('new-draft-discard'),
          onPressed: () => Navigator.of(dialogContext).pop(RouteActionChoice.discard),
          child: const Text('Abandonner'),
        ),
        TextButton(
          key: const Key('new-draft-save'),
          onPressed: () => Navigator.of(dialogContext).pop(RouteActionChoice.save),
          child: const Text('Sauvegarder'),
        ),
      ],
    ),
  );
}

/// Flux « Nouveau trajet » partagé entre la carte et la bibliothèque :
/// si l'état de travail contient des repères, demande d'abord
/// « Sauvegarder / Abandonner / Annuler » ; puis démarre un trajet vierge.
/// Retourne `true` si le nouveau trajet a été démarré, `false` si
/// l'utilisateur a annulé ; propage les erreurs de sauvegarde et de
/// réinitialisation à l'appelant (qui les affiche à sa façon).
Future<bool> confirmAndStartNewDraft(BuildContext context) async {
  final editor = RouteEditorController.instance;
  var discardUnsavedResult = false;
  if (editor.validatedMarkers.isNotEmpty || editor.hasUnsavedTracedResult) {
    final choice = await showNewDraftDialog(context);
    if (!context.mounted) return false;
    switch (choice) {
      case null:
      case RouteActionChoice.cancel:
        return false;
      case RouteActionChoice.discard:
        discardUnsavedResult = true;
      case RouteActionChoice.save:
        // Sauvegarde réussie = tracé éventuel enregistré : le nouveau
        // trajet est ensuite permis sans drapeau d'abandon.
        await editor.saveDraft();
    }
    if (!context.mounted) return false;
  }
  await editor.newDraft(discardUnsavedResult: discardUnsavedResult);
  return true;
}
