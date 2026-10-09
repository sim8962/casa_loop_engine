import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:casa_loop_engine/controllers/route_editor_controller.dart';
import 'package:casa_loop_engine/views/selected_markers/controllers/selected_markers_controller.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Sélecteur exclusif Distance / Durée et champ de saisie associé.
class TargetLoopFields extends StatefulWidget {
  const TargetLoopFields({super.key});

  @override
  State<TargetLoopFields> createState() => _TargetLoopFieldsState();
}

class _TargetLoopFieldsState extends State<TargetLoopFields> {
  late final SelectedMarkersController _controller = SelectedMarkersController.instance;
  late final TextEditingController _distanceController;
  late final TextEditingController _durationController;
  late final Worker _draftRestoreWorker;

  static String _distanceText(double? value) => value?.toStringAsFixed(0) ?? '';
  static String _durationText(double? value) => value?.toStringAsFixed(1) ?? '';

  @override
  void initState() {
    super.initState();
    Diag.event('TargetLoopFields.initState');
    _distanceController = TextEditingController(text: _distanceText(_controller.targetDistanceKm.value));
    _durationController = TextEditingController(text: _durationText(_controller.targetDurationHours.value));
    // Un brouillon chargé (démarrage ou action manuelle) remplace les
    // valeurs cibles, y compris par des valeurs nulles : modifier seulement
    // les Rx du controller ne suffit pas, les TextEditingController doivent
    // être réécrits explicitement pour que les champs affichés suivent.
    _draftRestoreWorker = ever(_controller.draftRestoreVersion, (_) {
      _distanceController.text = _distanceText(_controller.targetDistanceKm.value);
      _durationController.text = _durationText(_controller.targetDurationHours.value);
    });
  }

  @override
  void dispose() {
    _draftRestoreWorker.dispose();
    _distanceController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Diag.sync('TargetLoopFields.build', () {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Obx(() {
          final theme = Theme.of(context);
          final isDistance = _controller.loopTargetMode.value == LoopTargetMode.distance;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: ToggleButtons(
                  isSelected: [isDistance, !isDistance],
                  onPressed: _controller.mutationsBlocked ? null : (index) {
                    Diag.event('Ui.tap', 'target=loopTargetMode index=$index');
                    _controller.setLoopTargetMode(
                      index == 0 ? LoopTargetMode.distance : LoopTargetMode.duration,
                    );
                  },
                  color: theme.colorScheme.onSurface,
                  selectedColor: theme.colorScheme.onPrimary,
                  fillColor: theme.colorScheme.primary,
                  selectedBorderColor: theme.colorScheme.primary,
                  borderColor: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                  constraints: const BoxConstraints(minWidth: 85, minHeight: 40),
                  children: const [Text('Distance'), Text('Durée')],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: isDistance ? _distanceController : _durationController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    suffixText: isDistance ? 'km' : 'h',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  enabled: !_controller.mutationsBlocked,
                  onChanged: (text) {
                    final value = double.tryParse(text.replaceAll(',', '.'));
                    if (isDistance) {
                      _controller.setTargetDistanceKm(value);
                    } else {
                      _controller.setTargetDurationHours(value);
                    }
                  },
                ),
              ),
            ],
          );
        }),
      );
    });
  }
}
