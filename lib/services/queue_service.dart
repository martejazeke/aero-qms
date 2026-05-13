// lib/services/queue_service.dart

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/player.dart';
import '../models/session.dart';
import '../logic/matchmaking_engine.dart';
import 'database_service.dart';
import 'settings_service.dart';

// ── Match history record ──────────────────────────────────────

class MatchRecord {
  final String sessionId;
  final DateTime playedAt;
  final List<String> teamANames;
  final List<String> teamBNames;
  final String winnerTeam;
  final CourtType courtType;
  final int? durationSeconds;

  MatchRecord({
    required this.sessionId,
    required this.playedAt,
    required this.teamANames,
    required this.teamBNames,
    required this.winnerTeam,
    required this.durationSeconds,
    this.courtType = CourtType.doubles,
  });

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'playedAt': playedAt.toIso8601String(),
    'teamANames': teamANames,
    'teamBNames': teamBNames,
    'winnerTeam': winnerTeam,
    'courtType': courtType.name,
    'durationSeconds': durationSeconds,
  };

  factory MatchRecord.fromJson(Map<String, dynamic> j) => MatchRecord(
    sessionId: j['sessionId'] as String,
    playedAt: DateTime.parse(j['playedAt'] as String),
    teamANames: List<String>.from(j['teamANames'] as List),
    teamBNames: List<String>.from(j['teamBNames'] as List),
    winnerTeam: j['winnerTeam'] as String,
    durationSeconds: j['durationSeconds'] as int?,
    courtType: CourtType.values.byName(j['courtType'] as String? ?? 'doubles'),
  );
}

class SessionSummary {
  final String sessionName;
  final DateTime sessionDate;
  final int totalMatches;
  final int totalPlayers;
  final int totalSeconds;
  final int avgMatchSecs;
  final List<Player> mostWins;
  final List<Player> bestWinRate;
  final List<Player> mostGames;
  final List<Player> longestStreak;
  final String? bestPartnerA;
  final String? bestPartnerB;
  final int bestPairWins;
  final List<Player> allPlayers;

  const SessionSummary({
    required this.sessionName,
    required this.sessionDate,
    required this.totalMatches,
    required this.totalPlayers,
    required this.totalSeconds,
    required this.avgMatchSecs,
    required this.mostWins,
    required this.bestWinRate,
    required this.mostGames,
    required this.longestStreak,
    required this.bestPartnerA,
    required this.bestPartnerB,
    required this.bestPairWins,
    required this.allPlayers,
  });

  String get totalTimeFormatted {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String get avgTimeFormatted {
    final m = avgMatchSecs ~/ 60;
    final s = avgMatchSecs % 60;
    return '${m}m ${s}s';
  }
}

// ── QueueService ──────────────────────────────────────────────

class QueueService extends ChangeNotifier {
  final MatchmakingEngine _engine = MatchmakingEngine();
  final DatabaseService _db = DatabaseService();
  SettingsService? _settings;

  final List<Session> _sessions = [];
  final List<MatchRecord> _history = [];

  bool _loading = true;
  bool get loading => _loading;

  List<Session> get sessions => List.unmodifiable(_sessions);
  List<Session> get activeSessions =>
      _sessions.where((s) => !s.isEnded).toList();
  List<Session> get archivedSessions =>
      _sessions.where((s) => s.isEnded).toList();
  List<MatchRecord> get matchHistory => List.unmodifiable(_history);

  void attachSettings(SettingsService s) => _settings = s;

  void _haptic() {
    if (_settings?.hapticsEnabled == true) {
      HapticFeedback.mediumImpact();
    }
  }

  // ── Init ──────────────────────────────────────────────────

  Future<void> loadFromDatabase() async {
    _loading = true;
    notifyListeners();
    final loaded = await _db.loadSessions();
    final history = await _db.loadMatchHistory();
    _sessions
      ..clear()
      ..addAll(loaded);
    _history
      ..clear()
      ..addAll(history);
    _loading = false;
    notifyListeners();
  }

