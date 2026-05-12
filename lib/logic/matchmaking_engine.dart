// lib/logic/matchmaking_engine.dart

import 'dart:math';
import '../models/player.dart';

class MatchmakingEngine {
  static const double kWaitWeight = 0.70;
  static const double kGamesWeight = 0.20;
  static const double kFairnessWeight = 0.10;
  static const int kWaitToleranceSeconds = 30;

  Set<String> _lastMatchIds = {};

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
    final usedIds = <String>{};

    // Expand priority window for partners with score gaps
    final priorityIds = scored
        .take(playersNeeded)
        .map((ps) => ps.player.id)
        .toSet();
    final expandedIds = Set<String>.from(priorityIds);
    for (final ps in scored.take(playersNeeded)) {
      final p = ps.player;
      if (p.preferredPartnerId == null) continue;
      if (waitingRoom.any((x) => x.id == p.preferredPartnerId)) {
        expandedIds.add(p.preferredPartnerId!);
      }
    }

    // Add all eligible preferred pairs within the window before filling
    // individual slots, so a second pair is not split by the filler pass.
    for (final ps in scored) {
      if (selected.length + 2 > playersNeeded) break;

      final p = ps.player;
      if (usedIds.contains(p.id)) continue;
      if (p.preferredPartnerId == null) continue;
      if (!expandedIds.contains(p.id)) continue;
      if (!expandedIds.contains(p.preferredPartnerId)) continue;

      final partner = waitingRoom
          .where((x) => x.id == p.preferredPartnerId && !usedIds.contains(x.id))
          .firstOrNull;

      if (partner != null) {
        selected.addAll([p, partner]);
        usedIds.addAll([p.id, partner.id]);
      }
    }

    // Fill remaining slots with next highest-scored players
    for (final ps in scored) {
      if (selected.length >= playersNeeded) break;
      if (usedIds.contains(ps.player.id)) continue;
      selected.add(ps.player);
      usedIds.add(ps.player.id);
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

    final score =
        (waitScore * kWaitWeight) +
        (gamesScore * kGamesWeight) +
        (fairnessScore * kFairnessWeight);

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
