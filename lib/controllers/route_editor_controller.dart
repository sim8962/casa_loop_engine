import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'package:casa_loop_engine/models/computed_route.dart';
import 'package:casa_loop_engine/models/map_marker_item.dart';
import 'package:casa_loop_engine/models/route_draft.dart';
import 'package:casa_loop_engine/models/route_draft_segment_preference.dart';
import 'package:casa_loop_engine/services/routing/offline_routing_service.dart';
import 'package:casa_loop_engine/services/repositories/marker_repository.dart';
import 'package:casa_loop_engine/services/repositories/objectbox_working_state_repository.dart';
import 'package:casa_loop_engine/services/repositories/route_draft_repository.dart';
import 'package:casa_loop_engine/services/repositories/route_preference_repository.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

/// Mode de cible pour la boucle : distance ou durée.
enum LoopTargetMode { distance, duration }

/// Levée lorsqu'un brouillon de trajet contient des données incohérentes
/// (repère invalide, mode inconnu, préférence hors bornes, segment manquant
/// ou dupliqué…). Échec explicite : aucune valeur par défaut silencieuse
/// n'est substituée, et l'état de travail n'est jamais modifié avant que
/// la validation ait réussi.
class InvalidRouteDraftException implements Exception {
  InvalidRouteDraftException(this.message);

  final String message;

  @override
  String toString() => 'InvalidRouteDraftException: $message';
}

/// État partagé du travail courant : repères sélectionnés et leur ordre,
/// préférences de chaque segment, objectifs Distance/Durée, et actions sur
/// le brouillon (sauvegarde, chargement manuel, autosauvegarde).
///
/// Instance unique enregistrée `permanent` dans `AppBinding` : la même
/// instance est utilisée par [MapController] et [SelectedMarkersController],
/// qui y accèdent par injection constructeur ou par
/// `RouteEditorController.instance` lorsque le partage l'exige.
///
/// Ce controller ne dépend jamais de la carte : lorsqu'une mutation de
/// l'état de travail impose une resynchronisation des cercles, il incrémente
/// l'une des révisions partagées ([markersRevision], [circlesRevision],
/// [restoreCirclesRevision]) que [MapController] observe pour dessiner.
class RouteEditorController extends GetxController with WidgetsBindingObserver {
  RouteEditorController(
    this._markerRepository,
    this._routePreferenceRepository, {
    OfflineRoutingService? routingService,
    this._storageContainerName,
  }) : _routingService =
           routingService ??
           (Get.isRegistered<OfflineRoutingService>()
               ? Get.find<OfflineRoutingService>()
               : OfflineRoutingService());

  static RouteEditorController get instance => Get.find<RouteEditorController>();

  final MarkerRepository _markerRepository;
  final RoutePreferenceRepository _routePreferenceRepository;
  final OfflineRoutingService _routingService;

  /// Nom du conteneur GetStorage à utiliser ; `null` utilise le conteneur
  /// par défaut 'GetStorage'. Permet aux tests d'isoler un conteneur par
  /// environnement, car la bibliothèque met en cache une instance par nom.
  final String? _storageContainerName;
  late final RouteDraftRepository _draftRepository = Get.isRegistered<RouteDraftRepository>()
      ? Get.find<RouteDraftRepository>()
      : InMemoryRouteDraftRepository();
  late final GetStorage _localStorage;

  final RxList<MapMarkerItem> validatedMarkers = <MapMarkerItem>[].obs;

  /// Pourcentage de préférence de route (0 = Rapide, 100 = Trail) entre chaque
  /// paire de repères validés consécutifs.
  final RxList<double> segmentRoutePreferences = <double>[].obs;

  /// Couleur choisie pour chaque segment dirigé consécutif, index-aligné
  /// avec [segmentRoutePreferences] ; `null` tant qu'aucune couleur n'a été
  /// choisie pour ce segment ([SegmentColors.resolve] retombe alors sur
  /// [SegmentColors.defaultColor]). Associée au couple d'identifiants
  /// (`startMarkerId`, `endMarkerId`), pas à la position dans la liste : une
  /// réorganisation qui conserve un couple dirigé conserve sa couleur.
  final RxList<String?> segmentColors = <String?>[].obs;

  /// Clé GetStorage de la carte (couple dirigé → couleur) de l'état de
  /// travail courant. Persistance indépendante d'ObjectBox : les entités
  /// `RoutePreferenceEntity` de l'état de travail n'ont pas de champ couleur
  /// et ne peuvent pas être étendues sans changement de schéma (interdit par
  /// le mandat). La bibliothèque des trajets, elle, persiste la couleur
  /// dans le JSON déjà existant de chaque préférence (voir
  /// `ObjectBoxRouteDraftRepository`).
  static const _segmentColorsKey = 'segmentColorsByPair';

  /// Résumé de la boucle : distance totale et temps estimé, calculés à partir
  /// des repères et d'une vitesse moyenne de 50 km/h.
  final RxString loopSummary = ''.obs;

  /// Distance totale visée par l'utilisateur pour la boucle, en kilomètres.
  final RxnDouble targetDistanceKm = RxnDouble();

  /// Temps total visé par l'utilisateur pour la boucle, en heures.
  final RxnDouble targetDurationHours = RxnDouble();

  static const _targetDistanceKey = 'targetDistanceKm';
  static const _targetDurationKey = 'targetDurationHours';
  static const _targetModeKey = 'loopTargetMode';
  static const _currentDraftIdKey = 'currentDraftId';
  static const _currentDraftNameKey = 'currentDraftName';
  static const _currentDraftCreatedAtKey = 'currentDraftCreatedAtMillis';

  /// Mode de cible actuellement sélectionné (distance ou durée).
  final Rx<LoopTargetMode> loopTargetMode = LoopTargetMode.distance.obs;

  /// Identifiant du trajet sauvegardé actuellement en cours d'édition ;
  /// `null` tant qu'il n'a jamais été sauvegardé (nouveau trajet). Une
  /// sauvegarde avec un identifiant déjà présent met à jour uniquement ce
  /// trajet, sans affecter les autres trajets de la bibliothèque.
  final RxnString currentDraftId = RxnString();

  /// Nom personnalisé du trajet en cours d'édition. Vide si l'utilisateur
  /// n'a jamais personnalisé le nom : [displayDraftName] retombe alors sur
  /// le nom par défaut dérivé de la création du trajet.
  final RxString draftName = ''.obs;

  /// Date de création du trajet en cours d'édition : fixée au démarrage
  /// d'un nouveau trajet (ou restaurée depuis un trajet chargé), stable
  /// tant qu'un autre trajet n'est pas chargé ou qu'un nouveau trajet n'est
  /// pas démarré. Base du nom par défaut.
  DateTime? _currentDraftCreatedAt;

  /// Incrémenté chaque fois qu'un brouillon est appliqué à l'état de travail
  /// (démarrage ou chargement manuel) : permet aux champs de saisie
  /// d'actualiser leur texte affiché sans réagir à chaque frappe utilisateur.
  final RxInt draftRestoreVersion = 0.obs;

  /// `true` pendant une sauvegarde complète du trajet : sert à désactiver
  /// les boutons et à bloquer les doubles soumissions.
  final RxBool isSavingDraft = false.obs;

  /// `true` pendant un chargement manuel du brouillon : sert à désactiver
  /// l'action « Charger le brouillon » et à bloquer les doubles clics.
  final RxBool isLoadingDraft = false.obs;
  final RxBool isInitializing = true.obs;
  final RxBool isMutatingMarkers = false.obs;
  final RxnString workingStateError = RxnString();
  final RxBool initializationFailed = false.obs;
  bool get mutationsBlocked =>
      isInitializing.value || initializationFailed.value || isLoadingDraft.value || isMutatingMarkers.value;
  Timer? _workingSaveTimer;
  Future<void> _workingWrites = Future<void>.value();
  bool _workingDirty = false;
  RouteDraft? _committedWork;
  Worker? _markersWorker;