  Session? getSession(String id) {
    try {
      return _sessions.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  // ── Session management ─────────────────────────────────────

  Future<void> createSession({
    required String name,
    required DateTime date,
    int courtCount = 2,
    TeamAssignmentMode teamMode = TeamAssignmentMode.balanced,
    CourtType defaultCourtType = CourtType.doubles,
  }) async {
    _haptic();
    final session = Session(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      date: date,
      courtCount: courtCount,
      isActive: true,
      isEnded: false,
      teamMode: teamMode,
      defaultCourtType: defaultCourtType,
    );
    _sessions.insert(0, session);
    notifyListeners();
    await _db.saveSession(session);
  }

  Future<void> endSession(String sessionId) async {
    final s = getSession(sessionId);
    if (s == null) return;
    s.isActive = false;
    s.isEnded = true;
    notifyListeners();
    await _db.endSession(sessionId);
  }

  /// Builds a summary of a session for the summary screen.
  SessionSummary buildSessionSummary(String sessionId) {
    final s = getSession(sessionId);
    final matches = _history.where((r) => r.sessionId == sessionId).toList();
    final players = s?.players ?? [];

    // Total court time
    final totalSecs = matches
        .where((r) => r.durationSeconds != null)
        .fold<int>(0, (sum, r) => sum + r.durationSeconds!);

    final avgSecs = matches.isEmpty
        ? 0
        : matches
                  .where((r) => r.durationSeconds != null)
                  .fold<int>(0, (sum, r) => sum + (r.durationSeconds ?? 0)) ~/
              matches.where((r) => r.durationSeconds != null).length;

    // Per-player awards (min 1 game to qualify)
    final eligible = players.where((p) => p.gamesPlayed > 0).toList();

    // Sort all eligible players by wins desc, then gamesPlayed desc as tiebreaker
    final byWins = [...eligible]
      ..sort(
        (a, b) => b.wins != a.wins
            ? b.wins.compareTo(a.wins)
            : b.gamesPlayed.compareTo(a.gamesPlayed),
      );

    final byWinRate = eligible.where((p) => p.gamesPlayed >= 3).toList()
      ..sort(
        (a, b) => b.winRate != a.winRate
            ? b.winRate.compareTo(a.winRate)
            : b.gamesPlayed.compareTo(a.gamesPlayed),
      );

    final byGames = [...eligible]
      ..sort((a, b) => b.gamesPlayed.compareTo(a.gamesPlayed));

    final byStreak = eligible.where((p) => p.currentStreak > 0).toList()
      ..sort((a, b) => b.currentStreak.compareTo(a.currentStreak));

    final topWins = byWins.isNotEmpty ? byWins.first.wins : 0;
    final topRate = byWinRate.isNotEmpty ? byWinRate.first.winRate : 0.0;
    final topGames = byGames.isNotEmpty ? byGames.first.gamesPlayed : 0;
    final topStreak = byStreak.isNotEmpty ? byStreak.first.currentStreak : 0;

    final mostWins = byWins.where((p) => p.wins == topWins).toList();
    final bestWinRate = byWinRate.where((p) => p.winRate == topRate).toList();
    final mostGames = byGames.where((p) => p.gamesPlayed == topGames).toList();
    final longestStreak = byStreak
        .where((p) => p.currentStreak == topStreak)
        .toList();

    // Best pair — find pair with most wins together from match history
    String? partnerA, partnerB;
    int bestPairWins = 0;

    for (final match in matches) {
      final winners = match.winnerTeam == 'A'
          ? match.teamANames
          : match.teamBNames;

      // Only doubles matches have pairs
      if (winners.length < 2) continue;

      // For each pair in the winning team
      for (int i = 0; i < winners.length; i++) {
        for (int j = i + 1; j < winners.length; j++) {
          final nameA = winners[i];
          final nameB = winners[j];

          // Count total wins for this pair across all matches
          int pairWins = 0;
          for (final m in matches) {
            final w = m.winnerTeam == 'A' ? m.teamANames : m.teamBNames;
            if (w.contains(nameA) && w.contains(nameB)) pairWins++;
          }

          if (pairWins > bestPairWins) {
            bestPairWins = pairWins;
            partnerA = nameA;
            partnerB = nameB;
          }
        }
      }
    }

    return SessionSummary(
      sessionName: s?.name ?? '',
      sessionDate: s?.date ?? DateTime.now(),
      totalMatches: matches.length,
      totalPlayers: players.where((p) => p.isPresent).length,
      totalSeconds: totalSecs,
      avgMatchSecs: avgSecs,
      mostWins: mostWins,
      bestWinRate: bestWinRate,
      mostGames: mostGames,
      longestStreak: longestStreak,
      bestPartnerA: partnerA,
      bestPartnerB: partnerB,
      bestPairWins: bestPairWins,
      allPlayers: [...eligible]
        ..sort(
          (a, b) => b.wins != a.wins
              ? b.wins.compareTo(a.wins)
              : b.winRate.compareTo(a.winRate),
        ),
    );
  }

  Future<void> deleteSession(String sessionId) async {
    _sessions.removeWhere((s) => s.id == sessionId);
    notifyListeners();
    await _db.deleteSession(sessionId);
  }

  Future<void> updateTeamMode(String sessionId, TeamAssignmentMode mode) async {
    final s = getSession(sessionId);
    if (s == null) return;
    s.teamMode = mode;
    notifyListeners();
    await _db.updateSession(s);
  }

  Future<void> updateDefaultCourtType(String sessionId, CourtType type) async {
    final s = getSession(sessionId);
    if (s == null) return;
    s.defaultCourtType = type;

    // Update any existing empty courts to the new type so fillCourt
    // picks up the correct needed player count immediately.
    for (final court in s.activeCourts) {
      if (court.teamA.isEmpty && court.teamB.isEmpty) {
        court.type = type;
        // Trim excess players-per-team if switching to singles
        if (type == CourtType.singles) {
          if (court.teamA.length > 1) {
            s.waitingRoom.addAll(court.teamA.sublist(1));
            court.teamA.removeRange(1, court.teamA.length);
          }
          if (court.teamB.length > 1) {
            s.waitingRoom.addAll(court.teamB.sublist(1));
            court.teamB.removeRange(1, court.teamB.length);
          }
        }
      }
    }

    notifyListeners();
    await _db.updateSession(s);
  }

  // ── Player management ──────────────────────────────────────

  int _playerIdCounter = 0;

  String _newPlayerId(String sessionId) {
    _playerIdCounter++;
    return '${sessionId}_${DateTime.now().millisecondsSinceEpoch}_$_playerIdCounter';
  }

  Future<void> addPlayerToSession({
    required String sessionId,
    required String name,
    required SkillLevel skill,
  }) async {
    final s = getSession(sessionId);
    if (s == null) return;
    _haptic();
    final player = Player(
      id: _newPlayerId(sessionId),
      name: name,
      skill: skill,
    );
    s.players.add(player);
    if (player.isPresent) s.waitingRoom.add(player);
    notifyListeners();
    await _db.savePlayer(player, sessionId);
  }

  Future<void> addPlayersBulk({
    required String sessionId,
    required List<String> names,
    required SkillLevel skill,
  }) async {
    final s = getSession(sessionId);
    if (s == null) return;
    _haptic();

    final rng = Random();
    final now = DateTime.now();

    // Spread initial wait times randomly across 0-5 minutes so the
    // first match isn't biased toward whoever appears first in the list.
    // Real wait times take over naturally after the first match.
    final newPlayers = names.map((name) {
      final offsetSecs = rng.nextInt(300); // 0–300 s
      return Player(
        id: _newPlayerId(sessionId),
        name: name,
        skill: skill,
        isPresent: false, // starts absent — tap to check in
        lastWaitStartTime: now.subtract(Duration(seconds: offsetSecs)),
      );
    }).toList();

    s.players.addAll(newPlayers);
    // Only present players join the queue
    s.waitingRoom.addAll(newPlayers.where((p) => p.isPresent));
    notifyListeners();
    await _db.savePlayers(newPlayers, sessionId);
  }

  /// Toggle a player's presence (check-in / mark absent).
  /// Absent players are removed from the waiting room but kept
  /// in the session roster. Present players re-join the queue.
  Future<void> togglePlayerPresence({
    required String sessionId,
    required String playerId,
  }) async {
    final s = getSession(sessionId);
    if (s == null) return;
    try {
      final p = s.players.firstWhere((p) => p.id == playerId);
      p.isPresent = !p.isPresent;

      if (p.isPresent) {
        // Assign a random wait start so check-in order doesn't bias the queue.
        // Spread across 0–60 s so the first match feels fair regardless of
        // which order the organiser taps players in.
        final rng = Random();
        p.lastWaitStartTime = DateTime.now().subtract(
          Duration(seconds: rng.nextInt(60)),
        );
        if (!s.waitingRoom.any((x) => x.id == p.id) &&
            !s.activeCourts.any((c) => c.allPlayers.any((x) => x.id == p.id))) {
          s.waitingRoom.add(p);
        }
      } else {
        // Leaving — remove from queue (keep stats, keep in session)
        s.waitingRoom.removeWhere((x) => x.id == p.id);
      }
    } catch (_) {
      return;
    }
    notifyListeners();
    await _db.savePlayers(s.players, sessionId);
  }

  Future<void> updatePlayer({
    required String sessionId,
    required String playerId,
    required String name,
    required SkillLevel skill,
  }) async {
    final s = getSession(sessionId);
    if (s == null) return;
    try {
      final p = s.players.firstWhere((p) => p.id == playerId);
      p.name = name;
      p.skill = skill;
      // Also update in waitingRoom (same object ref, but be safe)
      final inQueue = s.waitingRoom.firstWhere(
        (x) => x.id == playerId,
        orElse: () => p,
      );
      inQueue.name = name;
      inQueue.skill = skill;
    } catch (_) {
      return;
    }
    notifyListeners();
    await _db.savePlayers(s.players, sessionId);
  }

  Future<void> removePlayerFromSession({
    required String sessionId,
    required String playerId,
  }) async {
    final s = getSession(sessionId);
    if (s == null) return;
    for (final p in s.players) {
      if (p.preferredPartnerId == playerId) {
        p.preferredPartnerId = null;
      }
    }
    s.players.removeWhere((p) => p.id == playerId);
    s.waitingRoom.removeWhere((p) => p.id == playerId);
    notifyListeners();
    await _db.deletePlayer(playerId);
    await _db.savePlayers(s.players, sessionId);
  }

  Future<void> setPreferredPartner({
    required String sessionId,
    required String playerId,
    required String? partnerId,
  }) async {
    final s = getSession(sessionId);
    if (s == null) return;

    Player? player;
    try {
      player = s.players.firstWhere((p) => p.id == playerId);
    } catch (_) {
      return;
    }

    if (player.preferredPartnerId != null) {
      try {
        final oldPartner = s.players.firstWhere(
          (p) => p.id == player!.preferredPartnerId,
        );
        oldPartner.preferredPartnerId = null;
      } catch (_) {}
    }

    player.preferredPartnerId = partnerId;

    if (partnerId != null) {
      try {
        final partner = s.players.firstWhere((p) => p.id == partnerId);
        if (partner.preferredPartnerId != null &&
            partner.preferredPartnerId != playerId) {
          try {
            final oldP = s.players.firstWhere(
              (p) => p.id == partner.preferredPartnerId,
            );
            oldP.preferredPartnerId = null;
          } catch (_) {}
        }
        partner.preferredPartnerId = playerId;
      } catch (_) {}
    }

    notifyListeners();
    await _db.savePlayers(s.players, sessionId);
  }

  // ── Court management ───────────────────────────────────────

  void addCourt(String sessionId, {CourtType? type}) {
    final s = getSession(sessionId);
    if (s == null) return;
    _haptic();

    final nextIndex = s.activeCourts.length;
    s.activeCourts.add(
      Court(
        index: nextIndex,
        teamA: [],
        teamB: [],
        type: type ?? s.defaultCourtType,
      ),
    );
    notifyListeners();
    _db.updateSession(s);
  }

  void updateCourtType(String sessionId, int courtIndex, CourtType type) {
    final s = getSession(sessionId);
    if (s == null || courtIndex >= s.activeCourts.length) return;
    final c = s.activeCourts[courtIndex];
    if (type == CourtType.singles) {
      if (c.teamA.length > 1) {
        final extra = c.teamA.removeAt(1);
        extra.resetWaitTime();
        s.waitingRoom.add(extra);
      }
      if (c.teamB.length > 1) {
        final extra = c.teamB.removeAt(1);
        extra.resetWaitTime();
        s.waitingRoom.add(extra);
      }
    }
    c.type = type;
    notifyListeners();
    _db.updateSession(s);
  }

  void removeCourt(String sessionId, int courtIndex) {
    final s = getSession(sessionId);
    if (s == null || courtIndex >= s.activeCourts.length) return;
    final court = s.activeCourts.removeAt(courtIndex);
    for (final p in court.allPlayers) {
      p.resetWaitTime();
      if (!s.waitingRoom.any((x) => x.id == p.id)) s.waitingRoom.add(p);
    }
    // Re-index remaining courts
    for (var i = 0; i < s.activeCourts.length; i++) {
      final c = s.activeCourts[i];
      s.activeCourts[i] = Court(
        index: i,
        teamA: c.teamA,
        teamB: c.teamB,
        type: c.type,
      );
    }
    notifyListeners();
    _db.updateSession(s);
  }

  // ── Matchmaking ────────────────────────────────────────────

  bool fillCourt({required String sessionId, int courtIndex = -1}) {
    final s = getSession(sessionId);
    if (s == null) return false;

    int targetIdx = courtIndex == -1
        ? s.activeCourts.indexWhere((c) => c.teamA.isEmpty && c.teamB.isEmpty)
        : courtIndex;

    // No empty court exists yet — auto-create one so Fill Court always works.
    if (targetIdx == -1) {
      targetIdx = s.activeCourts.length;
      s.activeCourts.add(
        Court(index: targetIdx, teamA: [], teamB: [], type: s.defaultCourtType),
      );
    }

    // Court slot exists in UI but hasn't been created in activeCourts yet
    // (placeholder slot) — create it now.
    while (s.activeCourts.length <= targetIdx) {
      final idx = s.activeCourts.length;
      s.activeCourts.add(
        Court(index: idx, teamA: [], teamB: [], type: s.defaultCourtType),
      );
    }

    final type = s.activeCourts[targetIdx].type;
    final needed = type == CourtType.singles ? 2 : 4;

    final presentCount = s.waitingRoom.where((p) => p.isPresent).length;
    if (presentCount < needed) return false;

    _haptic();

    // Pass the full waiting room to the engine. The engine scores every
    // player and enforces the priority-window rule internally — preferred
    // partners are only paired together when both are already in the
    // natural top-[needed] by wait time, so no queue-jumping occurs.
    final presentQueue = s.waitingRoom.where((p) => p.isPresent).toList();
    s.waitingRoom.removeWhere((p) => !p.isPresent);
    var result = _engine.findBestMatch(presentQueue, needed);
    var selected = result.selectedPlayers;

    // Safety fallback: if the engine somehow returns too few players,
    // just take the longest-waiting ones directly.
    if (selected.length < needed) {
      s.waitingRoom.sort(
        (a, b) => a.lastWaitStartTime.compareTo(b.lastWaitStartTime),
      );
      selected = s.waitingRoom.take(needed).toList();
    }

    for (final p in selected) {
      s.waitingRoom.removeWhere((x) => x.id == p.id);
    }

    final teams = _assignTeams(selected, s.teamMode, type);
    s.activeCourts[targetIdx] = Court(
      index: targetIdx,
      teamA: teams[0],
      teamB: teams[1],
      type: type,
      matchStartTime: DateTime.now(),
    );

    // Record only this court's players so the engine knows who just
    // played this round — not all on-court players across all courts.
    _engine.recordMatch(result.selectedPlayers);
    notifyListeners();
    return true;
  }

  /// Returns the ranked queue and predicted next players without
  /// modifying any state. Used by the Queue tab for display only.
  MatchResult previewNextMatch(String sessionId) {
    final s = getSession(sessionId);
    if (s == null) {
      return const MatchResult(selectedPlayers: [], rankedQueue: []);
    }
    final presentQueue = s.waitingRoom.where((p) => p.isPresent).toList();
    if (presentQueue.isEmpty) {
      return const MatchResult(selectedPlayers: [], rankedQueue: []);
    }
    final needed = s.defaultCourtType == CourtType.singles ? 2 : 4;
    return _engine.findBestMatch(presentQueue, needed);
  }

  void promoteToFront(String sessionId, String playerId) {
    final s = getSession(sessionId);
    if (s == null) return;
    // Find the earliest wait time in the queue, then go 1 minute earlier
    final earliest = s.waitingRoom
        .where((p) => p.isPresent)
        .map((p) => p.lastWaitStartTime)
        .fold(DateTime.now(), (a, b) => b.isBefore(a) ? b : a);
    final p = s.waitingRoom.firstWhere(
      (x) => x.id == playerId,
      orElse: () => s.players.firstWhere((x) => x.id == playerId),
    );
    p.lastWaitStartTime = earliest.subtract(const Duration(minutes: 1));
    notifyListeners();
    _db.updateSession(s);
  }

  void assignPlayerToCourt({
    required String sessionId,
    required int courtIndex,
    required String playerId,
    required String team,
    required int slotIndex,
  }) {
    final s = getSession(sessionId);
    if (s == null) return;

    while (s.activeCourts.length <= courtIndex) {
      s.activeCourts.add(
        Court(
          index: s.activeCourts.length,
          teamA: [],
          teamB: [],
          type: s.defaultCourtType,
        ),
      );
    }

    final court = s.activeCourts[courtIndex];
    Player? player;
    try {
      player = s.waitingRoom.firstWhere((p) => p.id == playerId);
    } catch (_) {
      try {
        player = s.players.firstWhere((p) => p.id == playerId);
      } catch (_) {
        return;
      }
    }

    s.waitingRoom.removeWhere((p) => p.id == playerId);
    court.teamA.removeWhere((p) => p.id == playerId);
    court.teamB.removeWhere((p) => p.id == playerId);

    final targetList = team == 'A' ? court.teamA : court.teamB;
    if (slotIndex < targetList.length) {
      final displaced = targetList[slotIndex];
      if (!s.waitingRoom.any((p) => p.id == displaced.id)) {
        displaced.resetWaitTime();
        s.waitingRoom.add(displaced);
      }
      targetList[slotIndex] = player;
    } else {
      targetList.add(player);
    }

    notifyListeners();
    _db.updateSession(s);
  }

  void clearCourtSlot({
    required String sessionId,
    required int courtIndex,
    required String team,
    required int slotIndex,
  }) {
    final s = getSession(sessionId);
    if (s == null || courtIndex >= s.activeCourts.length) return;
    final court = s.activeCourts[courtIndex];
    final list = team == 'A' ? court.teamA : court.teamB;
    if (slotIndex >= list.length) return;
    final p = list.removeAt(slotIndex);
    if (!s.waitingRoom.any((x) => x.id == p.id)) {
      p.resetWaitTime();
      s.waitingRoom.add(p);
    }
    notifyListeners();
    _db.updateSession(s);
  }

  void endMatch({
    required String sessionId,
    required int courtIndex,
    required bool teamAWon,
  }) {
    final s = getSession(sessionId);
    if (s == null || courtIndex >= s.activeCourts.length) return;
    _haptic();

    final court = s.activeCourts[courtIndex];
    final winners = teamAWon ? court.teamA : court.teamB;
    final losers = teamAWon ? court.teamB : court.teamA;

    final record = MatchRecord(
      sessionId: sessionId,
      playedAt: DateTime.now(),
      teamANames: court.teamA.map((p) => p.name).toList(),
      teamBNames: court.teamB.map((p) => p.name).toList(),
      winnerTeam: teamAWon ? 'A' : 'B',
      courtType: court.type,
      durationSeconds: court.matchStartTime != null
          ? DateTime.now().difference(court.matchStartTime!).inSeconds
          : null,
    );
    _history.insert(0, record);
    _db.saveMatchRecord(record);

    final loserIds = losers.map((p) => p.id).toList();
    final winnerIds = winners.map((p) => p.id).toList();

    final rng = Random();
    for (final p in winners) {
      p.recordWin(opponentIds: loserIds);
      p.lastWaitStartTime = DateTime.now().subtract(
        Duration(seconds: rng.nextInt(30)),
      );
      s.waitingRoom.add(p);
    }
    for (final p in losers) {
      p.recordLoss(opponentIds: winnerIds);
      p.lastWaitStartTime = DateTime.now().subtract(
        Duration(seconds: rng.nextInt(30)),
      );
      s.waitingRoom.add(p);
    }

    s.activeCourts[courtIndex] = Court(
      index: courtIndex,
      teamA: [],
      teamB: [],
      type: court.type,
    );

    notifyListeners();
    _db.savePlayers([...winners, ...losers], sessionId);
    _db.updateSession(s);
  }

  void swapPlayers({
    required String sessionId,
    required int courtIndex,
    required String playerIdA,
    required String playerIdB,
  }) {
    final s = getSession(sessionId);
    if (s == null || courtIndex >= s.activeCourts.length) return;
    final court = s.activeCourts[courtIndex];
    final isPlayerAInTeamA = court.teamA.any((p) => p.id == playerIdA);
    final isPlayerBInTeamA = court.teamA.any((p) => p.id == playerIdB);
    if (isPlayerAInTeamA == isPlayerBInTeamA) return;

    final idxA = isPlayerAInTeamA
        ? court.teamA.indexWhere((p) => p.id == playerIdA)
        : court.teamB.indexWhere((p) => p.id == playerIdA);
    final idxB = isPlayerBInTeamA
        ? court.teamA.indexWhere((p) => p.id == playerIdB)
        : court.teamB.indexWhere((p) => p.id == playerIdB);

    final pA = isPlayerAInTeamA ? court.teamA[idxA] : court.teamB[idxA];
    final pB = isPlayerBInTeamA ? court.teamA[idxB] : court.teamB[idxB];

    if (isPlayerAInTeamA) {
      court.teamA[idxA] = pB;
      court.teamB[idxB] = pA;
    } else {
      court.teamB[idxA] = pB;
      court.teamA[idxB] = pA;
    }

    notifyListeners();
    _db.updateSession(s);
  }

  /// Swap a player on this court with a player on ANY other court or queue.
  void swapWithAnywhere({
    required String sessionId,
    required int courtIndex,
    required String outPlayerId, // player currently on courtIndex
    required String inPlayerId, // player from another court or queue
  }) {
    final s = getSession(sessionId);
    if (s == null) return;

    // Find outgoing player's slot
    final court = s.activeCourts[courtIndex];
    final inA = court.teamA.indexWhere((p) => p.id == outPlayerId);
    final inB = court.teamB.indexWhere((p) => p.id == outPlayerId);
    if (inA == -1 && inB == -1) return;
    final onTeamA = inA != -1;
    final outSlot = onTeamA ? inA : inB;

    // Find incoming player — could be in waiting room or another court
    Player? incoming;
    int? inCourtIdx;
    bool? inTeamA;
    int? inSlot;

    // Check waiting room first
    final inQueue = s.waitingRoom.indexWhere((p) => p.id == inPlayerId);
    if (inQueue != -1) {
      incoming = s.waitingRoom[inQueue];
      s.waitingRoom.removeAt(inQueue);
      // Send outgoing to queue
      final outPlayer = onTeamA ? court.teamA[outSlot] : court.teamB[outSlot];
      outPlayer.resetWaitTime();
      s.waitingRoom.add(outPlayer);
    } else {
      // Search other courts
      for (var ci = 0; ci < s.activeCourts.length; ci++) {
        if (ci == courtIndex) continue;
        final c = s.activeCourts[ci];
        final ia = c.teamA.indexWhere((p) => p.id == inPlayerId);
        final ib = c.teamB.indexWhere((p) => p.id == inPlayerId);
        if (ia != -1 || ib != -1) {
          inCourtIdx = ci;
          inTeamA = ia != -1;
          inSlot = inTeamA ? ia : ib;
          incoming = inTeamA ? c.teamA[inSlot] : c.teamB[inSlot];
          break;
        }
      }
      if (incoming == null) return;
      final targetCourtIdx = inCourtIdx;
      final targetInTeamA = inTeamA;
      final targetSlot = inSlot;
      if (targetCourtIdx == null ||
          targetInTeamA == null ||
          targetSlot == null) {
        return;
      }

      // Swap the outgoing player into the incoming player's slot
      final outPlayer = onTeamA ? court.teamA[outSlot] : court.teamB[outSlot];
      final otherCourt = s.activeCourts[targetCourtIdx];
      if (targetInTeamA) {
        otherCourt.teamA[targetSlot] = outPlayer;
      } else {
        otherCourt.teamB[targetSlot] = outPlayer;
      }
    }

    // Place incoming into the slot on this court
    if (onTeamA) {
      court.teamA[outSlot] = incoming;
    } else {
      court.teamB[outSlot] = incoming;
    }

    _haptic();
    notifyListeners();
    _db.updateSession(s);
  }

  /// Substitute a player on court with one from the waiting room (or just
  /// send the on-court player back to the queue if [inPlayerId] is null).
  void substitutePlayer({
    required String sessionId,
    required int courtIndex,
    required String outPlayerId,
    String? inPlayerId,
  }) {
    final s = getSession(sessionId);
    if (s == null || courtIndex >= s.activeCourts.length) return;
    final court = s.activeCourts[courtIndex];

    // Find which team/slot the outgoing player is in.
    final inA = court.teamA.indexWhere((p) => p.id == outPlayerId);
    final inB = court.teamB.indexWhere((p) => p.id == outPlayerId);
    if (inA == -1 && inB == -1) return;

    final onTeamA = inA != -1;
    final slot = onTeamA ? inA : inB;
    final outPlayer = onTeamA ? court.teamA[slot] : court.teamB[slot];

    // Return outgoing player to queue.
    outPlayer.resetWaitTime();
    if (!s.waitingRoom.any((x) => x.id == outPlayer.id)) {
      s.waitingRoom.add(outPlayer);
    }

    if (inPlayerId == null) {
      // Just remove from court — leave the slot empty.
      if (onTeamA) {
        court.teamA.removeAt(slot);
      } else {
        court.teamB.removeAt(slot);
      }
    } else {
      // Swap with waiting-room player.
      Player? incoming;
      try {
        incoming = s.waitingRoom.firstWhere((p) => p.id == inPlayerId);
      } catch (_) {
        return;
      }

      s.waitingRoom.removeWhere((p) => p.id == inPlayerId);
      if (onTeamA) {
        court.teamA[slot] = incoming;
      } else {
        court.teamB[slot] = incoming;
      }
    }

    _haptic();
    notifyListeners();
    _db.updateSession(s);
  }

  // ── Team assignment ────────────────────────────────────────

  List<List<Player>> _assignTeams(
    List<Player> players,
    TeamAssignmentMode mode,
    CourtType type,
  ) {
    if (type == CourtType.singles) {
      return [
        [players[0]],
        [players[1]],
      ];
    }

    final pairs = <List<Player>>[];
    final usedIds = <String>{};

    for (final p in players) {
      if (usedIds.contains(p.id)) continue;

      final partnerId = p.preferredPartnerId;
      if (partnerId == null) continue;

      final partnerIdx = players.indexWhere((x) => x.id == partnerId);
      if (partnerIdx == -1) continue;

      final partner = players[partnerIdx];
      if (usedIds.contains(partner.id)) continue;

      pairs.add([p, partner]);
      usedIds.addAll([p.id, partner.id]);
    }

    if (pairs.length >= 2) {
      return [pairs[0], pairs[1]];
    }

    if (pairs.length == 1) {
      final rest = players.where((p) => !usedIds.contains(p.id)).toList();
      return [pairs[0], rest];
    }

    final p = [...players];
    switch (mode) {
      case TeamAssignmentMode.random:
        p.shuffle(Random());
        return [p.sublist(0, 2), p.sublist(2, 4)];
      case TeamAssignmentMode.perLevel:
        p.sort((a, b) => a.skill.index.compareTo(b.skill.index));
        return [
          [p[0], p[3]],
          [p[1], p[2]],
        ];
      case TeamAssignmentMode.balanced:
        p.sort((a, b) => b.winRate.compareTo(a.winRate));
        return [
          [p[0], p[3]],
          [p[1], p[2]],
        ];
    }
  }
}
