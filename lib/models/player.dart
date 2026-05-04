enum SkillLevel { beginner, intermediate, advanced }

enum TeamAssignmentMode { balanced, random, perLevel }

class Player {
  final String id;
  final String name;
  final SkillLevel skill;
  int gamesPlayed;
  int wins;
  int losses;
  int currentStreak; // positive = win streak, negative = loss streak
  bool isPresent;
  DateTime lastWaitStartTime;

  // head-to-head record: opponentId -> [wins, losses]
  final Map<String, List<int>> headToHead;

  Player({
    required this.id,
    required this.name,
    required this.skill,
    this.gamesPlayed = 0,
    this.wins = 0,
    this.losses = 0,
    this.currentStreak = 0,
    this.isPresent = true,
    DateTime? lastWaitStartTime,
    Map<String, List<int>>? headToHead,
  })  : lastWaitStartTime = lastWaitStartTime ?? DateTime.now(),
        headToHead = headToHead ?? {};

  double get winRate => gamesPlayed == 0 ? 0.0 : wins / gamesPlayed;

  String get winRateDisplay =>
      '${(winRate * 100).toStringAsFixed(0)}%';

  /// Returns [wins, losses] against a specific opponent, or [0, 0] if never faced.
  List<int> recordAgainst(String opponentId) =>
      headToHead[opponentId] ?? [0, 0];

  /// Win % against a specific opponent (0.0–1.0), or null if never faced.
  double? winRateAgainst(String opponentId) {
    final record = headToHead[opponentId];
    if (record == null) return null;
    final total = record[0] + record[1];
    return total == 0 ? null : record[0] / total;
  }

  void recordWin({List<String> opponentIds = const []}) {
    gamesPlayed++;
    wins++;
    currentStreak = currentStreak > 0 ? currentStreak + 1 : 1;
    for (final id in opponentIds) {
      headToHead.putIfAbsent(id, () => [0, 0]);
      headToHead[id]![0]++;
    }
  }

  void recordLoss({List<String> opponentIds = const []}) {
    gamesPlayed++;
    losses++;
    currentStreak = currentStreak < 0 ? currentStreak - 1 : -1;
    for (final id in opponentIds) {
      headToHead.putIfAbsent(id, () => [0, 0]);
      headToHead[id]![1]++;
    }
  }

  void resetWaitTime() {
    lastWaitStartTime = DateTime.now();
  }
}

// ── Court model — holds team split ───────────────────────────

class Court {
  final int index;
  List<Player> teamA;
  List<Player> teamB;

  Court({
    required this.index,
    required this.teamA,
    required this.teamB,
  });

  List<Player> get allPlayers => [...teamA, ...teamB];
}

// ── Matchmaking output models ─────────────────────────────────

class PlayerScore implements Comparable<PlayerScore> {
  final Player player;
  final double score;
  final double waitScore;
  final double gamesScore;
  final double fairnessScore;
  final Duration waitDuration;

  const PlayerScore({
    required this.player,
    required this.score,
    required this.waitScore,
    required this.gamesScore,
    required this.fairnessScore,
    required this.waitDuration,
  });

  @override
  int compareTo(PlayerScore other) => other.score.compareTo(score);

  @override
  String toString() =>
      '${player.name} | total: ${score.toStringAsFixed(3)} '
      '(wait: ${waitScore.toStringAsFixed(3)}, '
      'games: ${gamesScore.toStringAsFixed(3)}, '
      'fairness: ${fairnessScore.toStringAsFixed(3)})';
}

class MatchResult {
  final List<Player> selectedPlayers;
  final List<PlayerScore> rankedQueue;

  const MatchResult({
    required this.selectedPlayers,
    required this.rankedQueue,
  });
}