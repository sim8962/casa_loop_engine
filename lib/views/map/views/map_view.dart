import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:casa_loop_engine/controllers/route_editor_controller.dart';
import 'package:casa_loop_engine/models/computed_route.dart';
import 'package:casa_loop_engine/models/route_target_result.dart';
import 'package:casa_loop_engine/services/export/gpx_export_service.dart';
import 'package:casa_loop_engine/routes/app_routes.dart';
import 'package:casa_loop_engine/helpers/themes/app_colors.dart';
import 'package:casa_loop_engine/views/search/views/map_search_sheet.dart';
import 'package:casa_loop_engine/views/map/controllers/map_controller.dart';
import 'package:casa_loop_engine/helpers/geo/map_camera.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';
import 'package:casa_loop_engine/routes/route_draft_loader.dart';
import 'package:casa_loop_engine/views/common/route_dialogs.dart';
import 'package:casa_loop_engine/views/map/widgets/map_active_route_chip.dart';
import 'package:casa_loop_engine/views/map/widgets/map_marker_details.dart';
import 'package:casa_loop_engine/views/map/widgets/map_markers_button.dart';
import 'package:casa_loop_engine/views/map/widgets/map_markers_list_sheet.dart';
import 'package:casa_loop_engine/views/map/widgets/map_search_button.dart';
import 'package:casa_loop_engine/views/map/widgets/map_zoom_controls.dart';

