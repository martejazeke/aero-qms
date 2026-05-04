// ============================================================
//  Aero QMS — MatchmakingEngine
//  Priority: Wait Time → Games Played → Anti-repeat Fairness
// ============================================================

import 'dart:math';
import '../models/player.dart';

// ─────────────────────────────────────────────────────────────
//  MatchmakingEngine
// ─────────────────────────────────────────────────────────────

class MatchmakingEngine {
  static const double kWaitWeight = 0.70;
  static const double kGamesWeight = 0.20;
  static const double kFairnessWeight = 0.10;
  static const int kWaitToleranceSeconds = 30;

  // ── State ────────────────────────────────────────────────────

  Set<String> _lastMatchIds = {};

  // ─────────────────────────────────────────────────────────────
  //  Public API
  // ─────────────────────────────────────────────────────────────

  void recordMatch(List<Player> matchedPlayers) {
    _lastMatchIds = matchedPlayers.map((p) => p.id).toSet();
  }

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

    final scored = waitingRoom
        .map((p) => _scorePlayer(p, waitingRoom))
        .toList()
      ..sort();

    final selected = _selectFairCandidates(scored, playersNeeded);

    return MatchResult(
      selectedPlayers: selected,
      rankedQueue: scored,
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  Scoring
  // ─────────────────────────────────────────────────────────────

  PlayerScore _scorePlayer(Player player, List<Player> waitingRoom) {
    final now = DateTime.now();

    // ── Wait time (higher = waited longer) ─────────
    final maxWait = _maxWaitSeconds(waitingRoom, now);
    final playerWait =
        now.difference(player.lastWaitStartTime).inSeconds.toDouble();
    final waitScore =
        maxWait > 0 ? (playerWait / maxWait).clamp(0.0, 1.0) : 0.0;

    // ── Games played (lower games = higher score) ───
    final maxGames = _maxGamesPlayed(waitingRoom);
    final gamesScore =
        maxGames > 0 ? (1.0 - player.gamesPlayed / maxGames) : 1.0;

    // ── Fairness (penalise last-match players) ──────
    final fairnessScore = _lastMatchIds.contains(player.id) ? 0.0 : 1.0;

    // ── Composite ────────────────────────────────────────────────
    final score = (waitScore * kWaitWeight) +
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

  // ─────────────────────────────────────────────────────────────
  //  Fair Selection
  // ─────────────────────────────────────────────────────────────

  
  List<Player> _selectFairCandidates(
    List<PlayerScore> scored,
    int playersNeeded,
  ) {
    final fresh = <PlayerScore>[];
    final repeated = <PlayerScore>[];

    for (final ps in scored) {
      if (_lastMatchIds.contains(ps.player.id)) {
        repeated.add(ps);
      } else {
        fresh.add(ps);
      }
    }

    final mustInclude = <PlayerScore>[];
    if (repeated.isNotEmpty) {
      final longestRepeatWait = repeated
          .map((ps) => ps.waitDuration.inSeconds)
          .reduce(max);

      for (final ps in fresh) {
        if (ps.waitDuration.inSeconds > longestRepeatWait + kWaitToleranceSeconds) {
          mustInclude.add(ps);
        }
      }
    }

    final selected = <Player>[];
    final mustIncludeIds = mustInclude.map((ps) => ps.player.id).toSet();

    for (final ps in mustInclude) {
      if (selected.length >= playersNeeded) break;
      selected.add(ps.player);
    }

    for (final ps in fresh) {
      if (selected.length >= playersNeeded) break;
      if (!mustIncludeIds.contains(ps.player.id)) {
        selected.add(ps.player);
      }
    }

    for (final ps in repeated) {
      if (selected.length >= playersNeeded) break;
      selected.add(ps.player);
    }

    return selected;
  }

  // ─────────────────────────────────────────────────────────────
  //  Helpers
  // ─────────────────────────────────────────────────────────────

  double _maxWaitSeconds(List<Player> players, DateTime now) {
    if (players.isEmpty) return 0;
    return players
        .map((p) => now.difference(p.lastWaitStartTime).inSeconds.toDouble())
        .reduce(max);
  }

  int _maxGamesPlayed(List<Player> players) {
    if (players.isEmpty) return 0;
    return players.map((p) => p.gamesPlayed).reduce(max);
  }
}
