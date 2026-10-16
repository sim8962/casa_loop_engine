import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import 'package:casa_loop_engine/controllers/route_editor_controller.dart';
import 'package:casa_loop_engine/models/route_draft.dart';
import 'package:casa_loop_engine/routes/app_routes.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';
import 'package:casa_loop_engine/views/common/route_dialogs.dart';

/// Bibliothèque des trajets sauvegardés : liste chaque trajet par son nom,
/// sa date de sauvegarde et son nombre de repères. Un trajet dont le tracé
/// est enregistré offre deux entrées : « Charger » restaure le tracé et
/// revient directement à la carte — sans appel moteur — ; « Éditer »
/// (ou un clic sur la ligne) ouvre l'éditeur déjà présent dans la pile de
/// navigation — sans empiler un second éditeur — ou l'ouvre sinon. Un
/// trajet sans tracé valide ne propose que l'édition.
///
/// « Supprimer » retire définitivement le trajet après confirmation ;
/// si c'est le trajet actuellement édité, l'état de travail est remis à
/// zéro comme un nouveau trajet.
///
/// « Nouveau trajet » démarre un trajet vierge depuis la bibliothèque,
/// avec les mêmes protections que depuis l'éditeur ou la carte.
///
/// Si un résultat tracé n'a pas encore été enregistré, le chargement —
/// même du trajet déjà actif — est précédé d'un choix explicite
/// « Enregistrer le tracé / Abandonner / Annuler » : la géométrie
/// calculée n'est jamais remplacée silencieusement.
class RouteLibraryView extends StatefulWidget {
  const RouteLibraryView({super.key});

  @override
  State<RouteLibraryView> createState() => _RouteLibraryViewState();
}

class _RouteLibraryViewState extends State<RouteLibraryView> {
  late Future<List<RouteDraft>> _draftsFuture;

  @override
  void initState() {
    super.initState();
    Diag.event('RouteLibraryView.initState');
    _draftsFuture = RouteEditorController.instance.listSavedDrafts();
  }

  void _reload() {
    setState(() {
      _draftsFuture = RouteEditorController.instance.listSavedDrafts();
    });
  }

