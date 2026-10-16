import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Ouvre l'écran "Mes repères". Retourne le repère sélectionné pour
/// recentrage, ou `null` si l'utilisateur ferme l'écran sans sélection.
Future<MapMarkerItem?> showMapMarkersListSheet(
  BuildContext context, {
  required List<MapMarkerItem> markers,
  required FutureOr<void> Function(MapMarkerItem) onDelete,
  required ReorderCallback onReorder,
  required FutureOr<void> Function() onValidate,
  FutureOr<void> Function(MapMarkerItem marker, String newName)? onRename,
  String Function(MapMarkerItem marker, int index)? displayName,
}) => Diag.future(
  'showMapMarkersListSheet',
  () => showModalBottomSheet<MapMarkerItem>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      // La feuille se soulève au-dessus du clavier : sinon le bouton
      // « Valider » et le bas de la liste restent cachés.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: FractionallySizedBox(
        heightFactor: 0.75,
        child: MapMarkersListSheet(
          markers: markers,
          onDelete: onDelete,
          onReorder: onReorder,
          onValidate: onValidate,
          onRename: onRename,
          displayName: displayName,
        ),
      ),
    ),
  ),
  params: 'markers=${markers.length}',
  result: (selected) => selected == null ? 'selected=null' : 'selected="${selected.name}" id=${selected.id}',
);

class MapMarkersListSheet extends StatefulWidget {
  const MapMarkersListSheet({
    super.key,
    required this.markers,
    required this.onDelete,
    required this.onReorder,
    required this.onValidate,
    this.onRename,
    this.displayName,
  });

  final List<MapMarkerItem> markers;
  final FutureOr<void> Function(MapMarkerItem) onDelete;
  final ReorderCallback onReorder;
  final FutureOr<void> Function() onValidate;
  final FutureOr<void> Function(MapMarkerItem marker, String newName)? onRename;
  final String Function(MapMarkerItem marker, int index)? displayName;

  @override
  State<MapMarkersListSheet> createState() => _MapMarkersListSheetState();
}

