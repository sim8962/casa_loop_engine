import 'dart:convert';

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

  static List<PlaceEntity> rank(List<PlaceEntity> candidates, String query) => Diag.sync(
    'PlaceSearchRankingService.rank',
    () {
      if (query.isEmpty) return [];
      final scored = candidates.map((e) => _ScoredCandidate(e, _matchRank(e, query))).toList(growable: false);
      scored.sort(_compare);
      return scored.map((s) => s.entity).toList(growable: false);
    },
    params: 'candidates=${candidates.length} query="$query"',
    result: (ranked) => 'ranked=${ranked.length}',
  );

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
  _ScoredCandidate(this.entity, this.rank);

  final PlaceEntity entity;
  final int rank;
}