  /// `true` pendant que la carte resynchronise les cercles affichés :
  /// renseigné par [MapController] et lu ici pour refuser un chargement de
  /// brouillon concurrent. État partagé, pas une dépendance.
  final RxBool isCirclesSyncing = false.obs;

  /// Révisions incrémentées aux points où l'affichage carte des repères
  /// doit être mis à jour ; [MapController] les observe et applique la
  /// resynchronisation correspondante, sans que l'éditeur connaisse la carte.
  ///
  /// [markersRevision] : restauration complète avec recentrage (état de
  ///   travail chargé au démarrage, action « Réessayer »).
  /// [circlesRevision] : resynchronisation des cercles sans recentrage
  ///   (brouillon appliqué, repère supprimé).
  /// [restoreCirclesRevision] : resynchronisation en préservant la sélection
  ///   temporaire (retour arrière après un échec de persistance).
  final RxInt markersRevision = 0.obs;
  final RxInt circlesRevision = 0.obs;
  final RxInt restoreCirclesRevision = 0.obs;

  /// `true` pendant le calcul moteur du premier segment (bouton « Tracer ») :
  /// désactive les doubles demandes et signale l'état d'attente.
  final RxBool isTracing = false.obs;

  /// Résultat du dernier calcul A→B réussi (géométrie + mesures moteur), ou
  /// `null` si aucun calcul n'a encore abouti ou s'il a été invalidé.
  final Rxn<ComputedRoute> tracedSegment = Rxn<ComputedRoute>();

  /// Identité (identifiants et numéros) des deux repères à l'origine de
  /// [tracedSegment], capturée au lancement du calcul ; `null` en même
  /// temps que [tracedSegment]. Ne change jamais pour un résultat déjà
  /// affiché, même si les repères sont réordonnés par la suite (le résultat
  /// est alors invalidé plutôt que ré-étiqueté).
  final Rxn<TracedSegmentIdentity> tracedSegmentIdentity = Rxn<TracedSegmentIdentity>();

  /// Incrémenté lorsque la couleur du segment actuellement tracé (position
  /// 0 → 1) change, sans toucher à la géométrie ni aux mesures : permet à
  /// [MapController] de recolorer la ligne déjà affichée sans rappeler le
  /// moteur ni recadrer la caméra, à la différence de [routeResultRevision].
  final RxInt routeColorRevision = 0.obs;

  /// `true` pendant une mutation de [validatedMarkers] qui ne doit pas
  /// invalider [tracedSegment] (renommage) : un simple changement de nom
  /// affiché ne modifie ni l'identité ni la géométrie du calcul déjà fait.
  bool _suppressTraceInvalidation = false;

  /// Dernière erreur de calcul moteur, distincte de [workingStateError]
  /// (persistance) : la vue choisit le message à afficher selon la source.
  final RxnString traceError = RxnString();

  /// Incrémenté à chaque changement de résultat ou d'invalidation :
  /// [MapController] l'observe pour dessiner ou retirer la géométrie.
  final RxInt routeResultRevision = 0.obs;

  /// Génération du calcul en cours : incrémentée à chaque nouvelle demande
  /// et à chaque invalidation pour ignorer les réponses obsolètes.
  int _traceGeneration = 0;

  @override
  void onInit() {
    super.onInit();
    Diag.event('RouteEditorController.onInit');
    WidgetsBinding.instance.addObserver(this);
    _localStorage = _storageContainerName == null ? GetStorage() : GetStorage(_storageContainerName);
    targetDistanceKm.value = _localStorage.read<double>(_targetDistanceKey);
    targetDurationHours.value = _localStorage.read<double>(_targetDurationKey);
    final savedMode = _localStorage.read<String>(_targetModeKey);
    loopTargetMode.value = LoopTargetMode.values.firstWhere(
      (mode) => mode.name == savedMode,
      orElse: () => LoopTargetMode.distance,
    );
    currentDraftId.value = _localStorage.read<String>(_currentDraftIdKey);
    draftName.value = _localStorage.read<String>(_currentDraftNameKey) ?? '';
    final storedCreatedAtMillis = _localStorage.read<int>(_currentDraftCreatedAtKey);
    _currentDraftCreatedAt = storedCreatedAtMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(storedCreatedAtMillis)
        : DateTime.now();
    if (storedCreatedAtMillis == null) {
      unawaited(
        _persistDraftIdentity().catchError((Object error, StackTrace stack) {
          Diag.error('RouteEditorController.init.identity', error, stack);
          workingStateError.value = 'Enregistrement impossible. Réessayez : $error';
        }),
      );
    }
    unawaited(loadPersistedMarkers());
    _markersWorker = ever(validatedMarkers, (_) {
      Diag.frequent('RouteEditorController.validatedMarkersChanged', 'count=${validatedMarkers.length}');
      _syncSegmentPreferences();
      _syncSegmentColors();
      _updateLoopSummary();
      // Un renommage (voir [renameMarker]) mute cette même liste sans
      // changer l'identité ni les coordonnées des repères : il ne doit pas
      // invalider un résultat déjà tracé.
      if (!_suppressTraceInvalidation) _invalidateTrace();
    });
  }

  void setTargetDistanceKm(double? value) {
    if (mutationsBlocked) return;
    targetDistanceKm.value = value;
    scheduleWorkingSave();
  }

  void setTargetDurationHours(double? value) {
    if (mutationsBlocked) return;
    targetDurationHours.value = value;
    scheduleWorkingSave();
  }

  void setLoopTargetMode(LoopTargetMode mode) {
    if (mutationsBlocked) return;
    loopTargetMode.value = mode;
    scheduleWorkingSave();
  }

  /// Nom affiché pour le trajet en cours d'édition : le nom personnalisé
  /// s'il existe, sinon le nom par défaut stable `trajet-MMDDHHmm` dérivé
  /// de la date de création.
  String get displayDraftName =>
      draftName.value.isEmpty ? defaultDraftName(_currentDraftCreatedAt ?? DateTime.now()) : draftName.value;