class MapView extends GetView<MapController> {
  const MapView({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Diag.sync('MapView.build', () {
        final editor = RouteEditorController.instance;
        final startup = editor.isInitializing.value;
        final storageError = editor.workingStateError.value;
        final traceError = editor.traceError.value;
        if (startup) return const Center(child: CircularProgressIndicator());
        final error = controller.error.value;
        if (error != null) {
          return MapErrorView(message: error);
        }
        final mapPack = controller.mapPack.value;
        if (mapPack == null) {
          return ColoredBox(
            color: AppColors.canvas,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            _MapContent(stylePath: mapPack.stylePath),
            if (storageError != null || traceError != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Material(
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (storageError != null)
                          ListTile(
                            title: Text(storageError),
                            trailing: TextButton(
                              onPressed: () async {
                                try {
                                  await editor.retryWorkingState();
                                } catch (_) {}
                              },
                              child: const Text('Réessayer'),
                            ),
                          ),
                        // Erreur de calcul persistante : visible aussi au
                        // retour sur la carte, jusqu'à fermeture explicite,
                        // nouveau calcul ou invalidation du tracé.
                        if (traceError != null)
                          ColoredBox(
                            color: Theme.of(context).colorScheme.errorContainer,
                            child: ListTile(
                              title: Text(traceError),
                              trailing: IconButton(
                                key: const Key('map-trace-error-dismiss'),
                                tooltip: 'Fermer',
                                onPressed: () => editor.traceError.value = null,
                                icon: const Icon(Icons.close),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      }, result: (widget) => 'view=${widget.runtimeType}'),
    );
  }
}

/// Carte et calques d'interface. Le `MapLibreMap` est isolé des `Obx` des
/// surcouches pour ne jamais être reconstruit lorsqu'un repère change.
class _MapContent extends GetView<MapController> {
  const _MapContent({required this.stylePath});

  final String stylePath;

  Future<void> _openSearch(BuildContext context) => Diag.future('MapView._openSearch', () async {
    final result = await showMapSearchSheet(context);
    if (result == null) {
      return;
    }
    await controller.showPendingMarker(result);
  }, result: (_) => 'pendingMarker=${controller.pendingMarker.value?.id}');

  Future<void> _openMarkersList(BuildContext context) => Diag.future(
    'MapView._openMarkersList',
    () async {
      final editor = RouteEditorController.instance;
      final selected = await showMapMarkersListSheet(
        context,
        markers: editor.validatedMarkers,
        displayName: (marker, index) => editor.markerDisplayNameFor(marker, index),
        onDelete: editor.deleteMarker,
        onReorder: editor.reorderMarkers,
        onRename: editor.renameMarker,
        onValidate: () async {
          await editor.saveMarkersOrder();
          Diag.event('Navigation.push', 'route=${AppRoutes.selectedMarkers}');
          // Le panneau se ferme avant de pousser le prochain écran.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Get.toNamed(AppRoutes.selectedMarkers);
          });
        },
      );
      if (selected == null) {
        return;
      }
      await controller.centerOn(selected);
    },
    params: 'markers=${RouteEditorController.instance.validatedMarkers.length}',
    result: (_) => 'done',
  );

  /// Action « Enregistrer » du bandeau de tracé : persiste la boucle
  /// calculée non encore enregistrée ([hasUnsavedTracedResult]) puis
  /// affiche une confirmation honnête — aucun recalcul moteur.
  Future<void> _saveTracedResult(BuildContext context) => Diag.future('MapView._saveTracedResult', () async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await RouteEditorController.instance.saveDraft();
    } catch (exception) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Sauvegarde impossible : $exception')));
      return;
    }
    if (!context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Trajet sauvegardé'), duration: Duration(seconds: 2)),
    );
  }, result: (_) => 'done');

  /// Menu de la chip « trajet actif » : ouverture de l'éditeur, nouveau
  /// trajet (avec protection « Sauvegarder / Abandonner / Annuler ») ou
  /// bibliothèque des trajets.
  Future<void> _onChipAction(BuildContext context, MapActiveRouteAction action) =>
      Diag.future('MapView._onChipAction', () async {
        final editor = RouteEditorController.instance;
        switch (action) {
          case MapActiveRouteAction.edit:
            if (editor.validatedMarkers.isEmpty) return;
            Get.toNamed(AppRoutes.selectedMarkers);
          case MapActiveRouteAction.newDraft:
            final messenger = ScaffoldMessenger.of(context);
            try {
              final started = await confirmAndStartNewDraft(context);
              if (!context.mounted || !started) return;
              messenger.hideCurrentSnackBar();
              messenger.showSnackBar(
                const SnackBar(content: Text('Nouveau trajet démarré'), duration: Duration(seconds: 2)),
              );
            } catch (exception) {
              if (!context.mounted) return;
              messenger.hideCurrentSnackBar();
              messenger.showSnackBar(SnackBar(content: Text('$exception')));
            }
          case MapActiveRouteAction.details:
            // Révèle le résumé du tracé restauré au lancement, masqué par
            // défaut pour ne pas occuper la carte au démarrage.
            editor.startupTraceSummaryHidden.value = false;
          case MapActiveRouteAction.exportGpx:
            await _exportGpx(context);
          case MapActiveRouteAction.library:
            openRouteLibrary(origin: 'map');
        }
      }, params: 'action=${action.name}');

  /// Action « Exporter GPX » du bandeau de tracé : délègue au contrôleur
  /// (génération + partage hors ligne, sans recalcul) puis traduit
  /// l'issue en SnackBar — un succès n'est annoncé que pour un partage
  /// réel, jamais pour une annulation ni un échec. [buttonContext] sert
  /// à ancrer la feuille de partage sur le bouton invoquant (iPad).
  Future<void> _exportGpx(BuildContext buttonContext) => Diag.future('MapView._exportGpx', () async {
    final editor = RouteEditorController.instance;
    // Ancre iPad : position globale du bouton « Exporter GPX ».
    final render = buttonContext.findRenderObject();
    final Rect? origin = render is RenderBox && render.hasSize
        ? render.localToGlobal(Offset.zero) & render.size
        : null;
    try {
      final result = await editor.exportGpx(shareOrigin: origin);
      if (!buttonContext.mounted) return;
      switch (result.status) {
        case GpxExportStatus.shared:
          ScaffoldMessenger.of(buttonContext)
              .showSnackBar(SnackBar(content: Text('GPX partagé : ${result.fileName ?? 'trajet.gpx'}')));
        case GpxExportStatus.cancelled:
          // Annulation utilisateur : aucun message de réussite.
          break;
        case GpxExportStatus.failed:
          ScaffoldMessenger.of(buttonContext).showSnackBar(
            SnackBar(content: Text('Export GPX impossible : ${result.errorMessage ?? 'erreur inconnue'}')),
          );
      }
    } catch (exception) {
      if (!buttonContext.mounted) return;
      ScaffoldMessenger.of(buttonContext).showSnackBar(SnackBar(content: Text('$exception')));
    }
  }, result: (_) => 'done');

  @override
  Widget build(BuildContext context) {
    Diag.untilFirstFrame('MapView.firstFrame');
    return Diag.sync('_MapContent.build', () {
      final editor = RouteEditorController.instance;
      return Scaffold(
        backgroundColor: AppColors.canvas,
        body: Stack(
          fit: StackFit.expand,
          children: [
            SafeArea(
              child: SizedBox.expand(
                child: MapLibreMap(
                  styleString: stylePath,
                  initialCameraPosition: CameraPosition(
                    target: MapCamera.contentCenter,
                    zoom: MapCamera.initialZoom,
                  ),
                  minMaxZoomPreference: const MinMaxZoomPreference(MapCamera.minZoom, MapCamera.maxZoom),
                  cameraTargetBounds: CameraTargetBounds(MapCamera.contentBounds),
                  trackCameraPosition: true,
                  rotateGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  scrollGesturesEnabled: true,
                  zoomGesturesEnabled: true,
                  compassEnabled: false,
                  myLocationEnabled: false,
                  onMapCreated: controller.onMapCreated,
                  onCameraMove: controller.onCameraMove,
                  onCameraIdle: () => unawaited(controller.enforceBounds()),
                  onMapClick: (point, latLng) {
                    Diag.event(
                      'MapView.onMapClick',
                      'lat=${latLng.latitude.toStringAsFixed(5)} '
                          'lon=${latLng.longitude.toStringAsFixed(5)}',
                    );
                    unawaited(controller.showPendingMarkerAt(latLng));
                  },
                  onMapLongClick: (point, latLng) {
                    Diag.event(
                      'MapView.onMapLongClick',
                      'lat=${latLng.latitude.toStringAsFixed(5)} '
                          'lon=${latLng.longitude.toStringAsFixed(5)}',
                    );
                    unawaited(controller.showPendingMarkerAt(latLng));
                  },
                  onStyleLoadedCallback: controller.onStyleLoaded,
                ),
              ),
            ),
            // Numéros des repères validés : surcouche Flutter (texte natif,
            // lisible hors ligne sans glyphes de serveur) plutôt qu'un calque
            // MapLibre, positionnée par [MapController.markerNumberLabels].
            // `IgnorePointer` laisse tous les gestes de la carte (dont le
            // glisser-déposer des cercles) passer au travers.
            IgnorePointer(
              child: Obx(() {
                return Stack(
                  children: [
                    for (final label in controller.markerNumberLabels)
                      Positioned(
                        left: label.dx - 10.r,
                        top: label.dy - 10.r,
                        child: _MarkerNumberBadge(number: label.number),
                      ),
                  ],
                );
              }),
            ),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.all(16.r),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Obx(() {
                    final enabled = controller.styleLoaded.value && !editor.mutationsBlocked;
                    return MapZoomControls(
                      onZoomIn: enabled ? () => controller.zoomBy(1) : null,
                      onZoomOut: enabled ? () => controller.zoomBy(-1) : null,
                    );
                  }),
                ),
              ),
            ),
            // Chip « trajet actif » : nom du trajet édité et son état,
            // avec le menu Éditer / Nouveau trajet / Mes trajets.
            SafeArea(
              child: Padding(
                padding: EdgeInsets.all(16.r),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: MapActiveRouteChip(onAction: (action) => unawaited(_onChipAction(context, action))),
                ),
              ),
            ),
            // Zone du bas composée : résumé du tracé et commandes occupent
            // chacun une place distincte dans la même colonne — aucun
            // chevauchement possible, quelle que soit la hauteur du bandeau.
            Obx(() {
              final enabled = controller.styleLoaded.value && !editor.mutationsBlocked;
              final markerCount = editor.validatedMarkers.length;
              final itinerary = editor.tracedItinerary.value;
              // Un tracé restauré au lancement reste sans résumé en bas :
              // la carte n'est pas occupée avant toute action de la session.
              final summaryHidden = editor.startupTraceSummaryHidden.value;
              return MapBottomOverlay(
                controlsVisible: !summaryHidden,
                itinerary: summaryHidden ? null : itinerary,
                resultUnsaved: editor.unsavedTracedResult.value,
                onSaveResult: enabled && !editor.isSavingDraft.value && !editor.isTracing.value
                    ? () => unawaited(_saveTracedResult(context))
                    : null,
                targetComparison: editor.targetComparison,
                targetSearchResult: editor.targetSearchResult.value,
                isSearchingTarget: editor.isSearchingTarget.value,
                onAdjustToTarget: enabled
                    ? () => unawaited(
                        editor.adjustRouteToTarget().catchError((Object error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
                          }
                          return;
                        }),
                      )
                    : null,
                onStopTargetSearch: editor.stopTargetSearch,
                // Export de la boucle retenue : désactivé tant qu'un
                // calcul ou une recherche rend le résultat instable.
                onExportGpx: enabled && !editor.isTracing.value && !editor.isSearchingTarget.value
                    ? (buttonContext) => unawaited(_exportGpx(buttonContext))
                    : null,
                controls: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Accès à la liste des repères (ordonner, renommer,
                    // supprimer) — icône seule, la feuille mène ensuite
                    // aux réglages via « Réglages du trajet ».
                    MapSearchButton(onPressed: enabled ? () => _openSearch(context) : null),

                    if (markerCount >= 2) ...[
                      SizedBox(width: 12.w),
                      MapMarkersButton(
                        markerCount: markerCount,
                        onPressed: enabled ? () => _openMarkersList(context) : null,
                      ),
                    ],

                    // MapLoadDraftButton(controller: editor),
                  ],
                ),
              );
            }),
            Obx(() {
              final pendingMarker = controller.pendingMarker.value;
              if (pendingMarker == null) {
                return const SizedBox.shrink();
              }
              return Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: MapMarkerDetails(
                    marker: pendingMarker,
                    onNameChanged: controller.setPendingMarkerName,
                    onAdd: () async {
                      try {
                        await controller.validatePendingMarker();
                      } catch (exception) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$exception')));
                      }
                    },
                    onDismiss: () => unawaited(controller.clearPendingMarker()),
                  ),
                ),
              );
            }),
          ],
        ),
      );
    }, result: (_) => 'mapReady');
  }
}

