import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:casa_loop_engine/controllers/route_editor_controller.dart';
import 'package:casa_loop_engine/models/route_draft.dart';
import 'package:casa_loop_engine/routes/app_routes.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Bibliothèque des trajets sauvegardés : liste chaque trajet par son nom,
/// sa date de sauvegarde et son nombre de repères. Un clic charge ses choix
/// puis revient à l'éditeur déjà ouvert s'il en existe un dans la pile de
/// navigation — sans empiler un second éditeur — ou l'ouvre sinon, sans
/// dialogue de confirmation.
class RouteLibraryView extends StatefulWidget {
  const RouteLibraryView({super.key});

  @override
  State<RouteLibraryView> createState() => _RouteLibraryViewState();
}

class _RouteLibraryViewState extends State<RouteLibraryView> {
  late Future<List<RouteDraft>> _draftsFuture;

  @override
  void initState() {
    super.initState();
    Diag.event('RouteLibraryView.initState');
    _draftsFuture = RouteEditorController.instance.listSavedDrafts();
  }

  void _reload() {
    setState(() {
      _draftsFuture = RouteEditorController.instance.listSavedDrafts();
    });
  }

  static String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
  }

  Future<void> _onSelect(RouteDraft draft) async {
    final id = draft.id;
    if (id == null) return;
    Diag.event('Ui.tap', 'target=RouteLibraryView.selectDraft id=$id');
    final messenger = ScaffoldMessenger.of(context);
    try {
      await RouteEditorController.instance.loadDraft(id);
    } catch (exception) {
      Diag.error('RouteLibraryView.selectDraft', exception);
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Chargement impossible')));
      return;
    }
    if (!context.mounted) return;
    // Ferme la bibliothèque : si l'éditeur est déjà ouvert dessous (accès
    // depuis « Repères choisis »), on y revient tel quel — ses champs se
    // mettent à jour via draftRestoreVersion. Sinon on l'ouvre.
    Get.back();
    if (Get.currentRoute != AppRoutes.selectedMarkers) {
      await Get.toNamed(AppRoutes.selectedMarkers);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Diag.sync('RouteLibraryView.build', () {
      return Scaffold(
        appBar: AppBar(title: const Text('Mes trajets')),
        body: FutureBuilder<List<RouteDraft>>(
          future: _draftsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Chargement impossible : ${snapshot.error}'),
                    TextButton(
                      key: const Key('route-library-retry'),
                      onPressed: _reload,
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              );
            }
            final drafts = snapshot.data ?? const <RouteDraft>[];
            if (drafts.isEmpty) {
              return const Center(child: Text('Aucun trajet sauvegardé'));
            }
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView.separated(
                key: const Key('route-library-list'),
                itemCount: drafts.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final draft = drafts[index];
                  final name = draft.name.isEmpty
                      ? RouteEditorController.defaultDraftName(draft.createdAt)
                      : draft.name;
                  return ListTile(
                    key: Key('route-library-item-${draft.id}'),
                    title: Text(name),
                    subtitle: Text('${_formatDate(draft.savedAt)} — ${draft.markers.length} repères'),
                    onTap: () => _onSelect(draft),
                  );
                },
              ),
            );
          },
        ),
      );
    });
  }
}
