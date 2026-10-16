import 'package:casa_loop_engine/models/computed_route.dart';
import 'package:casa_loop_engine/models/map_marker_item.dart';

/// Un segment du tracé enregistré : identité dirigée (repères et numéros
/// au moment du calcul), préférence de routage appliquée et résultat
/// moteur complet (géométrie, distance, durée, accrochages).
///
/// La préférence est stockée pour vérifier la correspondance du snapshot
/// avec les réglages sauvegardés du trajet : une préférence différente
/// produit potentiellement une autre géométrie, donc un résultat calculé
/// avec d'anciennes préférences ne doit pas passer pour le résultat des
/// réglages actuels.
class SavedRouteSegment {
  const SavedRouteSegment({required this.identity, required this.preference, required this.route});

  /// Identité dirigée du couple de repères à l'origine du segment,
  /// retour N→1 compris.
  final TracedSegmentIdentity identity;

  /// Préférence de routage [0-100] en vigueur pour ce segment lors du
  /// calcul (voir `RoutePreferenceCosting`).
  final double preference;

  /// Résultat moteur du segment : géométrie routière et mesures.
  final ComputedRoute route;
}

/// Résultat moteur complet d'un trajet sauvegardé : la boucle telle
/// qu'elle a été calculée ou retenue après ajustement, dans l'ordre des
/// segments, retour N→1 inclus, avec la date du calcul et
/// l'identification du moteur/pack ayant produit la géométrie.
///
/// Le snapshot est construit uniquement à partir d'un [ComputedItinerary]
/// valide au moment d'une sauvegarde et n'est restauré que s'il
/// correspond exactement aux repères et préférences sauvegardés — il ne
/// se substitue jamais à un recalcul explicite. `null` sur un trajet
/// signifie « tracé à recalculer » (ancien trajet sans géométrie ou
/// réglages modifiés depuis le dernier calcul).
///
/// La représentation est versionnée : [version] identifie le schéma
/// sérialisé (voir `RouteSnapshotCodec`), qui doit refuser explicitement
/// toute version non prise en charge.
class SavedRouteSnapshot {
  const SavedRouteSnapshot({
    required this.version,
    required this.computedAt,
    required this.engineName,
    this.packFileName,
    this.packSha256,
    required this.segments,
  });

  /// Version du schéma sérialisé — seule la version courante est
  /// écrite et lue.
  static const int currentVersion = 1;

  /// Version du schéma de ce snapshot ([currentVersion] pour toute
  /// instance produite par le code courant).
  final int version;

  /// Date du calcul du résultat retenu — reprise de
  /// [ComputedItinerary.computedAt] : jamais la date de sauvegarde du
  /// trajet ni une heure de passage.
  final DateTime computedAt;

  /// Nom du moteur ayant produit la géométrie (`'valhalla'` pour le
  /// moteur embarqué actuel). Aucune version n'est inventée : le pack
  /// identifie précisément les données de calcul.
  final String engineName;

  /// Nom du fichier d'archive du pack de calcul utilisé
  /// (`AppConfig.routingGraphFileName`), s'il est connu.
  final String? packFileName;

  /// Empreinte SHA-256 du pack de calcul utilisé
  /// (`AppConfig.routingGraphSha256`), si elle est connue.
  final String? packSha256;

  /// Segments de la boucle dans l'ordre du calcul, retour N→1 inclus :
  /// N repères produisent N segments.
  final List<SavedRouteSegment> segments;

  /// Construit le snapshot du résultat [itinerary] associé aux
  /// préférences [preferences] (alignées sur ses segments : N repères →
  /// N segments, retour inclus). [engineName], [packFileName] et
  /// [packSha256] décrivent le moteur/pack ayant réellement produit la
  /// géométrie — ne rien renseigner d'inconnu.
  factory SavedRouteSnapshot.fromItinerary({
    required ComputedItinerary itinerary,
    required List<double> preferences,
    required String engineName,
    String? packFileName,
    String? packSha256,
  }) {
    if (preferences.length != itinerary.segments.length) {
      throw ArgumentError(
        'Préférences (${preferences.length}) non alignées sur les segments (${itinerary.segments.length}).',
      );
    }
    return SavedRouteSnapshot(
      version: currentVersion,
      computedAt: itinerary.computedAt,
      engineName: engineName,
      packFileName: packFileName,
      packSha256: packSha256,
      segments: [
        for (var i = 0; i < itinerary.segments.length; i++)
          SavedRouteSegment(
            identity: itinerary.segments[i].identity,
            preference: preferences[i],
            route: itinerary.segments[i].route,
          ),
      ],
    );
  }

  /// `true` si ce snapshot correspond exactement aux repères [markers]
  /// (même ordre, mêmes identifiants, mêmes couples dirigés — retour
  /// compris) et aux préférences [preferences] sauvegardés avec lui :
  /// il peut alors être restauré comme résultat de ces réglages sans
  /// recalcul. `false` sinon — le tracé doit être recalculé et le
  /// snapshot écarté (jamais restauré au prix d'une géométrie qui ne
  /// correspond pas aux réglages).
  bool correspondsTo(List<MapMarkerItem> markers, List<double> preferences) {
    if (markers.length != segments.length || markers.length != preferences.length) {
      return false;
    }
    for (var i = 0; i < markers.length; i++) {
      final segment = segments[i];
      if (segment.identity.startMarkerId != markers[i].id ||
          segment.identity.endMarkerId != markers[(i + 1) % markers.length].id ||
          segment.preference != preferences[i]) {
        return false;
      }
    }
    return true;
  }

  /// Reconstruit le résultat moteur tel qu'il doit être publié et
  /// dessiné : mêmes géométries, mesures, identités dirigées et date de
  /// calcul — aucun appel moteur.
  ComputedItinerary toComputedItinerary() => ComputedItinerary(
    segments: [
      for (final segment in segments) TracedSegment(identity: segment.identity, route: segment.route),
    ],
    computedAt: computedAt,
  );
}
