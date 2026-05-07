// lib/models/player.dart

enum SkillLevel { beginner, intermediate, advanced }

enum TeamAssignmentMode { balanced, random, perLevel }

enum CourtType { singles, doubles }

class Player {
  final String id;
  String name;
  SkillLevel skill;
  int gamesPlayed;
  int wins;
  int losses;
  int currentStreak;
  bool isPresent;
  DateTime lastWaitStartTime;
  final Map<String, List<int>> headToHead;

  /// ID of this player's preferred permanent partner (nullable).
  String? preferredPartnerId;

  Player({
    required this.id,
    required this.name,
    required this.skill,
    this.gamesPlayed = 0,
    this.wins = 0,
    this.losses = 0,
    this.currentStreak = 0,
    this.isPresent = true,
    this.preferredPartnerId,
    DateTime? lastWaitStartTime,
    Map<String, List<int>>? headToHead,
  })  : lastWaitStartTime = lastWaitStartTime ?? DateTime.now(),
        headToHead = headToHead ?? {};

  double get winRate =>
      gamesPlayed == 0 ? 0.0 : wins / gamesPlayed;

  String get winRateDisplay =>
      '${(winRate * 100).toStringAsFixed(0)}%';

  List<int> recordAgainst(String opponentId) =>
      headToHead[opponentId] ?? [0, 0];

  double? winRateAgainst(String opponentId) {
    final r = headToHead[opponentId];
    if (r == null) return null;
    final total = r[0] + r[1];
    return total == 0 ? null : r[0] / total;
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

// ── Court ─────────────────────────────────────────────────────

class Court {
  final int index;
  List<Player> teamA;
  List<Player> teamB;
  CourtType type; // singles or doubles

  Court({
    required this.index,
    required this.teamA,
    required this.teamB,
    this.type = CourtType.doubles,
  });

  int get playersPerTeam => type == CourtType.singles ? 1 : 2;
  int get totalPlayers   => playersPerTeam * 2;
  bool get isFull =>
      teamA.length == playersPerTeam && teamB.length == playersPerTeam;

  List<Player> get allPlayers => [...teamA, ...teamB];
}

// ── Matchmaking models ────────────────────────────────────────

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