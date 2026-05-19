// lib/logic/matchmaking_engine.dart

import 'dart:math';
import '../models/player.dart';

class MatchmakingEngine {
  static const double kWaitWeight = 0.70;
  static const double kGamesWeight = 0.20;
  static const double kFairnessWeight = 0.10;
  static const int kWaitToleranceSeconds = 30;

  Set<String> _lastMatchIds = {};

  // ── Matchup deduplication ─────────────────────────────────
  final Set<String> _recentMatchups = {};
 // Tracks recent teammates to avoid same people always playing together
  final Map<String, Set<String>> _recentPartners = {};

  bool recentlyPlayedTogether(String idA, String idB) =>
      _recentPartners[idA]?.contains(idB) ?? false;

  int _poolSize = 10;

  void updatePoolSize(int size) {
    _poolSize = size;
  }

  void recordPartners(List<Player> teamA, List<Player> teamB) {
    for (final team in [teamA, teamB]) {
      for (final p in team) {
        _recentPartners.putIfAbsent(p.id, () => {});
        for (final teammate in team) {
          if (teammate.id == p.id) continue;
          _recentPartners[p.id]!.add(teammate.id);
        }
      }
    }
    final memoryLimit = _poolSize <= 12 ? 2
        : _poolSize <= 20 ? 3
        : _poolSize <= 30 ? 4
        : 5;
    for (final key in _recentPartners.keys) {
      if (_recentPartners[key]!.length > memoryLimit) {
        final list = _recentPartners[key]!.toList();
        _recentPartners[key] =
            list.sublist(list.length - memoryLimit).toSet();
      }
    }
  }

  void recordMatchup(List<Player> teamA, List<Player> teamB) {
    final sig = _matchupSignature(teamA, teamB);
    _recentMatchups.add(sig);
    final matchupLimit = _poolSize <= 12 ? 6
        : _poolSize <= 20 ? 10
        : _poolSize <= 30 ? 15
        : 20;
    if (_recentMatchups.length > matchupLimit) {
      _recentMatchups.remove(_recentMatchups.first);
    }
    recordPartners(teamA, teamB);
  }

  bool isRecentMatchup(List<Player> teamA, List<Player> teamB) =>
      _recentMatchups.contains(_matchupSignature(teamA, teamB));

  String _matchupSignature(List<Player> teamA, List<Player> teamB) {
    final a = (teamA.map((p) => p.id).toList()..sort()).join(',');
    final b = (teamB.map((p) => p.id).toList()..sort()).join(',');
    final parts = [a, b]..sort();
    return parts.join('|');
  }

  void recordMatch(List<Player> matched) {
    _lastMatchIds = matched.map((p) => p.id).toSet();
  }

  /// Main entry point.
  /// [playersNeeded] is 2 for singles, 4 for doubles.
  /// For doubles, a preferred partner in the priority window brings their
  /// partner into the eligible window so the pair is selected together.
  MatchResult findBestMatch(List<Player> waitingRoom, int playersNeeded) {
    if (waitingRoom.isEmpty) {
      return const MatchResult(selectedPlayers: [], rankedQueue: []);
    }
    if (waitingRoom.length <= playersNeeded) {
      final scores =
          waitingRoom.map((p) => _scorePlayer(p, waitingRoom)).toList()..sort();
      return MatchResult(
        selectedPlayers: scores.map((s) => s.player).toList(),
        rankedQueue: scores,
      );
    }

    // Score everyone
    final scored = waitingRoom.map((p) => _scorePlayer(p, waitingRoom)).toList()
      ..sort();

    if (playersNeeded == 4) {
      return _selectDoubles(scored, waitingRoom, playersNeeded);
    } else {
      return _selectSingles(scored, playersNeeded);
    }
  }

  // ── Doubles selection ─────────────────────────────────────

