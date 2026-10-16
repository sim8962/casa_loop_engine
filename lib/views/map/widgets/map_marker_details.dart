import 'package:flutter/material.dart';

import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Fiche affichée au-dessus de la carte pour un repère temporaire, en
/// attendant que l'utilisateur le valide ou l'annule. Le champ « Nom »
/// est prérempli par le lieu le plus proche quand le référentiel en
/// connaît un, sinon par le générique
/// [MapMarkerItem.defaultPersonalizedName].
///
/// Le texte est piloté par un [TextEditingController] : une nouvelle
/// suggestion (ex. après un glisser-déposer) met le champ à jour tant
/// que l'utilisateur n'a rien saisi ; dès la première frappe, son texte
/// n'est plus jamais remplacé.
class MapMarkerDetails extends StatefulWidget {
  const MapMarkerDetails({
    super.key,
    required this.marker,
    required this.onAdd,
    required this.onDismiss,
    this.onNameChanged,
  });

  final MapMarkerItem marker;
  final VoidCallback onAdd;
  final VoidCallback onDismiss;

  /// Saisie du nom du repère temporaire ; `null` laisse le champ
  /// désactivé (tests sans carte).
  final void Function(String name)? onNameChanged;

  @override
  State<MapMarkerDetails> createState() => _MapMarkerDetailsState();
}

class _MapMarkerDetailsState extends State<MapMarkerDetails> {
  late final TextEditingController _nameController;

  /// `true` dès la première frappe : les changements de nom venant du
  /// contrôleur (suggestions) n'écrasent plus la saisie.
  bool _userEditedName = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.marker.name);
  }

  @override
  void didUpdateWidget(MapMarkerDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.marker.id != widget.marker.id) {
      // Nouvelle sélection : la saisie repart du nom du nouveau repère.
      _userEditedName = false;
      _nameController.text = widget.marker.name;
    } else if (!_userEditedName && _nameController.text != widget.marker.name) {
      _nameController.text = widget.marker.name;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final marker = widget.marker;
    return Diag.sync(
      'MapMarkerDetails.build',
      () => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Card(
          key: const Key('map-marker-details'),
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        key: const Key('map-marker-name'),
                        controller: _nameController,
                        onChanged: (value) {
                          _userEditedName = true;
                          widget.onNameChanged?.call(value);
                        },
                        decoration: const InputDecoration(
                          labelText: 'Nom',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${marker.latitude.toStringAsFixed(5)}, '
                        '${marker.longitude.toStringAsFixed(5)}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const Key('map-marker-details-add'),
                  onPressed: () {
                    Diag.event('Ui.tap', 'target=MapMarkerDetails.add');
                    widget.onAdd();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter'),
                ),
                IconButton(
                  key: const Key('map-marker-details-dismiss'),
                  tooltip: 'Annuler la sélection',
                  onPressed: () {
                    Diag.event('Ui.tap', 'target=MapMarkerDetails.dismiss');
                    widget.onDismiss();
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ),
      params: 'markerId=${marker.id} name="${marker.name}"',
    );
  }
}
