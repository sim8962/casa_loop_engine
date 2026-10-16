import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0),
        child: Obx(() {
          final theme = Theme.of(context);
          final isDistance = _controller.loopTargetMode.value == LoopTargetMode.distance;
          // Une valeur saisie mais invalide (≤ 0 ou non finie) est
          // refusée par le modèle et signalée ici plutôt qu'ignorée.
          final rawValue = isDistance
              ? _controller.targetDistanceKm.value
              : _controller.targetDurationHours.value;
          final hasInvalidTarget = rawValue != null && !(rawValue.isFinite && rawValue > 0);
          final toggles = ToggleButtons(
            isSelected: [isDistance, !isDistance],
            onPressed: _controller.mutationsBlocked
                ? null
                : (index) {
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
            borderRadius: BorderRadius.circular(8.r),
            // minHeight non convertie : plancher de zone tactile réel,
            // déjà volontairement compact — une conversion .h la
            // réduirait sur les écrans de hauteur < 844.
            constraints: BoxConstraints(minWidth: 85.w, minHeight: 40),
            children: const [Text('Distance'), Text('Durée')],
          );
          final field = TextField(
            controller: isDistance ? _distanceController : _durationController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              suffixText: isDistance ? 'km' : 'h',
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: hasInvalidTarget ? 'Cible invalide : valeur > 0 requise' : null,
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
          );
          // Disposition selon la largeur disponible : les deux contrôles
          // côte à côte demandent ~390 pt avec le texte agrandi ; sous
          // ce seuil (largeurs de téléphone) ils s'empilent plutôt que
          // de déborder — les zones tactiles ne sont pas réduites.
          return LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 440) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    toggles,
                    SizedBox(height: 8.h),
                    field,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: toggles),
                  SizedBox(width: 12.w),
                  Expanded(child: field),
                ],
              );
            },
          );
        }),
      );
    });
  }
}
