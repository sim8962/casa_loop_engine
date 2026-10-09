import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:casa_loop_engine/views/selected_markers/controllers/selected_markers_controller.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Champ « Nom du trajet » : distinct des champs Distance/Durée, affiche le
/// nom du trajet chargé (personnalisé ou par défaut, stable) et permet sa
/// modification.
class RouteNameField extends StatefulWidget {
  const RouteNameField({super.key});

  @override
  State<RouteNameField> createState() => _RouteNameFieldState();
}

class _RouteNameFieldState extends State<RouteNameField> {
  late final SelectedMarkersController _controller = SelectedMarkersController.instance;
  late final TextEditingController _nameController;
  late final Worker _draftRestoreWorker;

  @override
  void initState() {
    super.initState();
    Diag.event('RouteNameField.initState');
    _nameController = TextEditingController(text: _controller.displayDraftName);
    // Un trajet chargé (ou un nouveau trajet démarré) remplace le nom
    // affiché : le TextEditingController doit être réécrit explicitement
    // pour que le champ affiché suive, comme pour les champs Distance/Durée.
    _draftRestoreWorker = ever(_controller.draftRestoreVersion, (_) {
      _nameController.text = _controller.displayDraftName;
    });
  }

  @override
  void dispose() {
    _draftRestoreWorker.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Diag.sync('RouteNameField.build', () {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Obx(() {
          return TextField(
            key: const Key('route-name-field'),
            controller: _nameController,
            enabled: !_controller.mutationsBlocked,
            decoration: const InputDecoration(
              labelText: 'Nom du trajet',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: _controller.setDraftName,
          );
        }),
      );
    });
  }
}
