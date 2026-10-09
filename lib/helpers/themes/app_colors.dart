import 'package:flutter/material.dart';
import 'package:hexcolor/hexcolor.dart';

import 'package:casa_loop_engine/helpers/constants/color_hex.dart';

/// Couleurs Flutter dérivées de [ColorHex], seule source de vérité.
abstract final class AppColors {
  /// Fond neutre commun à la carte et aux écrans de chargement/erreur.
  static final Color canvas = HexColor(ColorHex.canvas);

  static const Color seed = Colors.deepPurple;
  static const Color error = Colors.red;
}
