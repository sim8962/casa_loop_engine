import 'package:flutter/material.dart';

import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

class MapZoomControls extends StatelessWidget {
  const MapZoomControls({super.key, required this.onZoomIn, required this.onZoomOut});

  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;

  @override
  Widget build(BuildContext context) {
    return Diag.frequentSync(
      'MapZoomControls.build',
      () => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            key: const Key('map-zoom-in'),
            heroTag: 'map-zoom-in',
            tooltip: 'Zoom avant',
            onPressed: onZoomIn == null
                ? null
                : () {
                    Diag.event('Ui.tap', 'target=map-zoom-in');
                    onZoomIn!();
                  },
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            key: const Key('map-zoom-out'),
            heroTag: 'map-zoom-out',
            tooltip: 'Zoom arrière',
            onPressed: onZoomOut == null
                ? null
                : () {
                    Diag.event('Ui.tap', 'target=map-zoom-out');
                    onZoomOut!();
                  },
            child: const Icon(Icons.remove),
          ),
        ],
      ),
      params: 'enabled=${onZoomIn != null}',
    );
  }
}
