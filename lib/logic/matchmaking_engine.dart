// lib/logic/matchmaking_engine.dart

import 'dart:math';
import '../models/player.dart';

class MatchmakingEngine {
  static const double kWaitWeight          = 0.70;
  static const double kGamesWeight         = 0.20;
  static const double kFairnessWeight      = 0.10;
  static const int    kWaitToleranceSeconds = 30;

  Set<String> _lastMatchIds = {};

  void recordMatch(List<Player> matched) {
    _lastMatchIds = matched.map((p) => p.id).toSet();
  }

  /// Main entry point.
  /// [playersNeeded] is 2 for singles, 4 for doubles.
  /// Preferred-partner pairs are only honoured when BOTH partners
  /// are already inside the natural top-[playersNeeded] priority window,
  /// so they cannot jump the queue just because a preference exists.
  MatchResult findBestMatch(
    List<Player> waitingRoom,
    int playersNeeded,
  ) {
    if (waitingRoom.isEmpty) {
      return const MatchResult(selectedPlayers: [], rankedQueue: []);
    }
    if (waitingRoom.length <= playersNeeded) {
      final scores = waitingRoom
          .map((p) => _scorePlayer(p, waitingRoom))
          .toList()
        ..sort();
      return MatchResult(
        selectedPlayers: scores.map((s) => s.player).toList(),
        rankedQueue: scores,
      );
    }

    // Score everyone
    final scored = waitingRoom
        .map((p) => _scorePlayer(p, waitingRoom))
        .toList()
      ..sort();

    if (playersNeeded == 4) {
      return _selectDoubles(scored, waitingRoom, playersNeeded);
    } else {
      return _selectSingles(scored, playersNeeded);
    }
  }

  // ── Doubles selection ─────────────────────────────────────

  MatchResult _selectDoubles(
      List<PlayerScore> scored, List<Player> waitingRoom, int playersNeeded) {
    final selected = <Player>[];
    final usedIds  = <String>{};
    final pairs    = <List<Player>>[];

    // Only players ranked in the natural top [playersNeeded] slots are
    // eligible to have their partner preference honoured this round.
    // This prevents a preferred pair from cutting in front of people
    // who have been waiting longer — while still letting the pair play
    // together every single match once they've both earned their spot.
    final priorityIds =
        scored.take(playersNeeded).map((ps) => ps.player.id).toSet();

    // Pass 1: find partner pairs where BOTH members are inside the
    // priority window AND both are present in the waiting room.
    for (final ps in scored) {
      final p = ps.player;
      if (usedIds.contains(p.id)) continue;
      if (p.preferredPartnerId == null) continue;

      // Both must be in the natural top-N — no queue jumping allowed.
      if (!priorityIds.contains(p.id)) continue;
      if (!priorityIds.contains(p.preferredPartnerId)) continue;

      final partnerInRoom = waitingRoom
          .where((x) =>
              x.id == p.preferredPartnerId && !usedIds.contains(x.id))
          .toList();

      if (partnerInRoom.isNotEmpty) {
        pairs.add([p, partnerInRoom.first]);
        usedIds.addAll([p.id, partnerInRoom.first.id]);
        if (pairs.length == 2) break; // two pairs fills a doubles court
      }
    }

    // Add pairs first (up to 2 pairs = 4 players)
    for (final pair in pairs) {
      selected.addAll(pair);
      if (selected.length >= 4) break;
    }

    // Pass 2: fill any remaining slots with the next highest-scored
    // players who haven't been chosen yet.
    for (final ps in scored) {
      if (selected.length >= 4) break;
      if (!usedIds.contains(ps.player.id) &&
          !selected.any((x) => x.id == ps.player.id)) {
        selected.add(ps.player);
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
    final fresh    = scored
        .where((ps) => !_lastMatchIds.contains(ps.player.id))
        .toList();
    final repeated = scored
        .where((ps) =>  _lastMatchIds.contains(ps.player.id))
        .toList();

    final mustInclude = <PlayerScore>[];
    if (repeated.isNotEmpty) {
      final longestRepeat = repeated
          .map((ps) => ps.waitDuration.inSeconds)
          .reduce(max);
      for (final ps in fresh) {
        if (ps.waitDuration.inSeconds >
            longestRepeat + kWaitToleranceSeconds) {
          mustInclude.add(ps);
        }
      }
    }

    final selected = <Player>[];
    final mustIds  = mustInclude.map((ps) => ps.player.id).toSet();

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
    final now        = DateTime.now();
    final maxWait    = _maxWait(room, now);
    final playerWait = now
        .difference(player.lastWaitStartTime)
        .inSeconds
        .toDouble();
    final waitScore  = maxWait > 0
        ? (playerWait / maxWait).clamp(0.0, 1.0)
        : 0.0;

    final maxGames   = _maxGames(room);
    final gamesScore = maxGames > 0
        ? (1.0 - player.gamesPlayed / maxGames)
        : 1.0;

    final fairnessScore =
        _lastMatchIds.contains(player.id) ? 0.0 : 1.0;

    final score = (waitScore     * kWaitWeight) +
                  (gamesScore    * kGamesWeight) +
                  (fairnessScore * kFairnessWeight);

    return PlayerScore(
      player:        player,
      score:         score,
      waitScore:     waitScore,
      gamesScore:    gamesScore,
      fairnessScore: fairnessScore,
      waitDuration:  Duration(seconds: playerWait.toInt()),
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