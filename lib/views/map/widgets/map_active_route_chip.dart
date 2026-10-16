import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import 'package:casa_loop_engine/controllers/route_editor_controller.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';
import 'package:casa_loop_engine/helpers/themes/app_colors.dart';

/// Actions du menu de la chip « trajet actif ».
enum MapActiveRouteAction { edit, newDraft, library, details, exportGpx }

/// Chip persistante en haut de la carte : nom du trajet en cours d'édition
/// et pastille d'état (en préparation / à calculer / tracé prêt / tracé non
/// enregistré). Un appui ouvre un menu : Éditer, Nouveau trajet, Mes trajets.
///
/// Lit uniquement [RouteEditorController] — l'état de travail survit à la
/// navigation, la chip reflète donc toujours le trajet actif réel.
class MapActiveRouteChip extends StatelessWidget {
  const MapActiveRouteChip({super.key, required this.onAction});

  /// Action choisie dans le menu ; les dialogues et la navigation restent
  /// portés par la vue appelante.
  final void Function(MapActiveRouteAction action) onAction;

  @override
  Widget build(BuildContext context) {
    return Diag.frequentSync('MapActiveRouteChip.build', () {
      final editor = RouteEditorController.instance;
      return Obx(() {
        // Lecture réactive : nom, repères, tracé et drapeau « non
        // enregistré » — la chip se met à jour à chaque mutation.
        final name = editor.displayDraftName;
        final markerCount = editor.validatedMarkers.length;
        final hasTrace = editor.tracedItinerary.value != null;
        final unsaved = editor.unsavedTracedResult.value;
        final blocked = editor.mutationsBlocked;

        final (label, dotColor) = switch ((markerCount, hasTrace, unsaved)) {
          (_, true, true) => ('Tracé non enregistré', Colors.orange),
          (_, true, false) => ('Tracé prêt', Colors.green),
          (0 || 1, _, _) => ('En préparation', Colors.grey),
          (_, _, _) => ('Tracé à calculer', Colors.amber),
        };

        // Un tracé restauré au lancement est affiché sur la carte sans
        // résumé en bas : le détail et l'export restent accessibles ici.
        final summaryHidden = editor.startupTraceSummaryHidden.value;
        final exportEnabled = hasTrace && !editor.isTracing.value && !editor.isSearchingTarget.value;

        return PopupMenuButton<MapActiveRouteAction>(
          key: const Key('map-active-route-chip'),
          enabled: !blocked,
          onSelected: (action) {
            Diag.event('Ui.tap', 'target=map-active-route-chip action=${action.name}');
            onAction(action);
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: MapActiveRouteAction.edit,
              enabled: markerCount > 0,
              child: const Text('Éditer le trajet'),
            ),
            if (summaryHidden && hasTrace)
              const PopupMenuItem(value: MapActiveRouteAction.details, child: Text('Détails du tracé')),
            if (exportEnabled)
              const PopupMenuItem(value: MapActiveRouteAction.exportGpx, child: Text('Exporter GPX')),
            const PopupMenuItem(value: MapActiveRouteAction.newDraft, child: Text('Nouveau trajet')),
            const PopupMenuItem(value: MapActiveRouteAction.library, child: Text('Mes trajets')),
          ],
          child: Material(
            elevation: 4.r,
            borderRadius: BorderRadius.circular(20.r),
            color: AppColors.canvas,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8.r,
                    height: 8.r,
                    decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                  ),
                  SizedBox(width: 6.w),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 180.w),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(width: 6.w),
                  Text(label, maxLines: 1, style: Theme.of(context).textTheme.bodySmall),
                  Icon(Icons.arrow_drop_down, size: 20.r),
                ],
              ),
            ),
          ),
        );
      });
    }, params: 'chip');
  }
}