  MatchResult _selectDoubles(
    List<PlayerScore> scored,
    List<Player> waitingRoom,
    int playersNeeded,
  ) {
    final selected = <Player>[];
    final usedIds  = <String>{};

    // Build a score map for quick lookup
    final scoreMap = {for (final ps in scored) ps.player.id: ps.score};

    // Separate players into pairs and singles
    final checkedPairIds = <String>{};
    final pairs = <({Player p1, Player p2, double combinedScore})>[];

    for (final ps in scored) {
      final p = ps.player;
      if (checkedPairIds.contains(p.id)) continue;
      if (p.preferredPartnerId == null) continue;

      final partner = waitingRoom
          .where((x) => x.id == p.preferredPartnerId)
          .firstOrNull;

      if (partner != null) {
        final partnerScore = scoreMap[partner.id] ?? 0.0;
        // Use the MINIMUM score so the pair only plays when
        // BOTH have waited long enough — not just one of them
        final combinedScore = min(ps.score, partnerScore);
        pairs.add((p1: p, p2: partner, combinedScore: combinedScore));
        checkedPairIds.addAll([p.id, partner.id]);
      }
    }

    // Sort pairs by combined score descending
    pairs.sort((a, b) => b.combinedScore.compareTo(a.combinedScore));

    // Non-paired players sorted by score
    final singles = scored
        .where((ps) => !checkedPairIds.contains(ps.player.id))
        .toList();

    // Merge pairs and singles into one priority list
    // A pair competes against individual singles by their combined score
    // This means a pair only jumps ahead of singles if BOTH partners
    // have high enough scores
    int pairIdx   = 0;
    int singleIdx = 0;

    while (selected.length < playersNeeded) {
      final hasPair   = pairIdx < pairs.length;
      final hasSingle = singleIdx < singles.length;

      if (!hasPair && !hasSingle) break;

      // Decide whether to take the next pair or the next single
      bool takePair = false;
      if (hasPair && !hasSingle) {
        takePair = true;
      } else if (hasSingle && !hasPair) {
        takePair = false;
      } else {
        // Both available — compare scores
        final pairScore   = pairs[pairIdx].combinedScore;
        final singleScore = singles[singleIdx].score;
        // Only take the pair if it would fit (need 2 slots) and scores higher
        final slotsLeft = playersNeeded - selected.length;
        takePair = slotsLeft >= 2 && pairScore >= singleScore;
      }

      if (takePair) {
        final pair = pairs[pairIdx++];
        if (usedIds.contains(pair.p1.id) || usedIds.contains(pair.p2.id)) continue;

        // Skip pair if both just played AND enough fresh singles available
        final bothJustPlayed = _lastMatchIds.contains(pair.p1.id) &&
            _lastMatchIds.contains(pair.p2.id);
        final freshSingles = singles
            .where((ps) => !_lastMatchIds.contains(ps.player.id) &&
                !usedIds.contains(ps.player.id))
            .length;
        if (bothJustPlayed && freshSingles >= playersNeeded) continue;

        selected.addAll([pair.p1, pair.p2]);
        usedIds.addAll([pair.p1.id, pair.p2.id]);
      } else {
        final ps = singles[singleIdx++];
        if (usedIds.contains(ps.player.id)) continue;
        selected.add(ps.player);
        usedIds.add(ps.player.id);
      }
    }

    return MatchResult(selectedPlayers: selected, rankedQueue: scored);
  }
  // ── Singles selection ─────────────────────────────────────

  MatchResult _selectSingles(List<PlayerScore> scored, int playersNeeded) {
    final selected = _selectFair(scored, playersNeeded);
    return MatchResult(selectedPlayers: selected, rankedQueue: scored);
  }

  // ── Fair selection (anti-repeat) ──────────────────────────

  List<Player> _selectFair(List<PlayerScore> scored, int needed) {
    final fresh = scored
        .where((ps) => !_lastMatchIds.contains(ps.player.id))
        .toList();
    final repeated = scored
        .where((ps) => _lastMatchIds.contains(ps.player.id))
        .toList();

    final mustInclude = <PlayerScore>[];
    if (repeated.isNotEmpty) {
      final longestRepeat = repeated
          .map((ps) => ps.waitDuration.inSeconds)
          .reduce(max);
      for (final ps in fresh) {
        if (ps.waitDuration.inSeconds > longestRepeat + kWaitToleranceSeconds) {
          mustInclude.add(ps);
        }
      }
    }

    final selected = <Player>[];
    final mustIds = mustInclude.map((ps) => ps.player.id).toSet();

    for (final ps in mustInclude) {
      if (selected.length >= needed) break;
      selected.add(ps.player);
    }
    for (final ps in fresh) {
      if (selected.length >= needed) break;
      if (!mustIds.contains(ps.player.id)) selected.add(ps.player);
    }
    for (final ps in repeated) {
      if (selected.length >= needed) break;
      selected.add(ps.player);
    }
    return selected;
  }

  // ── Scoring ───────────────────────────────────────────────

  PlayerScore _scorePlayer(Player player, List<Player> room) {
    final now = DateTime.now();
    final maxWait = _maxWait(room, now);
    final playerWait = now
        .difference(player.lastWaitStartTime)
        .inSeconds
        .toDouble();
    final waitScore = maxWait > 0
        ? (playerWait / maxWait).clamp(0.0, 1.0)
        : 0.0;

    final maxGames = _maxGames(room);
    final gamesScore = maxGames > 0
        ? (1.0 - player.gamesPlayed / maxGames)
        : 1.0;

    final fairnessScore = _lastMatchIds.contains(player.id) ? 0.0 : 1.0;

    

    final rng   = Random();
    final noise = rng.nextDouble() * 0.05;

    final score =
        (waitScore * kWaitWeight) +
        (gamesScore * kGamesWeight) +
        (fairnessScore * kFairnessWeight) +
        noise;

    return PlayerScore(
      player: player,
      score: score,
      waitScore: waitScore,
      gamesScore: gamesScore,
      fairnessScore: fairnessScore,
      waitDuration: Duration(seconds: playerWait.toInt()),
    );
  }

  double _maxWait(List<Player> players, DateTime now) {
    if (players.isEmpty) return 0;
    return players
        .map((p) => now.difference(p.lastWaitStartTime).inSeconds.toDouble())
        .reduce(max);
  }

  int _maxGames(List<Player> players) {
    if (players.isEmpty) return 0;
    return players.map((p) => p.gamesPlayed).reduce(max);
  }
}
