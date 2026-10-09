import 'package:flutter/material.dart';

import 'package:casa_loop_engine/helpers/themes/app_colors.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Thème applicatif. Reproduit à l'identique le thème utilisé avant la
/// migration MVC + GetX afin de ne pas modifier le rendu existant.
abstract final class AppTheme {
  static ThemeData get light => Diag.sync(
    'AppTheme.light',
    () => ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: AppColors.seed)),
  );
}
