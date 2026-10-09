import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';
import 'package:casa_loop_engine/controllers/route_editor_controller.dart';
import 'package:casa_loop_engine/routes/route_draft_loader.dart';

/// Bouton « Charger mes trajets » de l'écran carte, à côté de « Recherche »
/// et « Mes repères ». Accessible même sans repère actuellement sélectionné ;
/// désactivé pendant une sauvegarde ou un chargement déjà en cours. Ouvre la
/// bibliothèque des trajets sauvegardés via [openRouteLibrary].
class MapLoadDraftButton extends StatelessWidget {
  const MapLoadDraftButton({super.key, required this.controller});

  final RouteEditorController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final busy = controller.isSavingDraft.value || controller.isLoadingDraft.value;
      return Diag.frequentSync(
        'MapLoadDraftButton.build',
        () => FloatingActionButton.extended(
          key: const Key('map-load-draft-button'),
          heroTag: 'map-load-draft-button',
          onPressed: busy ? null : () => openRouteLibrary(origin: 'map'),
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('Charger mes trajets'),
        ),
        params: 'enabled=${!busy}',
      );
    });
  }
}
