import 'package:flutter/material.dart';

import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

class MapSearchButton extends StatelessWidget {
  const MapSearchButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Diag.frequentSync(
      'MapSearchButton.build',
      () => FloatingActionButton.extended(
        key: const Key('map-search-button'),
        heroTag: 'map-search-button',
        onPressed: onPressed == null
            ? null
            : () {
                Diag.event('Ui.tap', 'target=map-search-button');
                onPressed!();
              },
        icon: const Icon(Icons.search),
        label: SizedBox.shrink(), //const Text('Recherche'),
      ),
      params: 'enabled=${onPressed != null}',
    );
  }
}
