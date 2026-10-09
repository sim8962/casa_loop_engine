import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/views/search/controllers/place_search_controller.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

Future<MapMarkerItem?> showMapSearchSheet(BuildContext context) => Diag.future(
  'showMapSearchSheet',
  () => showModalBottomSheet<MapMarkerItem>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const FractionallySizedBox(heightFactor: 0.75, child: MapSearchSheet()),
  ),
  result: (result) => result == null ? 'selected=null' : 'selected="${result.name}" id=${result.id}',
);

/// Vue principale du panneau de recherche.
///
/// Ne porte elle-même aucun état : la saisie (TextEditingController) et la
/// réinitialisation à l'ouverture sont déléguées au composant interne
/// [_MapSearchSheetBody], qui possède son propre cycle de vie `State`.
class MapSearchSheet extends GetView<PlaceSearchController> {
  const MapSearchSheet({super.key});

  @override
  Widget build(BuildContext context) {
    Diag.untilFirstFrame('MapSearchSheet.firstFrame');
    return Diag.sync('MapSearchSheet.build', () => _MapSearchSheetBody(controller: controller));
  }
}

class _MapSearchSheetBody extends StatefulWidget {
  const _MapSearchSheetBody({required this.controller});

  final PlaceSearchController controller;

  @override
  State<_MapSearchSheetBody> createState() => _MapSearchSheetBodyState();
}

class _MapSearchSheetBodyState extends State<_MapSearchSheetBody> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Diag.event('MapSearchSheet.initState');
    widget.controller.reset();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final placeSearchController = widget.controller;
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Rechercher', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  key: const Key('close-map-search'),
                  tooltip: 'Fermer',
                  onPressed: () {
                    Diag.event('MapSearchSheet.close');
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const Key('map-search-field'),
              controller: _searchController,
              autofocus: true,
              onChanged: placeSearchController.search,
              decoration: const InputDecoration(
                hintText: 'Ville, douar, RN, RR, RP…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const TabBar(
            tabs: [
              Tab(text: 'Lieux'),
              Tab(text: 'Routes'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                // `toList()` lit effectivement la liste observable dans la
                // portée de l'Obx : passer la RxList telle quelle ne
                // déclencherait aucune mise à jour.
                Obx(() => _ResultList(results: placeSearchController.places.toList())),
                Obx(() => _ResultList(results: placeSearchController.roads.toList())),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultList extends StatelessWidget {
  const _ResultList({required this.results});

  final List<MapMarkerItem> results;

  @override
  Widget build(BuildContext context) {
    return Diag.frequentSync('MapSearchSheet._ResultList.build', () {
      if (results.isEmpty) {
        return const Center(child: Text('Aucun résultat'));
      }

      return ListView.builder(
        itemCount: results.length,
        itemBuilder: (context, index) {
          final result = results[index];
          return ListTile(
            key: Key('search-result-${result.name}'),
            leading: const Icon(Icons.place_outlined),
            title: Text(result.name),
            subtitle: Text(result.type),
            onTap: () {
              Diag.event(
                'MapSearchSheet.resultSelected',
                'id=${result.id} name="${result.name}" type=${result.type}',
              );
              Navigator.of(context).pop(result);
            },
          );
        },
      );
    }, params: 'count=${results.length}');
  }
}
