import 'package:flutter/material.dart';

import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

class MapMarkersButton extends StatelessWidget {
  const MapMarkersButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

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
        label: const Text('Mes repères'),
      ),
      params: 'enabled=${onPressed != null}',
    );
  }
}
