import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:casa_loop_engine/routes/route_draft_loader.dart';
import 'package:casa_loop_engine/views/selected_markers/controllers/selected_markers_controller.dart';
import 'package:casa_loop_engine/views/selected_markers/widgets/route_name_field.dart';
import 'package:casa_loop_engine/views/selected_markers/widgets/route_preference_tile.dart';
import 'package:casa_loop_engine/views/selected_markers/widgets/target_loop_fields.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Écran de synthèse des repères choisis, dans l'ordre validé.
class SelectedMarkersView extends GetView<SelectedMarkersController> {
  const SelectedMarkersView({super.key});

  @override
  Widget build(BuildContext context) {
    Diag.untilFirstFrame('SelectedMarkersView.firstFrame');
    return Diag.sync('SelectedMarkersView.build', () {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Repères choisis'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Diag.event('Navigation.back', 'from=SelectedMarkersView');
              Get.back();
            },
          ),
          actions: [
            Obx(() {
              final busy = controller.isSavingDraft.value || controller.mutationsBlocked;
              return PopupMenuButton<_RouteMenuAction>(
                key: const Key('route-menu-button'),
                enabled: !busy,
                onSelected: (action) {
                  switch (action) {
                    case _RouteMenuAction.newDraft:
                      unawaited(_onNewDraft(context));
                    case _RouteMenuAction.saveAsCopy:
                      unawaited(_onSaveDraftAsCopy(context));
                    case _RouteMenuAction.loadRoute:
                      openRouteLibrary(origin: 'selectedMarkers');
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: _RouteMenuAction.loadRoute, child: Text('Charger un trajet')),
                  PopupMenuItem(value: _RouteMenuAction.newDraft, child: Text('Nouveau trajet')),
                  PopupMenuItem(value: _RouteMenuAction.saveAsCopy, child: Text('Enregistrer une copie')),
                ],
              );
            }),
          ],
        ),
        body: Obx(() {
          final markers = controller.validatedMarkers;
          if (markers.isEmpty) {
            return const Center(child: Text('Aucun repère choisi'));
          }
          return Column(
            children: [
              const RouteNameField(),
              const TargetLoopFields(),
              if (controller.loopSummary.value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 16, right: 16, bottom: 8),
                  child: Obx(() {
                    return FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        controller.loopSummary.value,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                      ),
                    );
                  }),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  // N repères + N segments (boucle fermée) + 1 rappel visuel du
                  // repère de départ à la fin, pour visualiser le retour.
                  itemCount: markers.length * 2 + 1,
                  itemBuilder: (context, index) {
                    Diag.frequent(
                      'SelectedMarkersView.itemBuilder',
                      'index=$index count=${markers.length * 2 + 1}',
                    );
                    final tileCount = markers.length * 2;
                    if (index == tileCount) {
                      final marker = markers[0];
                      final subtitle = marker.roadRef != null
                          ? '${marker.type} — ${marker.roadRef}'
                          : '${marker.type} — ${marker.latitude.toStringAsFixed(4)}, ${marker.longitude.toStringAsFixed(4)}';
                      return ListTile(
                        leading: const CircleAvatar(
                          radius: 14,
                          child: Text('1', style: TextStyle(fontSize: 12)),
                        ),
                        title: Text(controller.markerDisplayName(0)),
                        subtitle: Text(subtitle),
                        onTap: () {
                          Diag.event('SelectedMarkersView.markerTap', 'markerId=${marker.id} index=0');
                          controller.centerOnMarker(marker);
                        },
                      );
                    }
                    if (index.isEven) {
                      final markerIndex = index ~/ 2;
                      final marker = markers[markerIndex];
                      final number = markerIndex + 1;
                      final subtitle = marker.roadRef != null
                          ? '${marker.type} — ${marker.roadRef}'
                          : '${marker.type} — ${marker.latitude.toStringAsFixed(4)}, ${marker.longitude.toStringAsFixed(4)}';
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 14,
                          child: Text('$number', style: const TextStyle(fontSize: 12)),
                        ),
                        title: Text(controller.markerDisplayName(markerIndex)),
                        subtitle: Text(subtitle),
                        onTap: () {
                          Diag.event(
                            'SelectedMarkersView.markerTap',
                            'markerId=${marker.id} index=$markerIndex',
                          );
                          controller.centerOnMarker(marker);
                        },
                      );
                    }
                    final segmentIndex = index ~/ 2;
                    final endIndex = (segmentIndex + 1) % markers.length;
                    return RoutePreferenceTile(
                      segmentIndex: segmentIndex,
                      startName: controller.markerDisplayName(segmentIndex),
                      endName: controller.markerDisplayName(endIndex),
                      startNumber: segmentIndex + 1,
                      endNumber: endIndex + 1,
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: controller.isSavingDraft.value || controller.mutationsBlocked
                            ? null
                            : () => _onSaveDraft(context),
                        child: const Text('Sauvegarder'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed:
                            controller.isSavingDraft.value ||
                                controller.isTracing.value ||
                                controller.mutationsBlocked
                            ? null
                            : () => _onTraceRoute(context),
                        child: controller.isTracing.value
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Tracer'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
      );
    }, params: 'markers=${controller.validatedMarkers.length}');
  }

  /// Bouton « Sauvegarder » : attend la fin réelle de la persistance avant
  /// d'afficher la confirmation, signale toute erreur et reste sur l'écran.
  Future<void> _onSaveDraft(BuildContext context) async {
    Diag.event('Ui.tap', 'target=SelectedMarkersView.saveDraft');
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.saveDraft();
    } catch (exception) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Sauvegarde impossible : ${_errorMessage(exception)}')));
      return;
    }
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Trajet sauvegardé'), duration: Duration(seconds: 2)),
    );
  }

  /// Bouton « Tracer » : sauvegarde complète puis calcul moteur du premier
  /// segment. Les erreurs de sauvegarde et de calcul sont distinguées ;
  /// après un calcul réussi, l'écran rejoint la carte où la géométrie est
  /// affichée.
  Future<void> _onTraceRoute(BuildContext context) async {
    Diag.event('Ui.tap', 'target=SelectedMarkersView.trace');
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.traceRoute();
    } catch (exception) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Sauvegarde impossible : ${_errorMessage(exception)}')));
      return;
    }
    if (!context.mounted) return;
    final traceError = controller.traceError.value;
    if (traceError != null) {
      messenger.showSnackBar(SnackBar(content: Text(traceError), duration: const Duration(seconds: 5)));
      return;
    }
    final route = controller.tracedSegment.value;
    if (route == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Tracé calculé : ${route.distanceKm.toStringAsFixed(1)} km — ${_formatDuration(route.durationSeconds)}',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
    // La géométrie est dessinée par MapController sur l'écran carte,
    // présent sous cet écran dans la pile de navigation.
    Get.back();
  }

  static String _formatDuration(double seconds) {
    final totalMinutes = (seconds / 60).round();
    if (totalMinutes < 60) return '$totalMinutes min';
    return '${totalMinutes ~/ 60} h ${(totalMinutes % 60).toString().padLeft(2, '0')}';
  }

  /// Menu « Nouveau trajet » : si l'état de travail contient des repères,
  /// demande d'abord à l'utilisateur de choisir entre Sauvegarder,
  /// Abandonner et Annuler ; une annulation ou un échec de sauvegarde
  /// laisse l'état de travail inchangé. Puis démarre un trajet vierge.
  Future<void> _onNewDraft(BuildContext context) async {
    Diag.event('Ui.tap', 'target=SelectedMarkersView.newDraft');
    final messenger = ScaffoldMessenger.of(context);
    if (controller.validatedMarkers.isNotEmpty) {
      final choice = await showDialog<_NewDraftChoice>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Nouveau trajet'),
          content: const Text('Que faire du trajet en cours ?'),
          actions: [
            TextButton(
              key: const Key('new-draft-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(_NewDraftChoice.cancel),
              child: const Text('Annuler'),
            ),
            TextButton(
              key: const Key('new-draft-discard'),
              onPressed: () => Navigator.of(dialogContext).pop(_NewDraftChoice.discard),
              child: const Text('Abandonner'),
            ),
            TextButton(
              key: const Key('new-draft-save'),
              onPressed: () => Navigator.of(dialogContext).pop(_NewDraftChoice.save),
              child: const Text('Sauvegarder'),
            ),
          ],
        ),
      );
      if (!context.mounted) return;
      switch (choice) {
        case null:
        case _NewDraftChoice.cancel:
          return;
        case _NewDraftChoice.discard:
          break;
        case _NewDraftChoice.save:
          try {
            await controller.saveDraft();
          } catch (exception) {
            if (!context.mounted) return;
            messenger.showSnackBar(
              SnackBar(content: Text('Sauvegarde impossible : ${_errorMessage(exception)}')),
            );
            return;
          }
      }
      if (!context.mounted) return;
    }
    try {
      await controller.newDraft();
    } catch (exception) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Nouveau trajet impossible : ${_errorMessage(exception)}')),
      );
      return;
    }
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Nouveau trajet démarré'), duration: Duration(seconds: 2)),
    );
  }

  /// Menu « Enregistrer une copie » : propose un nom par défaut pour la
  /// copie, laisse l'utilisateur le modifier ou l'annuler, puis sauvegarde
  /// le trajet en cours comme un nouveau trajet indépendant portant le nom
  /// choisi, sans modifier le trajet déjà chargé.
  Future<void> _onSaveDraftAsCopy(BuildContext context) async {
    Diag.event('Ui.tap', 'target=SelectedMarkersView.saveDraftAsCopy');
    final messenger = ScaffoldMessenger.of(context);
    // TextFormField avec initialValue plutôt qu'un TextEditingController
    // libéré après le dialogue : le sous-arbre du dialogue reste monté
    // pendant son animation de sortie, et un controller déjà détruit y
    // casserait le champ encore attaché.
    var enteredName = '${controller.displayDraftName} (copie)';
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enregistrer une copie'),
        content: TextFormField(
          key: const Key('copy-name-field'),
          initialValue: enteredName,
          autofocus: true,
          onChanged: (value) => enteredName = value,
          decoration: const InputDecoration(
            labelText: 'Nom de la copie',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('copy-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            key: const Key('copy-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(enteredName),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (!context.mounted || name == null) return;
    try {
      await controller.saveDraftAsCopy(name: name);
    } catch (exception) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Sauvegarde impossible : ${_errorMessage(exception)}')));
      return;
    }
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Copie enregistrée'), duration: Duration(seconds: 2)),
    );
  }

  static String _errorMessage(Object exception) => exception is StateError ? exception.message : '$exception';
}

enum _RouteMenuAction { newDraft, saveAsCopy, loadRoute }

enum _NewDraftChoice { save, discard, cancel }