String _routeDuration(double seconds) {
  final totalMinutes = (seconds / 60).round();
  if (totalMinutes < 60) return '$totalMinutes min';
  return '${totalMinutes ~/ 60} h ${(totalMinutes % 60).toString().padLeft(2, '0')}';
}

/// Écart signé et relatif d'une comparaison à la cible, dans l'unité de
/// la cible (« +12,4 km (+10,3 %) », « −0,5 h (−4,9 %) »).
String _targetDeltaText(RouteTargetComparison comparison) {
  final unit = comparison.target.unit == RouteTargetUnit.kilometers ? 'km' : 'h';
  final delta = comparison.signedDelta;
  final percent = comparison.relativeDelta * 100;
  return '${delta >= 0 ? '+' : '−'}${delta.abs().toStringAsFixed(1)} $unit '
      '(${percent >= 0 ? '+' : '−'}${percent.abs().toStringAsFixed(1)} %)';
}

/// Panneau de détail du tracé : un segment par ligne (identité
/// `Rep. X → Rep. Y` et mesures), déployé vers le haut au-dessus de la
/// rangée des commandes par [MapBottomOverlay]. Carte autonome, sans
/// positionnement propre ni état de repli — [onToggle] (en-tête +
/// chevron) demande le repli vers le résumé en ligne [RouteSummaryChip].
///
/// Hauteur bornée à ~30 % de l'écran, diminuée de [bottomReserve]
/// (place réservée à la rangée de commandes affichée sous le panneau)
/// et plafonnée à 200 pt : les détails par segment défilent dans cette
/// limite, tandis que le titre, le total et la mention « retour inclus »
/// restent toujours visibles, en dehors de la zone défilante.
///
/// Composant autonome (sans dépendance à [MapController] ni à la carte
/// native), pour rester testable isolément.
class RouteSummaryBanner extends StatelessWidget {
  const RouteSummaryBanner({
    super.key,
    required this.itinerary,
    this.bottomReserve = 0,
    required this.onToggle,
    this.targetComparison,
    this.targetSearchResult,
    this.isSearchingTarget = false,
    this.onAdjustToTarget,
    this.onStopTargetSearch,
    this.onExportGpx,
    this.resultUnsaved = false,
    this.onSaveResult,
  });