  static String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
  }

  /// Nom affiché d'un trajet : le nom personnalisé, ou à défaut le nom
  /// par défaut stable dérivé de sa création.
  static String _displayName(RouteDraft draft) =>
      draft.name.isEmpty ? RouteEditorController.defaultDraftName(draft.createdAt) : draft.name;

  /// Charge [draft]. [openInEditor] distingue les deux entrées : `false`
  /// (« Charger », tracé enregistré) revient à la carte ; `true`
  /// (« Éditer » ou clic sur la ligne) ouvre « Préparer la boucle ».
  Future<void> _onSelect(RouteDraft draft, {required bool openInEditor}) async {
    final id = draft.id;
    if (id == null) return;
    Diag.event('Ui.tap', 'target=RouteLibraryView.${openInEditor ? 'editDraft' : 'loadOnMap'} id=$id');
    final messenger = ScaffoldMessenger.of(context);
    final editor = RouteEditorController.instance;
    var discardUnsavedResult = false;
    // Un tracé calculé ou ajusté pas encore enregistré serait remplacé
    // par le chargement : décision explicite requise, y compris pour
    // recharger le trajet déjà actif.
    if (editor.hasUnsavedTracedResult) {
      final choice = await showUnsavedTraceDialog(context);
      if (!context.mounted) return;
      switch (choice) {
        case null:
        case RouteActionChoice.cancel:
          return;
        case RouteActionChoice.discard:
          discardUnsavedResult = true;
        case RouteActionChoice.save:
          try {
            await editor.saveDraft();
          } catch (exception) {
            Diag.error('RouteLibraryView.saveBeforeLoad', exception);
            if (!context.mounted) return;
            messenger.showSnackBar(
              const SnackBar(content: Text('Sauvegarde impossible — le tracé courant est conservé')),
            );
            return;
          }
      }
      if (!context.mounted) return;
    }
    // Honnêteté du trajet chargé : le résultat enregistré sera affiché
    // tel quel, ou le trajet est marqué « à recalculer ».
    try {
      await editor.loadDraft(id, discardUnsavedResult: discardUnsavedResult);
    } catch (exception) {
      Diag.error('RouteLibraryView.selectDraft', exception);
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Chargement impossible')));
      return;
    }
    if (!context.mounted) return;
    final routeRestored = editor.tracedItinerary.value != null;
    if (!openInEditor) {
      // « Charger » : ferme la bibliothèque puis, si « Préparer la
      // boucle » est empilé dessous, le ferme aussi — destination : la
      // carte, où le tracé restauré s'affiche via routeResultRevision
      // sans appel moteur.
      Get.back();
      if (Get.currentRoute == AppRoutes.selectedMarkers) {
        Get.back();
      }
      return;
    }
    // Ferme la bibliothèque : si l'éditeur est déjà ouvert dessous (accès
    // depuis « Préparer la boucle »), on y revient tel quel — ses champs
    // se mettent à jour via draftRestoreVersion. Sinon on l'ouvre.
    Get.back();
    if (Get.currentRoute != AppRoutes.selectedMarkers) {
      // Le Future se termine à la fermeture de l’éditeur, pas à son ouverture.
      Get.toNamed(AppRoutes.selectedMarkers);
    }
    if (!routeRestored) {
      // Le trajet est chargé mais n'a pas de tracé valide : indiquer
      // qu'un calcul explicite (« Tracer ») reste nécessaire — le
      // message part sur l'écran de destination.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Get.currentRoute != AppRoutes.selectedMarkers ||
            editor.currentDraftId.value != id ||
            editor.tracedItinerary.value != null) {
          return;
        }
        final ctx = Get.context;
        final target = ctx == null ? null : ScaffoldMessenger.maybeOf(ctx);
        target?.showSnackBar(const SnackBar(content: Text('Tracé à recalculer : appuyez sur « Tracer ».')));
      });
    }
  }

  /// `true` si le résultat moteur enregistré avec [draft] sera restauré
  /// au chargement : il correspond exactement aux repères et préférences
  /// sauvegardés (mêmes couples dirigés, même ordre, mêmes valeurs —
  /// voir `SavedRouteSnapshot.correspondsTo`). `false` sinon : ancien
  /// trajet sans géométrie, réglages modifiés depuis le calcul ou
  /// snapshot rejeté — le chargement reste possible, le tracé est « à
  /// recalculer ».
  static bool _hasUsableRoute(RouteDraft draft) {
    final snapshot = draft.computedResult;
    if (snapshot == null) return false;
    // Les préférences sauvegardées sont associées aux couples dirigés :
    // elles sont réalignées sur l'ordre des repères comme au chargement.
    final byKey = <String, double>{
      for (final pref in draft.preferences) '${pref.startMarkerId}>${pref.endMarkerId}': pref.value,
    };
    final preferences = <double>[
      for (var i = 0; i < draft.markers.length; i++)
        byKey['${draft.markers[i].id}>${draft.markers[(i + 1) % draft.markers.length].id}'] ?? -1,
    ];
    return snapshot.correspondsTo(draft.markers, preferences);
  }

  /// Supprime [draft] après confirmation explicite : action irréversible.
  /// Si le trajet supprimé est celui en cours d'édition, l'état de travail
  /// est remis à zéro ([RouteEditorController.deleteDraft]) — le dialogue
  /// l'annonce alors dans son contenu.
  Future<void> _onDelete(RouteDraft draft) async {
    final id = draft.id;
    if (id == null) return;
    Diag.event('Ui.tap', 'target=RouteLibraryView.deleteDraft id=$id');
    final messenger = ScaffoldMessenger.of(context);
    final editor = RouteEditorController.instance;
    final isCurrent = editor.currentDraftId.value == id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer ce trajet ?'),
        content: Text(
          '« ${_displayName(draft)} » sera définitivement supprimé.'
          '${isCurrent ? '\nLe trajet en cours d\u2019édition sera effacé.' : ''}',
        ),
        actions: [
          TextButton(
            key: const Key('delete-draft-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('delete-draft-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return;
    try {
      await editor.deleteDraft(id);
    } catch (exception) {
      Diag.error('RouteLibraryView.deleteDraft', exception);
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Suppression impossible')));
      return;
    }
    if (!context.mounted) return;
    _reload();
    messenger.showSnackBar(const SnackBar(content: Text('Trajet supprimé'), duration: Duration(seconds: 2)));
  }

  /// « Nouveau trajet » depuis la bibliothèque : même flux partagé que
  /// depuis la carte ou l'éditeur (protection Sauvegarder / Abandonner /
  /// Annuler), puis retour à l'écran précédent une fois le trajet vierge
  /// démarré.
  Future<void> _onNewDraft() async {
    Diag.event('Ui.tap', 'target=RouteLibraryView.newDraft');
    final messenger = ScaffoldMessenger.of(context);
    final bool started;
    try {
      started = await confirmAndStartNewDraft(context);
    } catch (exception) {
      Diag.error('RouteLibraryView.newDraft', exception);
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Nouveau trajet impossible : $exception')));
      return;
    }
    if (!context.mounted || !started) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('Nouveau trajet démarré'), duration: Duration(seconds: 2)),
    );
    Get.back();
  }

  /// Badge d'état du tracé enregistré : pastille colorée + libellé
  /// honnête (« Tracé prêt » / « À calculer »).
  Widget _traceBadge(bool routeRestored) {
    final color = routeRestored ? Colors.green : Colors.amber.shade800;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8.r,
          height: 8.r,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: 6.w),
        Text(routeRestored ? 'Tracé prêt' : 'À calculer', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Diag.sync('RouteLibraryView.build', () {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Mes trajets'),
          actions: [
            Obx(() {
              final editor = RouteEditorController.instance;
              final busy =
                  editor.isSavingDraft.value || editor.isLoadingDraft.value || editor.mutationsBlocked;
              return IconButton(
                key: const Key('route-library-new-draft'),
                tooltip: 'Nouveau trajet',
                onPressed: busy ? null : _onNewDraft,
                icon: const Icon(Icons.add_road),
              );
            }),
          ],
        ),
        body: FutureBuilder<List<RouteDraft>>(
          future: _draftsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Chargement impossible : ${snapshot.error}'),
                    TextButton(
                      key: const Key('route-library-retry'),
                      onPressed: _reload,
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              );
            }
            final drafts = snapshot.data ?? const <RouteDraft>[];
            if (drafts.isEmpty) {
              return const Center(child: Text('Aucun trajet sauvegardé'));
            }
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView.separated(
                key: const Key('route-library-list'),
                itemCount: drafts.length,
                separatorBuilder: (_, _) => Divider(height: 1.h),
                itemBuilder: (context, index) {
                  final draft = drafts[index];
                  final routeRestored = _hasUsableRoute(draft);
                  return ListTile(
                    key: Key('route-library-item-${draft.id}'),
                    title: Text(_displayName(draft)),
                    subtitle: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_formatDate(draft.savedAt)} — ${draft.markers.length} repères'),
                        SizedBox(height: 2.h),
                        _traceBadge(routeRestored),
                      ],
                    ),
                    onTap: () => _onSelect(draft, openInEditor: true),
                    // Tracé enregistré : deux entrées explicites —
                    // « Charger » affiche la carte avec le tracé,
                    // « Éditer » ouvre « Préparer la boucle ». « Supprimer »
                    // est proposé pour tout trajet, tracé ou non.
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (routeRestored) ...[
                          TextButton(
                            key: Key('route-library-load-${draft.id}'),
                            onPressed: () => _onSelect(draft, openInEditor: false),
                            child: const Text('Charger'),
                          ),
                          TextButton(
                            key: Key('route-library-edit-${draft.id}'),
                            onPressed: () => _onSelect(draft, openInEditor: true),
                            child: const Text('Éditer'),
                          ),
                        ],
                        IconButton(
                          key: Key('route-library-delete-${draft.id}'),
                          tooltip: 'Supprimer',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _onDelete(draft),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      );
    });
  }
}