  /// Nom par défaut stable d'un trajet créé à [createdAt].
  static String defaultDraftName(DateTime createdAt) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'trajet-${two(createdAt.month)}${two(createdAt.day)}${two(createdAt.hour)}${two(createdAt.minute)}';
  }

  /// Modifie le nom personnalisé du trajet en cours d'édition.
  /// L'écriture de l'identité est relancée à chaque frappe ; une erreur est
  /// signalée via [workingStateError] plutôt que propagée au champ de saisie.
  void setDraftName(String value) {
    if (mutationsBlocked) return;
    draftName.value = value;
    unawaited(
      _persistDraftIdentity().catchError((Object error, StackTrace stack) {
        Diag.error('RouteEditorController.setDraftName.identity', error, stack);
        workingStateError.value = 'Enregistrement impossible. Réessayez : $error';
      }),
    );
  }

  /// Persiste l'identité du trajet édité (id, nom, date de création) dans
  /// GetStorage, en attendant chaque écriture. Propagée aux appelants pour
  /// qu'aucune confirmation de sauvegarde ne précède une écriture réussie
  /// et qu'aucun futur en erreur ne reste non traité.
  Future<void> _persistDraftIdentity() async {
    final id = currentDraftId.value;
    if (id == null) {
      await _localStorage.remove(_currentDraftIdKey);
    } else {
      await _localStorage.write(_currentDraftIdKey, id);
    }
    await _localStorage.write(_currentDraftNameKey, draftName.value);
    await _localStorage.write(
      _currentDraftCreatedAtKey,
      (_currentDraftCreatedAt ?? DateTime.now()).millisecondsSinceEpoch,
    );
  }

  /// Rollback de l'identité du trajet édité après un échec : restaure les
  /// valeurs fournies puis tente de les repersister, sans masquer l'erreur
  /// d'origine.
  Future<void> _rollbackDraftIdentity(String? id, String name, DateTime? createdAt) async {
    currentDraftId.value = id;
    draftName.value = name;
    _currentDraftCreatedAt = createdAt;
    try {
      await _persistDraftIdentity();
    } catch (error, stack) {
      Diag.error('RouteEditorController.identityRollback', error, stack);
    }
  }

  /// Liste tous les trajets sauvegardés de la bibliothèque, du plus
  /// récemment sauvegardé au plus ancien.
  Future<List<RouteDraft>> listSavedDrafts() => _draftRepository.listAll();

  /// Le brouillon explicite ne remplace jamais l'état de travail au démarrage.
  Future<void> loadPersistedMarkers() async {
    isInitializing.value = true;
    try {
      final markers = await _markerRepository.loadAll();
      if (isClosed) return;
      validatedMarkers.assignAll(markers);
      await _loadRoutePreferences();
      _updateLoopSummary();
      _committedWork = _workingSnapshot();
      initializationFailed.value = false;
      workingStateError.value = null;
      // La carte, si elle existe, observe [markersRevision] et restaure
      // l'affichage des repères ; sinon la restauration attend le prochain
      // chargement de style.
      markersRevision.value++;
    } catch (exception, stack) {
      initializationFailed.value = true;
      Diag.error('RouteEditorController.loadPersistedMarkers', exception, stack);
      workingStateError.value = 'Chargement de l’état de travail impossible : $exception';
    } finally {
      isInitializing.value = false;
    }
  }

  Future<void> retryWorkingState() async {
    if (initializationFailed.value) {
      await loadPersistedMarkers();
      return;
    }
    try {
      await flushWorkingState();
      workingStateError.value = null;
      // La carte observe [markersRevision] et retente l'affichage ; un
      // échec de dessin est signalé par la carte via [workingStateError].
      markersRevision.value++;
    } catch (exception, stack) {
      Diag.error('RouteEditorController.retryWorkingState', exception, stack);
      rethrow;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      unawaited(
        flushWorkingState().catchError((Object error) {
          Diag.error("RouteEditorController.lifecycle.flush", error);
        }),
      );
    }
  }

  // Les champs id/name/createdAt ne sont pas utilisés par l'état de
  // travail (markers + préférences + mode + cibles) : seule la
  // bibliothèque des trajets, gérée séparément via [currentDraftId] et
  // [draftName], leur donne un sens. Des valeurs cohérentes leur sont tout
  // de même affectées pour que ce snapshot reste un [RouteDraft] valide.
  RouteDraft _workingSnapshot() => RouteDraft(
    id: currentDraftId.value,
    name: draftName.value,
    createdAt: _currentDraftCreatedAt ?? DateTime.now(),
    savedAt: DateTime.now(),
    targetMode: loopTargetMode.value.name,
    targetDistanceKm: targetDistanceKm.value,
    targetDurationHours: targetDurationHours.value,
    totalDistanceKm: 0,
    totalDurationHours: 0,
    averageSpeedKmh: 0,
    markers: [for (var i = 0; i < validatedMarkers.length; i++) validatedMarkers[i].copyWith(orderIndex: i)],
    preferences: [
      for (var i = 0; i < validatedMarkers.length; i++)
        RouteDraftSegmentPreference(
          startMarkerId: validatedMarkers[i].id,
          endMarkerId: validatedMarkers[(i + 1) % validatedMarkers.length].id,
          value: i < segmentRoutePreferences.length ? segmentRoutePreferences[i] : 0,
          color: i < segmentColors.length ? segmentColors[i] : null,
        ),
    ],
  );

  void _restoreWorkingState(RouteDraft state) {
    validatedMarkers.assignAll(state.markers);
    segmentRoutePreferences.assignAll(state.preferences.map((p) => p.value));
    segmentColors.assignAll(state.preferences.map((p) => p.color));
    _syncSegmentPreferences();
    _syncSegmentColors();
    loopTargetMode.value = LoopTargetMode.values.byName(state.targetMode);
    targetDistanceKm.value = state.targetDistanceKm;
    targetDurationHours.value = state.targetDurationHours;
    _updateLoopSummary();
    draftRestoreVersion.value++;
  }

  /// Écrit repères et préférences en une seule transaction ObjectBox
  /// (atomique), puis le mode et les objectifs dans GetStorage. Limite
  /// connue : les deux stockages ne forment pas une transaction globale — un
  /// arrêt brutal entre les deux peut laisser des objectifs désynchronisés
  /// des repères ; la prochaine écriture réussie réaligne les deux.
  ///
  /// Les couleurs de segment sont écrites séparément dans GetStorage (voir
  /// [_segmentColorsKey]) : `RoutePreferenceEntity` (ObjectBox) n'a pas de
  /// champ couleur et ne peut pas en recevoir un sans changement de schéma.
  Future<void> _writeWorkingState(RouteDraft state) async {
    if (Get.isRegistered<ObjectBoxWorkingStateRepository>()) {
      await Get.find<ObjectBoxWorkingStateRepository>().replace(state.markers, state.preferences);
    } else {
      // Adaptateur des repositories injectés en tests ; la production utilise
      // impérativement la transaction ObjectBox ci-dessus.
      await _markerRepository.replaceAll(state.markers);
      await _routePreferenceRepository.replaceAll(state.preferences);
    }
    await _localStorage.write(_targetModeKey, state.targetMode);
    if (state.targetDistanceKm == null) {
      await _localStorage.remove(_targetDistanceKey);
    } else {
      await _localStorage.write(_targetDistanceKey, state.targetDistanceKm);
    }
    if (state.targetDurationHours == null) {
      await _localStorage.remove(_targetDurationKey);
    } else {
      await _localStorage.write(_targetDurationKey, state.targetDurationHours);
    }
    await _localStorage.write(_segmentColorsKey, {
      for (final p in state.preferences)
        if (SegmentColors.isValid(p.color)) '${p.startMarkerId}>${p.endMarkerId}': p.color!,
    });
  }

  /// Lit la carte (couple dirigé → couleur) persistée de l'état de travail.
  /// Clés absentes ou valeurs invalides sont simplement ignorées : une
  /// couleur manquante ou corrompue retombe sur [SegmentColors.defaultColor]
  /// au moment de l'affichage, jamais sur une erreur de chargement.
  Map<String, String> _readSegmentColorsMap() {
    final raw = _localStorage.read<Map<String, dynamic>>(_segmentColorsKey);
    if (raw == null) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.value is String && SegmentColors.isValid(entry.value as String))
          entry.key: entry.value as String,
    };
  }

  Future<void> _persistWorkingState(RouteDraft state) async {
    final previous = _committedWork;
    try {
      await _writeWorkingState(state);
      _committedWork = state;
      workingStateError.value = null;
    } catch (exception, stack) {
      if (previous != null) {
        try {
          await _writeWorkingState(previous);
        } catch (rollback, rollbackStack) {
          Diag.error('RouteEditorController.workingRollback', rollback, rollbackStack);
        }
      }
      workingStateError.value = 'Enregistrement impossible. Réessayez : $exception';
      Diag.error('RouteEditorController.persistWorkingState', exception, stack);
      rethrow;
    }
  }

  /// Programme une autosauvegarde de l'état de travail après une mutation
  /// initiée hors de ce controller (glisser-déposer d'un repère sur la
  /// carte, par exemple).
  void scheduleWorkingSave() {
    _workingDirty = true;
    _workingSaveTimer?.cancel();
    _workingSaveTimer = Timer(const Duration(milliseconds: 200), () {
      unawaited(
        flushWorkingState().catchError((Object error) {
          // Erreur déjà exposée dans workingStateError ; les saisies restent
          // disponibles et la prochaine sauvegarde retente l'écriture.
        }),
      );
    });
  }

  Future<void> flushWorkingState() async {
    _workingSaveTimer?.cancel();
    _workingSaveTimer = null;
    if (!_workingDirty) {
      await _workingWrites;
      return;
    }
    final snapshot = _workingSnapshot();
    _workingDirty = false;
    final operation = _workingWrites.then((_) => _persistWorkingState(snapshot));
    _workingWrites = operation.catchError((Object error) {
      _workingDirty = true;
    });
    await operation;
  }

  /// Valeur et couleur de chaque segment dirigé, indexées par couple
  /// d'identifiants plutôt que par position : une réorganisation restaure
  /// ainsi la bonne valeur et la bonne couleur à chaque couple, au lieu de
  /// réassigner les anciennes valeurs par position.
  Map<(String, String), (double, String?)> _segmentValues() => {
    for (var i = 0; i < validatedMarkers.length; i++)
      (validatedMarkers[i].id, validatedMarkers[(i + 1) % validatedMarkers.length].id): (
        i < segmentRoutePreferences.length ? segmentRoutePreferences[i] : 0,
        i < segmentColors.length ? segmentColors[i] : null,
      ),
  };

  void _restoreSegmentValues(Map<(String, String), (double, String?)> values) {
    final resolved = [
      for (var i = 0; i < validatedMarkers.length; i++)
        values[(validatedMarkers[i].id, validatedMarkers[(i + 1) % validatedMarkers.length].id)],
    ];
    segmentRoutePreferences.assignAll([for (final v in resolved) v?.$1 ?? 0]);
    // Un couple dirigé absent (nouveau segment) reçoit `null`, résolu en
    // couleur par défaut à l'affichage ; un couple conservé garde sa couleur.
    segmentColors.assignAll([for (final v in resolved) v?.$2]);
    _updateLoopSummary();
  }

  /// Synchronise [segmentRoutePreferences] avec le nombre de segments
  /// formés par [validatedMarkers]. La boucle est fermée, donc N repères
  /// forment N segments. Chaque segment est initialisé à 0.
  void _syncSegmentPreferences() => Diag.frequentSync('RouteEditorController._syncSegmentPreferences', () {
    final segmentCount = validatedMarkers.length;
    if (segmentRoutePreferences.length > segmentCount) {
      segmentRoutePreferences.removeRange(segmentCount, segmentRoutePreferences.length);
    } else if (segmentRoutePreferences.length < segmentCount) {
      final missing = segmentCount - segmentRoutePreferences.length;
      segmentRoutePreferences.addAll(List.filled(missing, 0.0));
    }
  }, result: (_) => 'segments=${segmentRoutePreferences.length}');

  /// Synchronise [segmentColors] avec le nombre de segments formés par
  /// [validatedMarkers], en miroir de [_syncSegmentPreferences]. Les
  /// nouveaux segments reçoivent `null` (couleur par défaut à l'affichage).
  void _syncSegmentColors() => Diag.frequentSync('RouteEditorController._syncSegmentColors', () {
    final segmentCount = validatedMarkers.length;
    if (segmentColors.length > segmentCount) {
      segmentColors.removeRange(segmentCount, segmentColors.length);
    } else if (segmentColors.length < segmentCount) {
      final missing = segmentCount - segmentColors.length;
      segmentColors.addAll(List<String?>.filled(missing, null));
    }
  }, result: (_) => 'segments=${segmentColors.length}');

  /// Charge les préférences de route depuis ObjectBox, et les couleurs
  /// depuis GetStorage, pour les repères actuels. La boucle est fermée : le
  /// dernier segment relie le dernier repère au premier.
  Future<void> _loadRoutePreferences() =>
      Diag.future('RouteEditorController._loadRoutePreferences', () async {
        _syncSegmentPreferences();
        _syncSegmentColors();
        final colorsByPair = _readSegmentColorsMap();
        for (var i = 0; i < validatedMarkers.length; i++) {
          final start = validatedMarkers[i];
          final end = validatedMarkers[(i + 1) % validatedMarkers.length];
          final saved = await _routePreferenceRepository.load(start.id, end.id);
          segmentRoutePreferences[i] = saved ?? 0.0;
          segmentColors[i] = colorsByPair['${start.id}>${end.id}'];
        }
      }, result: (_) => 'segments=${segmentRoutePreferences.length}');

  /// Met à jour la préférence de route pour le segment d'index [segmentIndex].
  void setRoutePreference(int segmentIndex, double value) => Diag.frequentSync(
    'RouteEditorController.setRoutePreference',
    () {
      if (mutationsBlocked || !value.isFinite) return;
      if (segmentIndex < 0 || segmentIndex >= segmentRoutePreferences.length) {
        Diag.event('RouteEditorController.setRoutePreference.early', 'segmentIndex=$segmentIndex outOfRange');
        return;
      }
      segmentRoutePreferences[segmentIndex] = value.clamp(0.0, 100.0);
      _updateLoopSummary();
      scheduleWorkingSave();
    },
    params: 'segment=$segmentIndex value=$value',
  );

  /// Palette proposée par le sélecteur de couleur de segment.
  List<String> get segmentColorPalette => SegmentColors.palette;

  /// Couleur effective du segment d'index [segmentIndex] : la couleur
  /// choisie si elle est valide, sinon [SegmentColors.defaultColor].
  String colorForSegment(int segmentIndex) => Diag.frequentSync('RouteEditorController.colorForSegment', () {
    if (segmentIndex < 0 || segmentIndex >= segmentColors.length) {
      return SegmentColors.defaultColor;
    }
    return SegmentColors.resolve(segmentColors[segmentIndex]);
  }, params: 'segment=$segmentIndex');

  /// Choisit la couleur du segment d'index [segmentIndex] : couleur
  /// associée au couple dirigé (`startMarkerId`, `endMarkerId`) de ce
  /// segment, pas à sa position. N'appelle jamais le moteur ni n'invalide
  /// [tracedSegment] : seul le segment 0 (celui effectivement tracé) fait
  /// avancer [routeColorRevision] pour que la carte recolore la ligne déjà
  /// affichée sans recalcul ni recadrage.
  void setSegmentColor(int segmentIndex, String colorHex) =>
      Diag.sync('RouteEditorController.setSegmentColor', () {
        if (mutationsBlocked) return;
        if (segmentIndex < 0 || segmentIndex >= segmentColors.length) {
          Diag.event('RouteEditorController.setSegmentColor.early', 'segmentIndex=$segmentIndex outOfRange');
          return;
        }
        final resolved = SegmentColors.isValid(colorHex) ? colorHex : SegmentColors.defaultColor;
        if (segmentColors[segmentIndex] == resolved) return;
        segmentColors[segmentIndex] = resolved;
        if (segmentIndex == 0) routeColorRevision.value++;
        scheduleWorkingSave();
      }, params: 'segment=$segmentIndex color=$colorHex');

  /// Libellé utilisateur (profil de parcours) correspondant à une préférence [0-100].
  String roadPreferenceLabel(double value) => Diag.frequentSync(
    'RouteEditorController.roadPreferenceLabel',
    () {
      if (value <= 20) return 'Rapide';
      if (value <= 40) return 'Routier';
      if (value <= 60) return 'Sinueux';
      if (value <= 80) return 'Aventure';
      return 'Trail';
    },
    params: 'value=$value',
    result: (label) => 'label=$label',
  );

  /// Vitesse moyenne estimée (km/h) correspondant à une préférence de route [0-100].
  double roadPreferenceSpeedKmh(double value) => Diag.frequentSync(
    'RouteEditorController.roadPreferenceSpeedKmh',
    () {
      if (value <= 10) return 110.0;
      if (value <= 25) return 80.0;
      if (value <= 45) return 70.0;
      if (value <= 65) return 60.0;
      if (value <= 85) return 45.0;
      return 20.0;
    },
    params: 'value=$value',
    result: (speed) => 'speed=$speed',
  );

  /// Invalide le résultat calculé : appelée sur tout changement des repères
  /// ou du trajet chargé. Les réponses en vol de l'ancienne génération sont
  /// ignorées à leur retour.
  void _invalidateTrace() {
    _traceGeneration++;
    isTracing.value = false;
    if (tracedSegment.value != null || traceError.value != null) {
      tracedSegment.value = null;
      tracedSegmentIdentity.value = null;
      traceError.value = null;
      routeResultRevision.value++;
    }
  }

  /// Bouton « Tracer » : sauvegarde complète du trajet (identique à
  /// [saveDraft] ; ses erreurs remontent telles quelles), puis calcul
  /// moteur du premier segment repère[0] → repère[1] par le moteur hors
  /// ligne. Les segments suivants et le retour de boucle ne sont pas
  /// calculés à cette étape.
  ///
  /// Une erreur de calcul n'interrompt pas la méthode : elle est exposée
  /// dans [traceError] pour que la vue la distingue d'une erreur de
  /// sauvegarde. Le résultat est publié dans [tracedSegment] et signalé
  /// via [routeResultRevision].
  Future<void> traceRoute() => Diag.future('RouteEditorController.traceRoute', () async {
    if (isTracing.value) {
      throw StateError('Un calcul de tracé est déjà en cours.');
    }
    await saveDraft();
    final markers = List<MapMarkerItem>.of(validatedMarkers);
    final generation = ++_traceGeneration;
    isTracing.value = true;
    traceError.value = null;
    try {
      final route = await _routingService.computeFirstSegment(
        startLat: markers[0].latitude,
        startLon: markers[0].longitude,
        endLat: markers[1].latitude,
        endLon: markers[1].longitude,
      );
      if (generation != _traceGeneration) {
        Diag.event('RouteEditorController.traceRoute.stale', 'ignored result');
        return;
      }
      tracedSegment.value = route;
      // Le moteur calcule toujours repère[0] → repère[1] : identité figée
      // sur les numéros 1 et 2, indépendante d'une réorganisation ultérieure
      // (qui invaliderait ce résultat via [_invalidateTrace] plutôt que de
      // réattribuer de nouveaux numéros).
      tracedSegmentIdentity.value = TracedSegmentIdentity(
        startMarkerId: markers[0].id,
        endMarkerId: markers[1].id,
        startNumber: 1,
        endNumber: 2,
      );
      routeResultRevision.value++;
    } catch (exception, stack) {
      if (generation != _traceGeneration) {
        Diag.event('RouteEditorController.traceRoute.stale', 'ignored error');
        return;
      }
      tracedSegment.value = null;
      tracedSegmentIdentity.value = null;
      traceError.value = 'Calcul du tracé impossible : $exception';
      routeResultRevision.value++;
      Diag.error('RouteEditorController.traceRoute.compute', exception, stack);
    } finally {
      if (generation == _traceGeneration) {
        isTracing.value = false;
      }
    }
  }, params: 'markers=${validatedMarkers.length}');

  /// Sauvegarde complète du trajet en cours : ordre des repères, réglages de
  /// chaque segment (boucle fermée, segment de retour inclus), objectif
  /// Distance/Durée, snapshot du brouillon et métadonnées. Met à jour
  /// uniquement le trajet déjà chargé ([currentDraftId]) ; les autres
  /// trajets de la bibliothèque ne sont pas affectés. Ne se termine qu'après
  /// la persistance réelle ; lève une erreur en cas d'échec ou de prérequis
  /// manquant pour éviter tout faux succès.
  Future<void> saveDraft() => _persistCurrentAsDraft(asCopy: false);

  /// Sauvegarde le trajet en cours sous la forme d'un nouveau trajet
  /// indépendant, sans modifier le trajet actuellement chargé : la copie
  /// devient le trajet édité ([currentDraftId] pointe désormais vers elle).
  /// [name] permet à l'utilisateur de choisir le nom de la copie ; vide ou
  /// absent, le nom par défaut dérivé de la création de la copie est utilisé.
  Future<void> saveDraftAsCopy({String? name}) => _persistCurrentAsDraft(asCopy: true, copyName: name);

  Future<void> _persistCurrentAsDraft({required bool asCopy, String? copyName}) async {
    final opName = asCopy ? 'saveDraftAsCopy' : 'saveDraft';
    final op = Diag.start('RouteEditorController.$opName', 'markers=${validatedMarkers.length}');
    if (isSavingDraft.value || mutationsBlocked) {
      final busy = StateError('Une sauvegarde ou un chargement est déjà en cours.');
      op.fail(busy, StackTrace.current);
      throw busy;
    }
    isSavingDraft.value = true;
    try {
      if (segmentRoutePreferences.length != validatedMarkers.length) {
        throw InvalidRouteDraftException("Réglages de segments incomplets.");
      }
      if (validatedMarkers.length < 2) {
        throw StateError('Au moins deux repères sont nécessaires pour enregistrer un trajet.');
      }
      // Snapshot complet capturé avant le premier await : toutes les
      // écritures ci-dessous n'utilisent que cette image, même si
      // l'utilisateur modifie un curseur ou un repère pendant la persistance.
      final nameAtSaveStart = draftName.value;
      final markers = List<MapMarkerItem>.of(validatedMarkers);
      final preferences = List<double>.of(segmentRoutePreferences);
      final colors = List<String?>.of(segmentColors);
      final targetMode = loopTargetMode.value.name;
      final targetDistance = targetDistanceKm.value;
      final targetDuration = targetDurationHours.value;

      final ordered = <MapMarkerItem>[
        for (var i = 0; i < markers.length; i++) markers[i].copyWith(orderIndex: i),
      ];
      var totalDistanceKm = 0.0;
      var totalDurationHours = 0.0;
      for (var i = 0; i < ordered.length; i++) {
        final start = ordered[i];
        final end = ordered[(i + 1) % ordered.length];
        final segmentMeters = _haversineDistance(
          start.latitude,
          start.longitude,
          end.latitude,
          end.longitude,
        );
        final segmentDistanceKm = segmentMeters / 1000.0;
        final segmentSpeedKmh = roadPreferenceSpeedKmh(preferences[i]);
        totalDistanceKm += segmentDistanceKm;
        totalDurationHours += segmentDistanceKm / segmentSpeedKmh;
      }
      final averageSpeedKmh = totalDurationHours == 0 ? 0.0 : totalDistanceKm / totalDurationHours;

      // Une copie démarre toujours une nouvelle création : nom par défaut
      // regénéré, aucun identifiant existant réutilisé. Une sauvegarde
      // normale conserve l'identifiant et la date de création du trajet
      // chargé, pour que le nom par défaut reste stable dans le temps.
      // Une copie démarre toujours une nouvelle création : aucun
      // identifiant existant réutilisé. Le nom choisi explicitement est
      // utilisé tel quel ; à défaut, le nom du trajet source suivi de
      // « (copie) », ou le nom par défaut regénéré si le trajet source
      // n'avait pas de nom personnalisé. Une sauvegarde normale conserve
      // l'identifiant et la date de création du trajet chargé, pour que le
      // nom par défaut reste stable dans le temps.
      final createdAt = asCopy ? DateTime.now() : (_currentDraftCreatedAt ?? DateTime.now());
      final trimmedName = nameAtSaveStart.trim();
      final trimmedCopyName = copyName?.trim() ?? '';
      final name = asCopy
          ? (trimmedCopyName.isNotEmpty
                ? trimmedCopyName
                : (trimmedName.isEmpty ? defaultDraftName(createdAt) : '$trimmedName (copie)'))
          : (trimmedName.isEmpty ? defaultDraftName(createdAt) : trimmedName);
      final id = asCopy ? null : currentDraftId.value;

      final draft = RouteDraft(
        id: id,
        name: name,
        createdAt: createdAt,
        savedAt: DateTime.now(),
        targetMode: targetMode,
        targetDistanceKm: targetDistance,
        targetDurationHours: targetDuration,
        totalDistanceKm: totalDistanceKm,
        totalDurationHours: totalDurationHours,
        averageSpeedKmh: averageSpeedKmh,
        markers: ordered,
        preferences: [
          for (var i = 0; i < ordered.length; i++)
            RouteDraftSegmentPreference(
              startMarkerId: ordered[i].id,
              endMarkerId: ordered[(i + 1) % ordered.length].id,
              value: preferences[i],
              color: i < colors.length ? colors[i] : null,
            ),
        ],
      );
      _validateAndResolveDraft(draft);
      // Les validations précèdent toute écriture déclenchée par ce bouton.
      _workingDirty = true;
      await flushWorkingState();
      final savedId = await _draftRepository.save(draft);
      currentDraftId.value = savedId;
      _currentDraftCreatedAt = createdAt;
      // Le nom du snapshot sauvegardé est cohérent avec le trajet écrit ;
      // si l'utilisateur a modifié le nom pendant la sauvegarde, sa saisie
      // plus récente reste dans l'état de travail et n'est pas écrasée.
      if (draftName.value == nameAtSaveStart) {
        draftName.value = name;
      }
      // Les écritures de l'identité sont attendues : toute erreur est
      // propagée avant la confirmation affichée à l'utilisateur.
      await _persistDraftIdentity();
      // Signale le changement de trajet édité (copie devenue active, nom
      // normalisé) : les champs qui suivent draftRestoreVersion, comme le
      // champ de nom, se réalignent sur le trajet actif.
      draftRestoreVersion.value++;
      _saveLastItineraryMetadata(ordered);
      op.end(
        'id=$savedId '
        'totalKm=${totalDistanceKm.toStringAsFixed(1)} '
        'totalHours=${totalDurationHours.toStringAsFixed(2)} '
        'avgKmh=${averageSpeedKmh.toStringAsFixed(1)}',
      );
    } catch (exception, stack) {
      op.fail(exception, stack);
      rethrow;
    } finally {
      isSavingDraft.value = false;
    }
  }

  /// Réinitialise l'état de travail pour démarrer un trajet vierge,
  /// indépendant de celui actuellement chargé : repères, préférences et
  /// cibles effacés, nom personnalisé effacé, date de création renouvelée.
  /// Les trajets déjà sauvegardés ne sont pas modifiés.
  ///
  /// Un snapshot complet de l'état de travail et de l'identité du trajet
  /// édité est conservé : si la création du nouvel état échoue (écriture
  /// d'identité ou persistance de l'état vide), l'état précédent —
  /// repères, objectifs, identité et nom — est restauré et repersisté en
  /// best-effort avant de relancer l'erreur.
  Future<void> newDraft() => Diag.future('RouteEditorController.newDraft', () async {
    if (isSavingDraft.value || mutationsBlocked) {
      throw StateError('Une sauvegarde ou un chargement est déjà en cours.');
    }
    isMutatingMarkers.value = true;
    final previousWorking = _workingSnapshot();
    final previousId = currentDraftId.value;
    final previousName = draftName.value;
    final previousCreatedAt = _currentDraftCreatedAt;
    try {
      validatedMarkers.clear();
      segmentRoutePreferences.clear();
      targetDistanceKm.value = null;
      targetDurationHours.value = null;
      currentDraftId.value = null;
      draftName.value = '';
      _currentDraftCreatedAt = DateTime.now();
      await _persistDraftIdentity();
      _workingDirty = true;
      await flushWorkingState();
      draftRestoreVersion.value++;
      circlesRevision.value++;
    } catch (exception, stack) {
      _restoreWorkingState(previousWorking);
      await _rollbackDraftIdentity(previousId, previousName, previousCreatedAt);
      _workingDirty = true;
      try {
        await flushWorkingState();
      } catch (rollback, rollbackStack) {
        Diag.error('RouteEditorController.newDraft.rollback', rollback, rollbackStack);
      }
      restoreCirclesRevision.value++;
      Diag.error('RouteEditorController.newDraft', exception, stack);
      rethrow;
    } finally {
      isMutatingMarkers.value = false;
    }
  }, result: (_) => 'done');

  /// Valide [draft] puis retourne les réglages et couleurs de segments
  /// réordonnés selon [draft.markers], associés par identifiants
  /// (`startMarkerId`/`endMarkerId`, pas par position dans la liste) : une
  /// liste de préférences désordonnée mais cohérente est donc restaurée
  /// correctement.
  ///
  /// Lève [InvalidRouteDraftException] sans jamais modifier l'état de
  /// travail si les données sont incohérentes : identifiant de repère vide
  /// ou dupliqué, coordonnée hors bornes, mode inconnu, valeur cible non
  /// nulle mais non finie ou non positive, préférence hors `[0, 100]`,
  /// segment manquant, dupliqué ou faisant référence à un repère absent.
  /// Une couleur absente ou invalide ne lève jamais d'erreur : elle est
  /// résolue à `null`, repris en [SegmentColors.defaultColor] à l'affichage.
  (List<double>, List<String?>) _validateAndResolveDraft(RouteDraft draft) {
    final markers = draft.markers;
    if (markers.length < 2) {
      throw InvalidRouteDraftException('Au moins deux repères sont nécessaires.');
    }
    final seenIds = <String>{};
    for (final marker in markers) {
      if (marker.id.isEmpty) {
        throw InvalidRouteDraftException('Identifiant de repère vide.');
      }
      if (!seenIds.add(marker.id)) {
        throw InvalidRouteDraftException('Identifiant de repère dupliqué : ${marker.id}.');
      }
      if (!marker.latitude.isFinite || marker.latitude < -90 || marker.latitude > 90) {
        throw InvalidRouteDraftException('Latitude invalide pour le repère ${marker.id}.');
      }
      if (!marker.longitude.isFinite || marker.longitude < -180 || marker.longitude > 180) {
        throw InvalidRouteDraftException('Longitude invalide pour le repère ${marker.id}.');
      }
    }
    if (!LoopTargetMode.values.any((mode) => mode.name == draft.targetMode)) {
      throw InvalidRouteDraftException('Mode cible inconnu : ${draft.targetMode}.');
    }
    final targetDistance = draft.targetDistanceKm;
    if (targetDistance != null && (!targetDistance.isFinite || targetDistance <= 0)) {
      throw InvalidRouteDraftException('Distance cible invalide : $targetDistance.');
    }
    final targetDuration = draft.targetDurationHours;
    if (targetDuration != null && (!targetDuration.isFinite || targetDuration <= 0)) {
      throw InvalidRouteDraftException('Durée cible invalide : $targetDuration.');
    }

    final byKey = <String, double>{};
    final colorsByKey = <String, String?>{};
    for (final pref in draft.preferences) {
      if (!pref.value.isFinite || pref.value < 0 || pref.value > 100) {
        throw InvalidRouteDraftException(
          'Préférence hors bornes pour le segment ${pref.startMarkerId}→${pref.endMarkerId}.',
        );
      }
      final key = '${pref.startMarkerId}>${pref.endMarkerId}';
      if (byKey.containsKey(key)) {
        throw InvalidRouteDraftException('Segment dupliqué : $key.');
      }
      byKey[key] = pref.value;
      colorsByKey[key] = SegmentColors.isValid(pref.color) ? pref.color : null;
    }
    final resolved = <double>[];
    final resolvedColors = <String?>[];
    for (var i = 0; i < markers.length; i++) {
      final start = markers[i];
      final end = markers[(i + 1) % markers.length];
      final key = '${start.id}>${end.id}';
      final value = byKey.remove(key);
      if (value == null) {
        throw InvalidRouteDraftException('Préférence manquante pour le segment $key.');
      }
      resolved.add(value);
      resolvedColors.add(colorsByKey.remove(key));
    }
    if (byKey.isNotEmpty) {
      throw InvalidRouteDraftException(
        'Segment(s) faisant référence à un repère absent : ${byKey.keys.join(', ')}.',
      );
    }
    return (resolved, resolvedColors);
  }

  /// Applique un brouillon restauré à l'état de travail courant : repères
  /// (identifiants, noms, coordonnées, ordre), réglages de chaque segment
  /// (retour inclus), mode Distance/Durée et valeurs cibles — y compris
  /// nulles, pour ne pas laisser une ancienne saisie à leur place. Recalcule
  /// ensuite le résumé indicatif avec les profils restaurés. Partagée entre
  /// la restauration au démarrage et le chargement manuel du brouillon.
  ///
  /// Valide [draft] avant toute mutation : en cas de données incohérentes,
  /// lève [InvalidRouteDraftException] et laisse l'état de travail intact.
  Future<void> _applyRouteDraft(RouteDraft draft) async {
    final (resolvedPreferences, resolvedColors) = _validateAndResolveDraft(draft);
    Diag.event('RouteEditorController._applyRouteDraft.validated', 'markers=${draft.markers.length}');

    // RxList.assignAll émet clear() puis addAll() : le listener sur
    // validatedMarkers voit un état vide transitoire et
    // _syncSegmentPreferences viderait les curseurs restaurés — les
    // préférences sont donc posées après les repères.
    validatedMarkers.assignAll(draft.markers);
    segmentRoutePreferences.assignAll(resolvedPreferences);
    segmentColors.assignAll(resolvedColors);
    _syncSegmentPreferences();
    _syncSegmentColors();
    // Recalcule le résumé avec les profils restaurés (le listener l'avait
    // calculé pendant l'état transitoire de assignAll).
    _updateLoopSummary();

    loopTargetMode.value = LoopTargetMode.values.byName(draft.targetMode);
    targetDistanceKm.value = draft.targetDistanceKm;
    targetDurationHours.value = draft.targetDurationHours;
    currentDraftId.value = draft.id;
    draftName.value = draft.name;
    _currentDraftCreatedAt = draft.createdAt;
    await _persistDraftIdentity();
    draftRestoreVersion.value++;
    Diag.event('RouteEditorController._applyRouteDraft.restored', 'markers=${draft.markers.length}');
  }

  /// Charge le trajet sauvegardé [id] depuis la bibliothèque et remplace
  /// l'état de travail courant (repères, réglages, mode, valeurs cibles,
  /// nom et date de création), sans réécrire ce trajet dans le repository.
  /// Lève une erreur si une sauvegarde ou un autre chargement est déjà en
  /// cours, ou si [id] ne correspond à aucun trajet.
  ///
  /// Un snapshot complet de l'état de travail et de l'identité du trajet
  /// édité est conservé : si la validation échoue, rien n'a encore été
  /// modifié ; si la persistance du nouvel état échoue après son
  /// application, l'état précédent est restauré et repersisté pour ne pas
  /// perdre les anciens choix. La synchronisation des cercles suit les
  /// révisions partagées : un échec de dessin est signalé par la carte via
  /// [workingStateError], sans faire échouer le chargement lui-même.
  Future<void> loadDraft(String id) => Diag.future('RouteEditorController.loadDraft', () async {
    if (isSavingDraft.value || mutationsBlocked) {
      throw StateError('Une sauvegarde ou un chargement est déjà en cours.');
    }
    isLoadingDraft.value = true;
    final previousWorking = _workingSnapshot();
    final previousId = currentDraftId.value;
    final previousName = draftName.value;
    final previousCreatedAt = _currentDraftCreatedAt;
    try {
      if (isCirclesSyncing.value) {
        throw StateError("Synchronisation de la carte en cours");
      }
      await flushWorkingState();
      final draft = await _draftRepository.load(id);
      if (draft == null) {
        throw StateError('Trajet introuvable.');
      }
      // La validation précède toute mutation : une erreur ici laisse
      // l'état de travail et l'identité du trajet édité intacts.
      _validateAndResolveDraft(draft);
      try {
        await _applyRouteDraft(draft);
        final replacement = _workingSnapshot();
        await _persistWorkingState(replacement);
        circlesRevision.value++;
      } catch (exception, stack) {
        _restoreWorkingState(previousWorking);
        await _rollbackDraftIdentity(previousId, previousName, previousCreatedAt);
        try {
          await _persistWorkingState(previousWorking);
        } catch (rollback, rollbackStack) {
          Diag.error('RouteEditorController.loadRollback.storage', rollback, rollbackStack);
        }
        restoreCirclesRevision.value++;
        Diag.error('RouteEditorController.loadDraft', exception, stack);
        rethrow;
      }
    } finally {
      isLoadingDraft.value = false;
    }
  }, params: 'id=$id');

  /// Ajoute un repère validé à l'état de travail en préservant les réglages
  /// de segments par paire dirigée, puis persiste immédiatement. Appelé par
  /// [MapController] après le transfert du cercle temporaire vers les
  /// cercles validés.
  Future<void> addValidatedMarker(MapMarkerItem marker) async {
    final pairs = _segmentValues();
    validatedMarkers.add(marker);
    _restoreSegmentValues(pairs);
    _workingDirty = true;
    await flushWorkingState();
  }

  /// Renomme [marker] (personnalisé ou issu de la recherche) dans l'état de
  /// travail : persiste immédiatement, sans modifier l'entrée d'origine du
  /// catalogue de recherche ni aucun autre trajet de la bibliothèque. Un nom
  /// vide (après trim) est refusé sans aucune mutation. N'invalide jamais
  /// [tracedSegment] : seuls les identifiants et numéros des repères
  /// identifient un résultat déjà calculé, jamais leur nom affiché.
  ///
  /// En cas d'échec de persistance, restaure le nom précédent avant de
  /// relancer l'erreur : aucun succès n'est jamais annoncé sur un
  /// renommage qui n'a pas atteint le disque.
  Future<void> renameMarker(MapMarkerItem marker, String newName) =>
      Diag.future('RouteEditorController.renameMarker', () async {
        if (mutationsBlocked) {
          throw StateError('Chargement ou modification en cours.');
        }
        final trimmed = newName.trim();
        if (trimmed.isEmpty) {
          throw InvalidRouteDraftException('Le nom ne peut pas être vide.');
        }
        final index = validatedMarkers.indexWhere((item) => item.id == marker.id);
        if (index == -1) return;
        final previous = validatedMarkers[index];
        if (previous.name == trimmed) return;
        isMutatingMarkers.value = true;
        _suppressTraceInvalidation = true;
        try {
          validatedMarkers[index] = previous.copyWith(name: trimmed);
          _workingDirty = true;
          await flushWorkingState();
        } catch (exception, stack) {
          validatedMarkers[index] = previous;
          workingStateError.value = 'Enregistrement impossible. Réessayez : $exception';
          Diag.error('RouteEditorController.renameMarker', exception, stack);
          rethrow;
        } finally {
          _suppressTraceInvalidation = false;
          isMutatingMarkers.value = false;
        }
      }, params: 'markerId=${marker.id}');

  /// Supprime [marker] de l'état de travail : préserve les réglages des
  /// paires dirigées restantes, persiste, puis signale à la carte de
  /// resynchroniser les cercles via [circlesRevision]. En cas d'échec,
  /// restaure l'état de travail précédent et tente de le repersister avant
  /// de relancer l'erreur.
  Future<void> deleteMarker(MapMarkerItem marker) async {
    if (mutationsBlocked) {
      Diag.event('RouteEditorController.deleteMarker', 'loadingDraft');
      return;
    }
    isMutatingMarkers.value = true;
    final previous = _workingSnapshot();
    try {
      final pairs = _segmentValues();
      validatedMarkers.removeWhere((item) => item.id == marker.id);
      _restoreSegmentValues(pairs);
      _workingDirty = true;
      await flushWorkingState();
      circlesRevision.value++;
    } catch (exception) {
      _restoreWorkingState(previous);
      _workingDirty = true;
      try {
        await flushWorkingState();
        circlesRevision.value++;
      } catch (rollback) {
        Diag.error("RouteEditorController.deleteRollback", rollback);
      }
      workingStateError.value = "Suppression impossible : $exception";
      rethrow;
    } finally {
      isMutatingMarkers.value = false;
    }
  }

  /// Réordonne les repères et programme la persistance automatique.
  void reorderMarkers(int oldIndex, int newIndex) => Diag.sync('RouteEditorController.reorderMarkers', () {
    if (mutationsBlocked) return;
    final pairs = _segmentValues();
    if (oldIndex < 0 ||
        oldIndex >= validatedMarkers.length ||
        newIndex < 0 ||
        newIndex >= validatedMarkers.length) {
      Diag.event('RouteEditorController.reorderMarkers.early', 'old=$oldIndex new=$newIndex outOfRange');
      return;
    }
    final marker = validatedMarkers.removeAt(oldIndex);
    validatedMarkers.insert(newIndex, marker);
    _restoreSegmentValues(pairs);
    scheduleWorkingSave();
  }, params: 'old=$oldIndex new=$newIndex');

  /// Recalcule et persiste les indices d'ordre de la liste validée, sans
  /// réinitialiser les réglages de segments (indexés par position).
  Future<void> saveMarkersOrder() => Diag.future('RouteEditorController.saveMarkersOrder', () async {
    if (mutationsBlocked) throw StateError("Chargement ou modification en cours.");
    final ordered = <MapMarkerItem>[
      for (var i = 0; i < validatedMarkers.length; i++) validatedMarkers[i].copyWith(orderIndex: i),
    ];
    _applyMarkersOrder(ordered);
    _workingDirty = true;
    await flushWorkingState();
  }, result: (_) => 'count=${validatedMarkers.length}');

  /// Aligne [validatedMarkers] sur [ordered] (indices persistés) en préservant
  /// les réglages de segments : RxList.assignAll émet clear() puis addAll(),
  /// et le listener voit un état vide transitoire qui viderait les curseurs.
  /// Recalcule ensuite [loopSummary] avec les valeurs restaurées.
  void _applyMarkersOrder(List<MapMarkerItem> ordered) {
    final preservedPreferences = segmentRoutePreferences.toList();
    validatedMarkers.assignAll(ordered);
    segmentRoutePreferences.assignAll(preservedPreferences);
    _updateLoopSummary();
  }

  void _saveLastItineraryMetadata(List<MapMarkerItem> markers) =>
      Diag.sync('RouteEditorController._saveLastItineraryMetadata', () {
        final displayNames = [for (var i = 0; i < markers.length; i++) markerDisplayNameFor(markers[i], i)];
        _localStorage.write('lastRouteListName', displayNames.join(' → '));
        _localStorage.write('lastMarkerNames', displayNames);
      }, result: (_) => 'names=${markers.length}');

  /// Met à jour [loopSummary] avec la distance, la durée et la vitesse moyenne.
  void _updateLoopSummary() => Diag.frequentSync('RouteEditorController._updateLoopSummary', () {
    if (validatedMarkers.length < 2) {
      loopSummary.value = '';
      return;
    }
    var totalDistanceKm = 0.0;
    var totalDurationHours = 0.0;
    for (var i = 0; i < validatedMarkers.length; i++) {
      final start = validatedMarkers[i];
      final end = validatedMarkers[(i + 1) % validatedMarkers.length];
      final segmentMeters = _haversineDistance(start.latitude, start.longitude, end.latitude, end.longitude);
      final segmentDistanceKm = segmentMeters / 1000.0;
      final segmentSpeedKmh = roadPreferenceSpeedKmh(segmentRoutePreferences[i]);
      final segmentDurationHours = segmentDistanceKm / segmentSpeedKmh;
      totalDistanceKm += segmentDistanceKm;
      totalDurationHours += segmentDurationHours;
    }
    final averageSpeedKmh = totalDurationHours == 0 ? 0.0 : totalDistanceKm / totalDurationHours;
    final hours = totalDurationHours.floor();
    final minutes = ((totalDurationHours - hours) * 60).round();
    final time = hours > 0 ? '$hours h $minutes' : '$minutes min';
    loopSummary.value =
        'Indic. ${totalDistanceKm.toStringAsFixed(1)} km  •  '
        'Est. $time  •  '
        'Moy. ${averageSpeedKmh.toStringAsFixed(0)} km/h';
  }, result: (_) => 'summary="${loopSummary.value}"');

  static double _haversineDistance(double lat1, double lon1, double lat2, double lon2) =>
      Diag.frequentSync('RouteEditorController._haversineDistance', () {
        const earthRadiusMeters = 6371000.0;
        final dLat = _toRadians(lat2 - lat1);
        final dLon = _toRadians(lon2 - lon1);
        final a =
            math.sin(dLat / 2) * math.sin(dLat / 2) +
            math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
        final c = 2 * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
        return earthRadiusMeters * c;
      });

  static double _toRadians(double degrees) => degrees * (math.pi / 180.0);

  /// Nom à afficher pour le repère à [index] dans [validatedMarkers] :
  /// - le nom du repère s'il provient d'une recherche (ville, route, etc.) ;
  /// - sinon, `Repère_N` selon la position dans la boucle.
  String markerDisplayName(int index) => Diag.frequentSync(
    'RouteEditorController.markerDisplayName',
    () {
      if (index < 0 || index >= validatedMarkers.length) {
        return 'Repère';
      }
      return markerDisplayNameFor(validatedMarkers[index], index);
    },
    params: 'index=$index',
    result: (name) => 'name="$name"',
  );

  /// Nom à afficher, distinct de son numéro ([index] + 1, qui change avec
  /// l'ordre) : le nom stocké tel quel dès qu'il est non vide — y compris
  /// « Repère » ou « Repère_02 » s'ils ont été saisis par l'utilisateur,
  /// qui restent des noms légitimes. Le repli numéroté `Repère_NN` selon
  /// la position actuelle ne s'applique qu'à un ancien nom vide.
  String markerDisplayNameFor(MapMarkerItem marker, int index) => Diag.frequentSync(
    'RouteEditorController.markerDisplayNameFor',
    () {
      if (marker.name.trim().isEmpty) {
        return 'Repère_${(index + 1).toString().padLeft(2, '0')}';
      }
      return marker.name;
    },
    params: 'id=${marker.id} index=$index',
    result: (name) => 'name="$name"',
  );

  @override
  void onClose() {
    Diag.event('RouteEditorController.onClose');
    WidgetsBinding.instance.removeObserver(this);
    _markersWorker?.dispose();
    unawaited(
      flushWorkingState().catchError((Object error) {
        Diag.error('RouteEditorController.close.flush', error);
      }),
    );
    super.onClose();
  }
}
