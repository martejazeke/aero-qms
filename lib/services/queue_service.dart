// lib/services/queue_service.dart

import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/player.dart';
import '../models/session.dart';
import '../logic/matchmaking_engine.dart';
import 'database_service.dart';

class QueueService extends ChangeNotifier {
  final MatchmakingEngine _engine = MatchmakingEngine();
  final DatabaseService   _db     = DatabaseService();
  final List<Session>     _sessions = [];
  
  bool _loading = true;
  bool get loading => _loading;

  List<Session> get sessions     => List.unmodifiable(_sessions);
  List<Session> get activeSessions =>
      _sessions.where((s) => !s.isEnded).toList();
  List<Session> get archivedSessions =>
      _sessions.where((s) => s.isEnded).toList();

  // ── Init ──────────────────────────────────────────────────

  Future<void> loadFromDatabase() async {
    _loading = true;
    notifyListeners();
    final loaded = await _db.loadSessions();
    _sessions
      ..clear()
      ..addAll(loaded);
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
  }) async {
    final session = Session(
      id:         DateTime.now().millisecondsSinceEpoch.toString(),
      name:       name,
      date:       date,
      courtCount: courtCount,
      isActive:   true,
      isEnded:    false,
      teamMode:   teamMode,
    );
    _sessions.insert(0, session);
    notifyListeners();
    await _db.saveSession(session);
  }

  Future<void> endSession(String sessionId) async {
    final session = getSession(sessionId);
    if (session == null) return;
    session.isActive = false;
    session.isEnded  = true;
    notifyListeners();
    await _db.endSession(sessionId);
  }

  Future<void> deleteSession(String sessionId) async {
    _sessions.removeWhere((s) => s.id == sessionId);
    notifyListeners();
    await _db.deleteSession(sessionId);
  }

  Future<void> updateTeamMode(String sessionId, TeamAssignmentMode mode) async {
    final session = getSession(sessionId);
    if (session == null) return;
    session.teamMode = mode;
    notifyListeners();
    await _db.updateSession(session);
  }

  // ── Player management ──────────────────────────────────────

  Future<void> addPlayerToSession({
    required String sessionId,
    required String name,
    required SkillLevel skill,
  }) async {
    final session = getSession(sessionId);
    if (session == null) return;

    final player = Player(
      id:   '${sessionId}_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      skill: skill,
    );
    session.players.add(player);
    session.waitingRoom.add(player);
    notifyListeners();
    await _db.savePlayer(player, sessionId);
  }

  Future<void> removePlayerFromSession({
    required String sessionId,
    required String playerId,
  }) async {
    final session = getSession(sessionId);
    if (session == null) return;
    session.players.removeWhere((p) => p.id == playerId);
    session.waitingRoom.removeWhere((p) => p.id == playerId);
    notifyListeners();
    await _db.deletePlayer(playerId);
  }

  // ── Court management ───────────────────────────────────────

  void addCourt(String sessionId) {
    final session = getSession(sessionId);
    if (session == null) return;
    // Add an empty court — will be filled manually or by matchmaker
    session.activeCourts.add(Court(
      index: session.activeCourts.length,
      teamA: [],
      teamB: [],
    ));
    notifyListeners();
    _db.updateSession(session);
  }

  void removeCourt(String sessionId, int courtIndex) {
    final session = getSession(sessionId);
    if (session == null) return;
    // Return any players on this court back to waiting room
    final court = session.activeCourts.removeAt(courtIndex);
    for (final p in court.allPlayers) {
      p.resetWaitTime();
      session.waitingRoom.add(p);
    }
    // Re-index remaining courts
    for (var i = 0; i < session.activeCourts.length; i++) {
      session.activeCourts[i] = Court(
        index: i,
        teamA: session.activeCourts[i].teamA,
        teamB: session.activeCourts[i].teamB,
      );
    }
    notifyListeners();
    _db.updateSession(session);
  }

  // ── Matchmaking ────────────────────────────────────────────

  bool fillCourt({required String sessionId, int playersNeeded = 4}) {
    final session = getSession(sessionId);
    if (session == null) return false;
    if (session.waitingRoom.length < playersNeeded) return false;

    final result   = _engine.findBestMatch(session.waitingRoom, playersNeeded);
    final selected = result.selectedPlayers;

    for (final p in selected) {
      session.waitingRoom.removeWhere((x) => x.id == p.id);
    }

    final teams = _assignTeams(selected, session.teamMode);
    session.activeCourts.add(Court(
      index: session.activeCourts.length,
      teamA: teams[0],
      teamB: teams[1],
    ));
    _engine.recordMatch(selected);
    notifyListeners();
    _db.updateSession(session);
    return true;
  }

  /// Manually assign a player to a slot on a court.
  /// [team] is 'A' or 'B', [slotIndex] is 0 or 1.
  void assignPlayerToCourt({
    required String sessionId,
    required int courtIndex,
    required String playerId,
    required String team,
    required int slotIndex,
  }) {
    final session = getSession(sessionId);
    if (session == null) return;
    if (courtIndex >= session.activeCourts.length) return;

    final court = session.activeCourts[courtIndex];
    final player = session.waitingRoom.firstWhere(
      (p) => p.id == playerId,
      orElse: () => session.players.firstWhere((p) => p.id == playerId),
    );

    // Remove from waiting room if present
    session.waitingRoom.removeWhere((p) => p.id == playerId);

    // Remove from any other court slot first
    for (final c in session.activeCourts) {
      c.teamA.removeWhere((p) => p.id == playerId);
      c.teamB.removeWhere((p) => p.id == playerId);
    }

    // If a player already in this slot, send them back to waiting room
    final targetList = team == 'A' ? court.teamA : court.teamB;
    if (slotIndex < targetList.length) {
      final displaced = targetList[slotIndex];
      displaced.resetWaitTime();
      session.waitingRoom.add(displaced);
      targetList[slotIndex] = player;
    } else {
      targetList.add(player);
    }

    notifyListeners();
    _db.updateSession(session);
  }

  void endMatch({
    required String sessionId,
    required int courtIndex,
    required bool teamAWon,
  }) {
    final session = getSession(sessionId);
    if (session == null) return;
    if (courtIndex >= session.activeCourts.length) return;

    final court   = session.activeCourts.removeAt(courtIndex);
    final winners = teamAWon ? court.teamA : court.teamB;
    final losers  = teamAWon ? court.teamB : court.teamA;

    final loserIds  = losers.map((p) => p.id).toList();
    final winnerIds = winners.map((p) => p.id).toList();

    for (final p in winners) {
      p.recordWin(opponentIds: loserIds);
      p.resetWaitTime();
      session.waitingRoom.add(p);
    }
    for (final p in losers) {
      p.recordLoss(opponentIds: winnerIds);
      p.resetWaitTime();
      session.waitingRoom.add(p);
    }

    notifyListeners();
    _db.savePlayers([...winners, ...losers], sessionId);
    _db.updateSession(session);
  }

  void swapPlayers({
    required String sessionId,
    required int courtIndex,
    required String playerIdA,
    required String playerIdB,
  }) {
    final session = getSession(sessionId);
    if (session == null) return;
    if (courtIndex >= session.activeCourts.length) return;

    final court     = session.activeCourts[courtIndex];
    final inTeamA_A = court.teamA.any((p) => p.id == playerIdA);
    final inTeamA_B = court.teamA.any((p) => p.id == playerIdB);

    if (inTeamA_A == inTeamA_B) return; // same team, no-op

    final idxA = inTeamA_A
        ? court.teamA.indexWhere((p) => p.id == playerIdA)
        : court.teamB.indexWhere((p) => p.id == playerIdA);
    final idxB = inTeamA_B
        ? court.teamA.indexWhere((p) => p.id == playerIdB)
        : court.teamB.indexWhere((p) => p.id == playerIdB);

    final playerA = inTeamA_A ? court.teamA[idxA] : court.teamB[idxA];
    final playerB = inTeamA_B ? court.teamA[idxB] : court.teamB[idxB];

    if (inTeamA_A) {
      court.teamA[idxA] = playerB;
      court.teamB[idxB] = playerA;
    } else {
      court.teamB[idxA] = playerB;
      court.teamA[idxB] = playerA;
    }

    notifyListeners();
    _db.updateSession(session);
  }

  // ── Team assignment ────────────────────────────────────────

  List<List<Player>> _assignTeams(
      List<Player> players, TeamAssignmentMode mode) {
    final p = [...players];
    switch (mode) {
      case TeamAssignmentMode.random:
        p.shuffle(Random());
        return [p.sublist(0, 2), p.sublist(2, 4)];
      case TeamAssignmentMode.perLevel:
        p.sort((a, b) => a.skill.index.compareTo(b.skill.index));
        return [[p[0], p[3]], [p[1], p[2]]];
      case TeamAssignmentMode.balanced:
      default:
        p.sort((a, b) => b.winRate.compareTo(a.winRate));
        return [[p[0], p[3]], [p[1], p[2]]];
    }
  }
}