  final ComputedItinerary itinerary;

  /// `true` tant que le tracé retenu n'est pas encore écrit dans un
  /// trajet sauvegardé : le panneau affiche alors la pastille
  /// « Non enregistré » et l'action [onSaveResult].
  final bool resultUnsaved;

  /// Action « Enregistrer » du tracé non enregistré ; `null` désactive le
  /// bouton (sauvegarde ou calcul en cours).
  final VoidCallback? onSaveResult;

  /// Hauteur réservée sous le panneau (commandes du bas, marges) :
  /// retranchée du plafond de hauteur pour que panneau et commandes
  /// réunis laissent toujours une zone de carte utilisable.
  final double bottomReserve;

  /// Appui sur l'en-tête : demande le repli du panneau vers le résumé
  /// en ligne dans la rangée des commandes.
  final VoidCallback onToggle;

  /// Comparaison vivante mesures moteur ↔ cible active ; `null` sans
  /// cible valide — aucune ligne de cible n'est alors affichée.
  final RouteTargetComparison? targetComparison;

  /// Bilan de la dernière recherche de variantes (issue, budgets) ;
  /// `null` tant qu'aucune n'a abouti.
  final RouteTargetSearchResult? targetSearchResult;

  /// `true` pendant la recherche de variantes : bouton « Arrêter ».
  final bool isSearchingTarget;