class _MapMarkersListSheetState extends State<MapMarkersListSheet> {
  late List<MapMarkerItem> _markers;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Diag.event('MapMarkersListSheet.initState', 'markers=${widget.markers.length}');
    _markers = List.of(widget.markers);
  }

  Future<void> _confirmDelete(MapMarkerItem marker) async {
    if (_busy) return;
    final confirmed = await Diag.future(
      'MapMarkersListSheet.deleteDialog',
      () => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Supprimer ce repère ?'),
          content: Text('« ${marker.name} » sera définitivement supprimé.'),
          actions: [
            TextButton(
              onPressed: () {
                Diag.event('MapMarkersListSheet.deleteCancel');
                Navigator.of(context).pop(false);
              },
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                Diag.event('MapMarkersListSheet.deleteConfirm');
                Navigator.of(context).pop(true);
              },
              child: const Text('Supprimer'),
            ),
          ],
        ),
      ),
      params: 'markerId=${marker.id}',
      result: (result) => 'confirmed=$result',
    );
    if (!mounted || confirmed != true || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onDelete(marker);
      if (mounted) setState(() => _markers = List.of(widget.markers));
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Suppression impossible : $exception")));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onReorder(int oldIndex, int newIndex) => Diag.sync('MapMarkersListSheet._onReorder', () {
    if (_busy) return;
    widget.onReorder(oldIndex, newIndex);
    setState(() => _markers = List.of(widget.markers));
  }, params: 'old=$oldIndex new=$newIndex');

  /// Renomme [marker] : champ prérempli avec le nom actuel, « Annuler » ne
  /// produit aucune modification. En cas d'échec de persistance, aucun
  /// succès n'est affiché : l'erreur remontée par [onRename] est montrée
  /// telle quelle.
  Future<void> _rename(MapMarkerItem marker) async {
    final onRename = widget.onRename;
    if (onRename == null || _busy) return;
    var enteredName = marker.name;
    final result = await Diag.future(
      'MapMarkersListSheet.renameDialog',
      () => showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Renommer'),
          content: TextFormField(
            key: const Key('rename-marker-field'),
            initialValue: enteredName,
            autofocus: true,
            onChanged: (value) => enteredName = value,
            decoration: const InputDecoration(labelText: 'Nom', isDense: true, border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
              key: const Key('rename-marker-cancel'),
              onPressed: () {
                Diag.event('MapMarkersListSheet.renameCancel');
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const Key('rename-marker-confirm'),
              onPressed: () {
                Diag.event('MapMarkersListSheet.renameConfirm');
                Navigator.of(dialogContext).pop(enteredName);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
      params: 'markerId=${marker.id}',
      result: (name) => 'confirmed=${name != null}',
    );
    if (!mounted || result == null || _busy) return;
    setState(() => _busy = true);
    try {
      await onRename(marker, result);
      if (mounted) setState(() => _markers = List.of(widget.markers));
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Renommage impossible : $exception')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Diag.untilFirstFrame('MapMarkersListSheet.firstFrame');
    return Diag.sync('MapMarkersListSheet.build', () {
      return Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 0, 8.w, 8.h),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Mes repères',
                    style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  key: const Key('close-markers-list'),
                  tooltip: 'Fermer',
                  onPressed: () {
                    Diag.event('MapMarkersListSheet.close');
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: _markers.isEmpty
                ? const Center(child: Text('Aucun repère sélectionné'))
                : ReorderableListView.builder(
                    itemCount: _markers.length,
                    onReorderItem: _onReorder,
                    itemBuilder: (context, index) {
                      Diag.frequent(
                        'MapMarkersListSheet.itemBuilder',
                        'index=$index count=${_markers.length}',
                      );
                      final marker = _markers[index];
                      final number = index + 1;
                      final subtitle = marker.roadRef != null
                          ? '${marker.type} — ${marker.roadRef}'
                          : '${marker.type} — ${marker.latitude.toStringAsFixed(4)}, ${marker.longitude.toStringAsFixed(4)}';
                      return ListTile(
                        key: Key('marker-list-item-${marker.id}'),
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_handle)),
                            SizedBox(width: 12.w),
                            CircleAvatar(
                              radius: 14.r,
                              child: Text('$number', style: TextStyle(fontSize: 12.sp)),
                            ),
                            SizedBox(width: 8.w),
                            const Icon(Icons.location_on),
                          ],
                        ),
                        title: Text(widget.displayName?.call(marker, index) ?? marker.name),
                        subtitle: Text(subtitle),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.onRename != null)
                              IconButton(
                                key: Key('marker-list-rename-${marker.id}'),
                                tooltip: 'Renommer',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () {
                                  Diag.event(
                                    'Ui.tap',
                                    'target=MapMarkersListSheet.rename '
                                        'markerId=${marker.id}',
                                  );
                                  _rename(marker);
                                },
                              ),
                            IconButton(
                              key: Key('marker-list-delete-${marker.id}'),
                              tooltip: 'Supprimer',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () {
                                Diag.event(
                                  'Ui.tap',
                                  'target=MapMarkersListSheet.delete '
                                      'markerId=${marker.id}',
                                );
                                _confirmDelete(marker);
                              },
                            ),
                          ],
                        ),
                        onTap: () {
                          Diag.event(
                            'MapMarkersListSheet.markerSelected',
                            'markerId=${marker.id} index=$index',
                          );
                          Navigator.of(context).pop(marker);
                        },
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 16.h),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('validate-markers-order'),
                  onPressed: _busy
                      ? null
                      : () async {
                          Diag.event('MapMarkersListSheet.validateOrder');
                          if (_busy) return;
                          setState(() => _busy = true);
                          try {
                            await widget.onValidate();
                            if (context.mounted) Navigator.of(context).pop();
                          } catch (exception) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Enregistrement impossible : $exception")),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  icon: const Icon(Icons.tune),
                  label: const Text('Réglages du trajet'),
                ),
              ),
            ),
          ),
        ],
      );
    }, params: 'markers=${_markers.length}');
  }
}
