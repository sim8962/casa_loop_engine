import 'dart:convert';
import 'dart:math';

import 'package:casa_loop_engine/models/entities/place_entity.dart';
import 'package:casa_loop_engine/services/search/place_search_key_service.dart';
import 'package:casa_loop_engine/helpers/diagnostics/diag.dart';

class PlaceSearchRankingService {
  static const int _rankSearchKey = 5;
  static const int _rankContainsAlt = 4;
  static const int _rankPrefixAlt = 3;
  static const int _rankContainsPrimary = 2;
  static const int _rankPrefixPrimary = 1;
  static const int _rankExact = 0;
  static const double _earthRadiusKm = 6371.0;

  static List<PlaceEntity> rank(
    List<PlaceEntity> candidates,
    String query, {
    double? latitude,
    double? longitude,
  }) => Diag.sync(
    'PlaceSearchRankingService.rank',
    () {
      if (query.isEmpty) return [];
      _validateLocation(latitude, longitude);

      final hasLocation = latitude != null && longitude != null;
      final scored = candidates
          .map((e) {
            final distance = hasLocation ? distanceInKm(latitude, longitude, e.latitude, e.longitude) : null;
            return _ScoredCandidate(e, _matchRank(e, query), distance);
          })
          .toList(growable: false);
      scored.sort(_compare);
      return scored.map((s) => s.entity).toList(growable: false);
    },
    params:
        'candidates=${candidates.length} query="$query" '
        'lat=$latitude lon=$longitude',
    result: (ranked) => 'ranked=${ranked.length}',
  );

  static double distanceInKm(double lat1, double lon1, double lat2, double lon2) =>
      Diag.frequentSync('PlaceSearchRankingService.distanceInKm', () {
        final dLat = _toRadians(lat2 - lat1);
        final dLon = _toRadians(lon2 - lon1);
        final a =
            sin(dLat / 2) * sin(dLat / 2) +
            cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * sin(dLon / 2) * sin(dLon / 2);
        final c = 2 * atan2(sqrt(a), sqrt(1 - a));
        return _earthRadiusKm * c;
      });

  static int _matchRank(PlaceEntity candidate, String query) =>
      Diag.frequentSync('PlaceSearchRankingService._matchRank', () {
        var rank = _rankSearchKey;

        final primary = [candidate.name, candidate.nameFr, candidate.nameAr, candidate.nameZgh]
            .whereType<String>()
            .map(PlaceSearchKeyService.normalize)
            .where((n) => n.isNotEmpty)
            .toList(growable: false);

        for (final n in primary) {
          if (n == query) return _rankExact;
          if (rank > _rankPrefixPrimary && n.startsWith(query)) {
            rank = _rankPrefixPrimary;
          }
          if (rank > _rankContainsPrimary && n.contains(query)) {
            rank = _rankContainsPrimary;
          }
        }

        for (final n in _normalizedAlternatives(candidate)) {
          if (n == query) return _rankExact;
          if (rank > _rankPrefixAlt && n.startsWith(query)) {
            rank = _rankPrefixAlt;
          }
          if (rank > _rankContainsAlt && n.contains(query)) {
            rank = _rankContainsAlt;
          }
        }

        return rank;
      }, result: (rank) => 'rank=$rank');

  static int _compare(_ScoredCandidate a, _ScoredCandidate b) =>
      Diag.frequentSync('PlaceSearchRankingService._compare', () {
        final rankCompare = a.rank.compareTo(b.rank);
        if (rankCompare != 0) return rankCompare;

        final importanceCompare = _compareImportance(a.entity.importance, b.entity.importance);
        if (importanceCompare != 0) return importanceCompare;

        final populationCompare = _comparePopulation(a.entity.population, b.entity.population);
        if (populationCompare != 0) return populationCompare;

        final distanceCompare = _compareDistance(a.distance, b.distance);
        if (distanceCompare != 0) return distanceCompare;

        final nameCompare = _displayName(a.entity).compareTo(_displayName(b.entity));
        if (nameCompare != 0) return nameCompare;

        return a.entity.osmId.compareTo(b.entity.osmId);
      });

  static int _compareImportance(double? a, double? b) =>
      Diag.frequentSync('PlaceSearchRankingService._compareImportance', () {
        final av = a ?? double.negativeInfinity;
        final bv = b ?? double.negativeInfinity;
        return bv.compareTo(av);
      });

  static int _comparePopulation(int? a, int? b) =>
      Diag.frequentSync('PlaceSearchRankingService._comparePopulation', () {
        final av = a ?? -1;
        final bv = b ?? -1;
        return bv.compareTo(av);
      });

  static int _compareDistance(double? a, double? b) =>
      Diag.frequentSync('PlaceSearchRankingService._compareDistance', () {
        final av = a ?? double.infinity;
        final bv = b ?? double.infinity;
        return av.compareTo(bv);
      });

  static double _toRadians(double degrees) => degrees * (pi / 180.0);

  static void _validateLocation(double? latitude, double? longitude) =>
      Diag.frequentSync('PlaceSearchRankingService._validateLocation', () {
        if (latitude == null && longitude == null) return;
        if (latitude == null || longitude == null) {
          throw ArgumentError('La latitude et la longitude doivent être fournies ensemble');
        }
        if (latitude < -90 || latitude > 90 || latitude.isNaN) {
          throw ArgumentError('Latitude invalide : $latitude');
        }
        if (longitude < -180 || longitude > 180 || longitude.isNaN) {
          throw ArgumentError('Longitude invalide : $longitude');
        }
      }, params: 'lat=$latitude lon=$longitude');

  static String _displayName(PlaceEntity e) => Diag.frequentSync(
    'PlaceSearchRankingService._displayName',
    () => e.nameFr ?? e.nameAr ?? e.nameZgh ?? e.name,
  );

  static List<String> _normalizedAlternatives(PlaceEntity candidate) =>
      Diag.frequentSync('PlaceSearchRankingService._normalizedAlternatives', () {
        final raw = candidate.alternativeNames;
        if (raw == null || raw.isEmpty) return [];

        try {
          final list = jsonDecode(raw) as List<dynamic>;
          return list
              .map((v) => PlaceSearchKeyService.normalize(v.toString()))
              .where((n) => n.isNotEmpty)
              .toList(growable: false);
        } catch (_) {
          return [];
        }
      }, result: (names) => 'count=${names.length}');
}

class _ScoredCandidate {
  _ScoredCandidate(this.entity, this.rank, this.distance);

  final PlaceEntity entity;
  final int rank;
  final double? distance;
}
