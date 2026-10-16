import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import 'package:casa_loop_engine/views/selected_markers/controllers/selected_markers_controller.dart';
import 'package:casa_loop_engine/views/selected_markers/widgets/segment_color_picker.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Contrôle de préférence de route et de couleur entre deux repères
/// consécutifs (segment dirigé).
class RoutePreferenceTile extends GetView<SelectedMarkersController> {
  const RoutePreferenceTile({
    super.key,
    required this.segmentIndex,
    required this.startName,
    required this.endName,
    required this.startNumber,
    required this.endNumber,
  });

  final int segmentIndex;
  final String startName;
  final String endName;

  /// Numéros (position + 1) des repères de ce segment, pour le libellé
  /// `Rep. X → Rep. Y` affiché près du sélecteur de couleur.
  final int startNumber;
  final int endNumber;

  @override
  Widget build(BuildContext context) {
    return Diag.frequentSync('RoutePreferenceTile.build', () {
      return Obx(() {
        final value = controller.segmentRoutePreferences[segmentIndex];
        final label = controller.roadPreferenceLabel(value);
        final color = controller.colorForSegment(segmentIndex);
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$startName → $endName', style: Theme.of(context).textTheme.titleSmall),
              Text(
                'Rep. $startNumber → Rep. $endNumber',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
              SizedBox(height: 4.h),
              Text('Profil : $label', style: Theme.of(context).textTheme.bodySmall),
              Slider(
                value: value,
                min: 0,
                max: 100,
                divisions: 4,
                label: '${value.round()} %',
                onChanged: controller.mutationsBlocked
                    ? null
                    : (newValue) => controller.setRoutePreference(segmentIndex, newValue),
                onChangeEnd: (_) async {
                  try {
                    await controller.flushWorkingState();
                  } catch (exception) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('Enregistrement impossible : $exception')));
                  }
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Rapide', style: TextStyle(fontSize: 11.sp)),
                  Text('Trail', style: TextStyle(fontSize: 11.sp)),
                ],
              ),
              SizedBox(height: 8.h),
              Text('Couleur du tracé', style: Theme.of(context).textTheme.bodySmall),
              SizedBox(height: 4.h),
              SegmentColorPicker(
                palette: controller.segmentColorPalette,
                selected: color,
                onChanged: (newColor) => controller.setSegmentColor(segmentIndex, newColor),
              ),
            ],
          ),
        );
      });
    }, params: 'segment=$segmentIndex');
  }
}
