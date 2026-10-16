import 'package:flutter/material.dart';

import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

class MapMarkersButton extends StatelessWidget {
  const MapMarkersButton({super.key, required this.onPressed, this.markerCount = 0});

  final VoidCallback? onPressed;

  /// Nombre de repères actuellement sélectionnés, affiché dans le libellé
  /// pour situer l'état du trajet sans ouvrir la liste.
  final int markerCount;

  @override
  Widget build(BuildContext context) {
    return Diag.frequentSync(
      'MapMarkersButton.build',
      () => FloatingActionButton.extended(
        key: const Key('map-markers-button'),
        heroTag: 'map-markers-button',
        onPressed: onPressed == null
            ? null
            : () {
                Diag.event('Ui.tap', 'target=map-markers-button');
                onPressed!();
              },
        icon: const Icon(Icons.list_alt),
        label: Text(markerCount > 0 ? 'Repères · $markerCount' : 'Repères'),
      ),
      params: 'enabled=${onPressed != null} markers=$markerCount',
    );
  }
}