  /// Action « Ajuster à l'objectif » ; `null` désactive le bouton.
  final VoidCallback? onAdjustToTarget;

  /// Arrêt de la recherche en cours.
  final VoidCallback? onStopTargetSearch;

  /// Action « Exporter GPX » ; `null` désactive le bouton (calcul ou
  /// recherche en cours — le résultat exporté doit être stable). Le
  /// contexte du bouton est transmis pour ancrer la feuille de partage
  /// sur iPad.
  final void Function(BuildContext context)? onExportGpx;

  @override
  Widget build(BuildContext context) {
    final segments = itinerary.segments;
    // Plafond de hauteur : proportion de la hauteur réelle (MediaQuery,
    // non convertie), bornée par des plafonds de conception (.h) ;
    // [bottomReserve] reste la hauteur réelle réservée aux commandes.
    final maxHeight = (MediaQuery.sizeOf(context).height * 0.30 - bottomReserve).clamp(140.h, 200.h);
    return Material(
      elevation: 4.r,
      borderRadius: BorderRadius.circular(12.r),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: onToggle,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${segments.length} segment${segments.length > 1 ? 's' : ''} tracé${segments.length > 1 ? 's' : ''} — boucle complète — profil moto standard',
                        textAlign: TextAlign.center,
                        // Textes bornés en lignes : les parties fixes du
                        // panneau doivent toujours tenir dans le plafond
                        // de hauteur, quelle que soit la fonte ou la
                        // largeur — le détail défile, pas le cadre.
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(Icons.keyboard_arrow_down, size: 20.r),
                  ],
                ),
              ),
              SizedBox(height: 4.h),
              // Zone défilante unique : détails par segment puis total,
              // statut, actions et pied. Le nombre de segments n'est pas
              // borné par construction et les parties basses peuvent
              // dépasser le plafond de hauteur (texte agrandi, cible
              // active) — le contenu défile plutôt que de déborder ;
              // l'en-tête reste fixe pour replier le panneau.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Identités (numéros) figées au lancement du
                      // calcul : chaque segment garde le libellé
                      // `Rep. X → Rep. Y` de son couple dirigé.
                      for (final segment in segments)
                        Text(
                          'Rep. ${segment.identity.startNumber} → Rep. ${segment.identity.endNumber} : '
                          '${segment.route.distanceKm.toStringAsFixed(1)} km — ${_routeDuration(segment.route.durationSeconds)}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      SizedBox(height: 4.h),
                      Text(
                        'Total : ${itinerary.totalDistanceKm.toStringAsFixed(1)} km — '
                        '${_routeDuration(itinerary.totalDurationSeconds)} — retour inclus',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      if (targetComparison != null) ...[
                        SizedBox(height: 4.h),
                        // Comparaison mesures moteur ↔ cible : cible, résultat
                        // réel, écart signé et relatif — distinct des
                        // estimations indicatives de l'écran des repères.
                        Text(
                          'Cible : ${targetComparison!.target.label} — '
                          'moteur : ${targetComparison!.actualValue.toStringAsFixed(1)} '
                          '${targetComparison!.target.unit == RouteTargetUnit.kilometers ? 'km' : 'h'} — '
                          'écart ${_targetDeltaText(targetComparison!)}',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                      // Statut et actions : ils passent à la ligne (Wrap)
                      // quand la largeur ne suffit pas — texte agrandi ou
                      // téléphone étroit — plutôt que de déborder. La
                      // ligne n'existe que si une action est présentée.
                      // « Exporter GPX » est proposé même sans cible ; il
                      // reste visible mais désactivé quand le résultat
                      // est instable. La mention « durées hors pauses »
                      // est portée par le pied du bandeau pour les cibles
                      // en durée.
                      if (targetComparison != null || onExportGpx != null || resultUnsaved)
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // Résultat calculé pas encore écrit : signal
                            // honnête + action de sauvegarde directe.
                            if (resultUnsaved) ...[
                              Text(
                                'Tracé non enregistré',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.orange.shade800),
                              ),
                              TextButton(
                                key: const Key('save-traced-result-button'),
                                onPressed: onSaveResult,
                                child: const Text('Enregistrer'),
                              ),
                            ],
                            if (targetComparison != null) ...[
                              _TargetSearchStatus(
                                comparison: targetComparison!,
                                result: targetSearchResult,
                                isSearching: isSearchingTarget,
                              ),
                              if (!isSearchingTarget)
                                TextButton(
                                  onPressed: onAdjustToTarget,
                                  child: const Text('Ajuster à l\u2019objectif'),
                                )
                              else ...[
                                SizedBox(width: 8.w),
                                SizedBox(
                                  width: 14.r,
                                  height: 14.r,
                                  child: CircularProgressIndicator(strokeWidth: 2.r),
                                ),
                                SizedBox(width: 6.w),
                                Text('Recherche…', style: Theme.of(context).textTheme.bodySmall),
                                TextButton(onPressed: onStopTargetSearch, child: const Text('Arrêter')),
                              ],
                            ],
                            Builder(
                              builder: (buttonContext) => TextButton(
                                onPressed: onExportGpx == null ? null : () => onExportGpx!(buttonContext),
                                child: const Text('Exporter GPX'),
                              ),
                            ),
                          ],
                        ),
                      SizedBox(height: 2.h),
                      Text(
                        'Pack régional — navigation non validée · mesures moteur de la boucle complète'
                        // Cible en durée : honnêteté exigée — la durée moteur
                        // est une estimation de roulage, hors pauses, non
                        // garantie.
                        '${targetComparison != null && targetComparison!.target.unit == RouteTargetUnit.hours ? ' · durées hors pauses, estimées' : ''}',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ligne de statut de la recherche de variantes dans le bandeau de
/// résumé : pendant la recherche, ou bilan honnête de la dernière —
/// jamais le mot « impossible » : une recherche bornée ne prouve pas
/// qu'aucune solution n'existe.
class _TargetSearchStatus extends StatelessWidget {
  const _TargetSearchStatus({required this.comparison, required this.result, required this.isSearching});

  final RouteTargetComparison comparison;
  final RouteTargetSearchResult? result;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final String? text;
    if (isSearching) {
      text = null;
    } else if (result != null) {
      final counts =
          '${result!.candidateLoopsEvaluated} boucle${result!.candidateLoopsEvaluated > 1 ? 's' : ''}, '
          '${result!.engineCalls} appel${result!.engineCalls > 1 ? 's' : ''}';
      text = switch (result!.outcome) {
        RouteTargetSearchOutcome.reached =>
          result!.itineraryChanged ? 'Cible approchée (±5 %) — variante retenue' : 'Cible approchée (±5 %)',
        RouteTargetSearchOutcome.notReached => 'Cible non atteinte dans les variantes explorées ($counts)',
        RouteTargetSearchOutcome.cancelled => 'Recherche arrêtée — meilleur résultat conservé ($counts)',
      };
    } else {
      text = comparison.withinTolerance ? 'Cible approchée (±5 %)' : null;
    }
    if (text == null) return const SizedBox.shrink();
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

/// Résumé compact du tracé inséré dans la rangée des commandes du bas
/// quand le panneau est replié : total « retour inclus » et mention du
/// pack tiennent sur deux lignes à hauteur de bouton. [onToggle]
/// redéploie le détail vers le haut (voir [MapBottomOverlay]).
class RouteSummaryChip extends StatelessWidget {
  const RouteSummaryChip({super.key, required this.itinerary, required this.onToggle});

  final ComputedItinerary itinerary;

  /// Appui : demande le déploiement du panneau de détail au-dessus de
  /// la rangée des commandes.
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4.r,
      borderRadius: BorderRadius.circular(12.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: onToggle,
        child: ConstrainedBox(
          // Largeur bornée : le résumé partage la rangée avec les
          // commandes, il ne doit pas les chasser hors de l'écran.
          constraints: BoxConstraints(maxWidth: 360.w),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total : ${itinerary.totalDistanceKm.toStringAsFixed(1)} km — '
                        '${_routeDuration(itinerary.totalDurationSeconds)} — retour inclus',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Pack régional — navigation non validée · mesures moteur de la boucle complète',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 4.w),
                Icon(Icons.keyboard_arrow_up, size: 20.r),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Zone du bas de la carte : une seule rangée de commandes au bas
/// (« Recherche », « Repères », « Mes trajets » + le résumé compact
/// [RouteSummaryChip] quand le tracé est replié), surmontée du panneau de
/// détail [RouteSummaryBanner] quand il est déployé — le déploiement
/// s'ouvre donc vers le haut, la rangée reste à sa place.
///
/// Replié par défaut : le détail n'occupe la carte qu'après la publication
/// d'un **nouvel** itinéraire (calcul « Tracer », variante retenue ou
/// chargement explicite — retour visuel de l'action) ou sur appui de
/// l'utilisateur. Le repli manuel est respecté tant que l'itinéraire
/// affiché ne change pas (même position dans l'arbre).
///
/// Un tracé restauré silencieusement au lancement n'affiche rien du tout
/// en bas — ni résumé ni commandes ([controlsVisible] à `false`) : la
/// carte est entièrement libre au démarrage et les actions restent
/// accessibles depuis le menu de la chip « trajet actif ».
///
/// Placer rangée et panneau dans une même colonne alignée en bas, à
/// l'intérieur de la [SafeArea], réserve à chacun une place distincte :
/// le panneau ne peut jamais recouvrir les commandes, même sur une
/// petite hauteur d'écran en paysage — sa hauteur est bornée en
/// retranchant [controlsReserve], et ses détails défilent.
///
/// [controls] est injecté (rangée déjà construite par l'appelant) pour
/// garder ce composant testable sans [MapController] ni carte native.
class MapBottomOverlay extends StatefulWidget {
  const MapBottomOverlay({
    super.key,
    this.itinerary,
    required this.controls,
    this.targetComparison,
    this.targetSearchResult,
    this.isSearchingTarget = false,
    this.onAdjustToTarget,
    this.onStopTargetSearch,
    this.onExportGpx,
    this.resultUnsaved = false,
    this.onSaveResult,
    this.controlsVisible = true,
  });

  /// Hauteur réservée à la rangée de commandes et aux espacements sous le
  /// panneau : hauteur d'un `FloatingActionButton.extended` (~56) +
  /// espacement panneau/commandes + marge basse. Retranchée du plafond de
  /// hauteur du panneau via [RouteSummaryBanner.bottomReserve].
  static const double controlsReserve = 84;

  /// Itinéraire calculé à résumer ; le résumé n'apparaît que s'il est
  /// non nul et non vide.
  final ComputedItinerary? itinerary;

  /// Rangée des commandes du bas, déjà construite par l'appelant.
  final Widget controls;

  /// Données de la comparaison à la cible et de la recherche de
  /// variantes — transmises telles quelles à [RouteSummaryBanner].
  final RouteTargetComparison? targetComparison;
  final RouteTargetSearchResult? targetSearchResult;
  final bool isSearchingTarget;
  final VoidCallback? onAdjustToTarget;
  final VoidCallback? onStopTargetSearch;

  /// Action « Exporter GPX » transmise à [RouteSummaryBanner] ; `null`
  /// désactive le bouton.
  final void Function(BuildContext context)? onExportGpx;

  /// `true` tant que le tracé retenu n'est pas encore enregistré :
  /// transmis à [RouteSummaryBanner] qui affiche alors la pastille
  /// « Tracé non enregistré » et l'action [onSaveResult].
  final bool resultUnsaved;

  /// Action « Enregistrer » du tracé non enregistré, transmise à
  /// [RouteSummaryBanner].
  final VoidCallback? onSaveResult;

  /// `false` masque toute la zone du bas (tracé restauré au lancement :
  /// la carte reste libre, les actions passent par la chip « trajet
  /// actif »). Sans itinéraire ni commandes, rien n'est construit.
  final bool controlsVisible;

  @override
  State<MapBottomOverlay> createState() => _MapBottomOverlayState();
}

class _MapBottomOverlayState extends State<MapBottomOverlay> {
  /// Replié au premier affichage : un tracé restauré au lancement ne
  /// masque pas la carte. Voir [didUpdateWidget] pour le déploiement
  /// automatique à chaque nouvel itinéraire publié.
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  void didUpdateWidget(MapBottomOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Publication d'un nouvel itinéraire (calcul, variante retenue,
    // chargement) : le détail se déploie une fois comme retour de
    // l'action — un repli manuel reste respecté tant que le résultat
    // affiché ne change pas (comparaison par identité, jamais par valeur).
    if (widget.itinerary != null && !identical(oldWidget.itinerary, widget.itinerary)) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final itinerary = widget.itinerary;
    final showBanner = itinerary != null && itinerary.segments.isNotEmpty;
    if (!showBanner && !widget.controlsVisible) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Panneau de détail : déployé vers le haut au-dessus de la
              // rangée, qui garde sa place en bas.
              if (showBanner && _expanded)
                Padding(
                  padding: EdgeInsets.only(bottom: 10.h),
                  child: RouteSummaryBanner(
                    itinerary: itinerary,
                    bottomReserve: MapBottomOverlay.controlsReserve,
                    onToggle: _toggle,
                    targetComparison: widget.targetComparison,
                    targetSearchResult: widget.targetSearchResult,
                    isSearchingTarget: widget.isSearchingTarget,
                    onAdjustToTarget: widget.onAdjustToTarget,
                    onStopTargetSearch: widget.onStopTargetSearch,
                    onExportGpx: widget.onExportGpx,
                    resultUnsaved: widget.resultUnsaved,
                    onSaveResult: widget.onSaveResult,
                  ),
                ),
              if (widget.controlsVisible)
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Rangée défilable horizontalement : sur les petites
                    // largeurs, trois FloatingActionButton.extended
                    // dépasseraient sinon la largeur disponible
                    // (débordement RenderFlex).
                    final controlsRow = Align(
                      alignment: Alignment.centerLeft,
                      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: widget.controls),
                    );
                    final collapsed = showBanner && !_expanded;
                    // Replié : le résumé tient en ligne avec les commandes
                    // tant que la zone défilable laisse voir chaque
                    // commande entière. Sur téléphone étroit, résumé et
                    // commandes ne peuvent pas partager une ligne —
                    // le résumé passe sur sa propre ligne au-dessus,
                    // sinon le bouton le plus large resterait
                    // inappuyable au bout du défilement.
                    if (!collapsed || constraints.maxWidth >= 640) {
                      return Row(
                        children: [
                          if (collapsed) ...[
                            Flexible(
                              child: RouteSummaryChip(itinerary: itinerary, onToggle: _toggle),
                            ),
                            SizedBox(width: 12.w),
                          ],
                          Expanded(child: controlsRow),
                        ],
                      );
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RouteSummaryChip(itinerary: itinerary, onToggle: _toggle),
                        SizedBox(height: 8.h),
                        controlsRow,
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Badge numéroté superposé à un repère validé sur la carte. Texte natif
/// Flutter uniquement (pas de police chargée depuis un serveur), lisible
/// hors ligne.
class _MarkerNumberBadge extends StatelessWidget {
  const _MarkerNumberBadge({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20.r,
      height: 20.r,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black87,
        shape: BoxShape.circle,
        border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 1.5.r)),
      ),
      child: Text(
        '$number',
        style: TextStyle(color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class MapErrorView extends StatelessWidget {
  const MapErrorView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Diag.sync(
      'MapErrorView.build',
      () => ColoredBox(
        color: AppColors.canvas,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24.r),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.error, fontSize: 16.sp),
            ),
          ),
        ),
      ),
      params: 'messageBytes=${message.length}',
    );
  }
}
