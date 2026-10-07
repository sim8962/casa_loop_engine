import 'package:flutter/material.dart';

import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Petite palette de couleurs contrastées pour un segment dirigé : chaque
/// pastille représente une couleur de [palette], celle correspondant à
/// [selected] est mise en évidence. Sans dépendance externe : couleurs
/// hexadécimales `#RRGGBB` déjà utilisées par le reste de l'application.
class SegmentColorPicker extends StatelessWidget {
  const SegmentColorPicker({super.key, required this.palette, required this.selected, required this.onChanged});

  final List<String> palette;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Diag.sync('SegmentColorPicker.build', () {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final colorHex in palette)
            _Swatch(
              colorHex: colorHex,
              isSelected: colorHex.toUpperCase() == selected.toUpperCase(),
              onTap: () => onChanged(colorHex),
            ),
        ],
      );
    }, params: 'palette=${palette.length} selected=$selected');
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.colorHex, required this.isSelected, required this.onTap});

  final String colorHex;
  final bool isSelected;
  final VoidCallback onTap;

  Color get _color => Color(int.parse(colorHex.substring(1), radix: 16) + 0xFF000000);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('segment-color-swatch-$colorHex'),
      customBorder: const CircleBorder(),
      onTap: () {
        Diag.event('SegmentColorPicker.tap', 'color=$colorHex');
        onTap();
      },
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: _color,
          shape: BoxShape.circle,
          border: Border.all(color: isSelected ? Colors.black : Colors.black26, width: isSelected ? 2.5 : 1),
        ),
        child: isSelected
            ? const Icon(Icons.check, color: Colors.white, size: 16)
            : null,
      ),
    );
  }
}
