import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:casa_loop_engine/controllers/route_editor_controller.dart';
import 'package:casa_loop_engine/routes/app_routes.dart';
import 'package:casa_loop_engine/helpers/themes/app_colors.dart';
import 'package:casa_loop_engine/views/search/views/map_search_sheet.dart';
import 'package:casa_loop_engine/views/map/controllers/map_controller.dart';
import 'package:casa_loop_engine/helpers/geo/map_camera.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';
import 'package:casa_loop_engine/views/map/widgets/map_load_draft_button.dart';
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
            if (storageError != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Material(
                  child: SafeArea(
                    bottom: false,
                    child: ListTile(
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
                        left: label.dx - 10,
                        top: label.dy - 10,
                        child: _MarkerNumberBadge(number: label.number),
                      ),
                  ],
                );
              }),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
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
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  // Rangée défilable horizontalement : sur les petites
                  // largeurs, trois FloatingActionButton.extended dépasseraient
                  // sinon la largeur disponible (débordement RenderFlex).
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Obx(() {
                      final enabled = controller.styleLoaded.value && !editor.mutationsBlocked;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MapSearchButton(onPressed: enabled ? () => _openSearch(context) : null),
                          const SizedBox(width: 12),
                          MapMarkersButton(onPressed: enabled ? () => _openMarkersList(context) : null),
                          const SizedBox(width: 12),
                          MapLoadDraftButton(controller: editor),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ),
            Obx(() {
              final route = editor.tracedSegment.value;
              if (route == null) {
                return const SizedBox.shrink();
              }
              // Identité (numéros) figée au lancement du calcul : si elle
              // manquait pour une raison quelconque, le libellé reste neutre
              // plutôt que d'afficher un numéro incorrect.
              final identity = editor.tracedSegmentIdentity.value;
              final segmentLabel = identity == null
                  ? 'Segment tracé — profil moto standard'
                  : 'Rep. ${identity.startNumber} → Rep. ${identity.endNumber} — profil moto standard';
              return Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              segmentLabel,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${route.distanceKm.toStringAsFixed(1)} km — ${_routeDuration(route.durationSeconds)}',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Graphe de test — restrictions de virage absentes',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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

/// Badge numéroté superposé à un repère validé sur la carte. Texte natif
/// Flutter uniquement (pas de police chargée depuis un serveur), lisible
/// hors ligne.
class _MarkerNumberBadge extends StatelessWidget {
  const _MarkerNumberBadge({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.black87,
        shape: BoxShape.circle,
        border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 1.5)),
      ),
      child: Text(
        '$number',
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
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
            padding: const EdgeInsets.all(24),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.error, fontSize: 16),
            ),
          ),
        ),
      ),
      params: 'messageBytes=${message.length}',
    );
  }
}
