import 'package:flutter/material.dart';

import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Fiche affichée au-dessus de la carte pour un repère temporaire, en
/// attendant que l'utilisateur le valide ou l'annule.
class MapMarkerDetails extends StatelessWidget {
  const MapMarkerDetails({super.key, required this.marker, required this.onAdd, required this.onDismiss});

  final MapMarkerItem marker;
  final VoidCallback onAdd;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Diag.sync(
      'MapMarkerDetails.build',
      () => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Card(
          key: const Key('map-marker-details'),
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        marker.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${marker.latitude.toStringAsFixed(5)}, '
                        '${marker.longitude.toStringAsFixed(5)}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const Key('map-marker-details-add'),
                  onPressed: () {
                    Diag.event('Ui.tap', 'target=MapMarkerDetails.add');
                    onAdd();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter'),
                ),
                IconButton(
                  key: const Key('map-marker-details-dismiss'),
                  tooltip: 'Annuler la sélection',
                  onPressed: () {
                    Diag.event('Ui.tap', 'target=MapMarkerDetails.dismiss');
                    onDismiss();
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ),
      params: 'markerId=${marker.id} name="${marker.name}"',
    );
  }
}
