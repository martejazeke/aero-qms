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

  MatchRecord({
    required this.sessionId,
    required this.playedAt,
    required this.teamANames,
    required this.teamBNames,
    required this.winnerTeam,
    this.courtType = CourtType.doubles,
  });

  Map<String, dynamic> toJson() => {
    'sessionId':  sessionId,
    'playedAt':   playedAt.toIso8601String(),
    'teamANames': teamANames,
    'teamBNames': teamBNames,
    'winnerTeam': winnerTeam,
    'courtType':  courtType.name,
  };

  factory MatchRecord.fromJson(Map<String, dynamic> j) => MatchRecord(
    sessionId:  j['sessionId'] as String,
    playedAt:   DateTime.parse(j['playedAt'] as String),
    teamANames: List<String>.from(j['teamANames'] as List),
    teamBNames: List<String>.from(j['teamBNames'] as List),
    winnerTeam: j['winnerTeam'] as String,
    courtType:  CourtType.values.byName(
        j['courtType'] as String? ?? 'doubles'),
  );
}

// ── QueueService ──────────────────────────────────────────────

class QueueService extends ChangeNotifier {
  final MatchmakingEngine _engine   = MatchmakingEngine();
  final DatabaseService   _db       = DatabaseService();
  SettingsService?        _settings;

  final List<Session>     _sessions = [];
  final List<MatchRecord> _history  = [];

  bool _loading = true;
  bool get loading  => _loading;

  List<Session>     get sessions         => List.unmodifiable(_sessions);
  List<Session>     get activeSessions   =>
      _sessions.where((s) => !s.isEnded).toList();
  List<Session>     get archivedSessions =>
      _sessions.where((s) => s.isEnded).toList();
  List<MatchRecord> get matchHistory     =>
      List.unmodifiable(_history);

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
    final loaded  = await _db.loadSessions();
    final history = await _db.loadMatchHistory();
    _sessions ..clear() ..addAll(loaded);
    _history  ..clear() ..addAll(history);
    _loading = false;
    notifyListeners();
  }

  Session? getSession(String id) {
    try { return _sessions.firstWhere((s) => s.id == id); }
    catch (_) { return null; }
  }

  // ── Session management ─────────────────────────────────────

  Future<void> createSession({
    required String name,
    required DateTime date,
    int courtCount = 2,
    TeamAssignmentMode teamMode = TeamAssignmentMode.balanced,
    CourtType defaultCourtType  = CourtType.doubles,
  }) async {
    _haptic();
    final session = Session(
      id:               DateTime.now().millisecondsSinceEpoch.toString(),
      name:             name,
      date:             date,
      courtCount:       courtCount,
      isActive:         true,
      isEnded:          false,
      teamMode:         teamMode,
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
    s.isEnded  = true;
    notifyListeners();
    await _db.endSession(sessionId);
  }

  Future<void> deleteSession(String sessionId) async {
    _sessions.removeWhere((s) => s.id == sessionId);
    notifyListeners();
    await _db.deleteSession(sessionId);
  }

  Future<void> updateTeamMode(
      String sessionId, TeamAssignmentMode mode) async {
    final s = getSession(sessionId);
    if (s == null) return;
    s.teamMode = mode;
    notifyListeners();
    await _db.updateSession(s);
  }

  Future<void> updateDefaultCourtType(
      String sessionId, CourtType type) async {
    final s = getSession(sessionId);
    if (s == null) return;
    s.defaultCourtType = type;
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
      id:    _newPlayerId(sessionId),
      name:  name,
      skill: skill,
    );
    s.players.add(player);
    s.waitingRoom.add(player);
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
        id:                _newPlayerId(sessionId),
        name:              name,
        skill:             skill,
        isPresent:         false, // starts absent — tap to check in
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
        // Returning — reset wait time and add to queue
        p.resetWaitTime();
        if (!s.waitingRoom.any((x) => x.id == p.id) &&
            !s.activeCourts.any((c) => c.allPlayers.any((x) => x.id == p.id))) {
          s.waitingRoom.add(p);
        }
      } else {
        // Leaving — remove from queue (keep stats, keep in session)
        s.waitingRoom.removeWhere((x) => x.id == p.id);
      }
    } catch (_) { return; }
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
      p.name  = name;
      p.skill = skill;
      // Also update in waitingRoom (same object ref, but be safe)
      final inQueue = s.waitingRoom.firstWhere(
          (x) => x.id == playerId, orElse: () => p);
      inQueue.name  = name;
      inQueue.skill = skill;
    } catch (_) { return; }
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
    try { player = s.players.firstWhere((p) => p.id == playerId); }
    catch (_) { return; }

    if (player.preferredPartnerId != null) {
      try {
        final oldPartner = s.players
            .firstWhere((p) => p.id == player!.preferredPartnerId);
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
                (p) => p.id == partner.preferredPartnerId);
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
    s.activeCourts.add(Court(
      index: nextIndex,
      teamA: [],
      teamB: [],
      type:  type ?? s.defaultCourtType,
    ));
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
          index: i, teamA: c.teamA, teamB: c.teamB, type: c.type);
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
      s.activeCourts.add(Court(
        index: targetIdx,
        teamA: [],
        teamB: [],
        type:  s.defaultCourtType,
      ));
    }

    final type   = s.activeCourts[targetIdx].type;
    final needed = type == CourtType.singles ? 2 : 4;

    if (s.waitingRoom.length < needed) return false;

    _haptic();

    // Pass the full waiting room to the engine. The engine scores every
    // player and enforces the priority-window rule internally — preferred
    // partners are only paired together when both are already in the
    // natural top-[needed] by wait time, so no queue-jumping occurs.
    final result   = _engine.findBestMatch(s.waitingRoom, needed);
    var   selected = result.selectedPlayers;

    // Safety fallback: if the engine somehow returns too few players,
    // just take the longest-waiting ones directly.
    if (selected.length < needed) {
      s.waitingRoom.sort(
          (a, b) => a.lastWaitStartTime.compareTo(b.lastWaitStartTime));
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
      type:  type,
    );

    _engine.recordMatch(selected);
    notifyListeners();
    return true;
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
      s.activeCourts.add(Court(
        index: s.activeCourts.length, teamA: [], teamB: [],
        type:  s.defaultCourtType));
    }

    final court = s.activeCourts[courtIndex];
    Player? player;
    try { player = s.waitingRoom.firstWhere((p) => p.id == playerId); }
    catch (_) {
      try { player = s.players.firstWhere((p) => p.id == playerId); }
      catch (_) { return; }
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
    final list  = team == 'A' ? court.teamA : court.teamB;
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

    final court   = s.activeCourts[courtIndex];
    final winners = teamAWon ? court.teamA : court.teamB;
    final losers  = teamAWon ? court.teamB : court.teamA;

    final record = MatchRecord(
      sessionId:  sessionId,
      playedAt:   DateTime.now(),
      teamANames: court.teamA.map((p) => p.name).toList(),
      teamBNames: court.teamB.map((p) => p.name).toList(),
      winnerTeam: teamAWon ? 'A' : 'B',
      courtType:  court.type,
    );
    _history.insert(0, record);
    _db.saveMatchRecord(record);

    final loserIds  = losers.map((p) => p.id).toList();
    final winnerIds = winners.map((p) => p.id).toList();

    for (final p in winners) {
      p.recordWin(opponentIds: loserIds);
      p.resetWaitTime();
      s.waitingRoom.add(p);
    }
    for (final p in losers) {
      p.recordLoss(opponentIds: winnerIds);
      p.resetWaitTime();
      s.waitingRoom.add(p);
    }

    s.activeCourts[courtIndex] = Court(
      index: courtIndex,
      teamA: [],
      teamB: [],
      type:  court.type,
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
    final court     = s.activeCourts[courtIndex];
    final inTeamA_A = court.teamA.any((p) => p.id == playerIdA);
    final inTeamA_B = court.teamA.any((p) => p.id == playerIdB);
    if (inTeamA_A == inTeamA_B) return;

    final idxA = inTeamA_A
        ? court.teamA.indexWhere((p) => p.id == playerIdA)
        : court.teamB.indexWhere((p) => p.id == playerIdA);
    final idxB = inTeamA_B
        ? court.teamA.indexWhere((p) => p.id == playerIdB)
        : court.teamB.indexWhere((p) => p.id == playerIdB);

    final pA = inTeamA_A ? court.teamA[idxA] : court.teamB[idxA];
    final pB = inTeamA_B ? court.teamA[idxB] : court.teamB[idxB];

    if (inTeamA_A) { court.teamA[idxA] = pB; court.teamB[idxB] = pA; }
    else           { court.teamB[idxA] = pB; court.teamA[idxB] = pA; }

    notifyListeners();
    _db.updateSession(s);
  }

  /// Substitute a player on court with one from the waiting room (or just
  /// send the on-court player back to the queue if [inPlayerId] is null).
  void substitutePlayer({
    required String sessionId,
    required int    courtIndex,
    required String outPlayerId,
    String?         inPlayerId,
  }) {
    final s = getSession(sessionId);
    if (s == null || courtIndex >= s.activeCourts.length) return;
    final court = s.activeCourts[courtIndex];

    // Find which team/slot the outgoing player is in.
    final inA   = court.teamA.indexWhere((p) => p.id == outPlayerId);
    final inB   = court.teamB.indexWhere((p) => p.id == outPlayerId);
    if (inA == -1 && inB == -1) return;

    final onTeamA = inA != -1;
    final slot    = onTeamA ? inA : inB;
    final outPlayer = onTeamA ? court.teamA[slot] : court.teamB[slot];

    // Return outgoing player to queue.
    outPlayer.resetWaitTime();
    if (!s.waitingRoom.any((x) => x.id == outPlayer.id)) {
      s.waitingRoom.add(outPlayer);
    }

    if (inPlayerId == null) {
      // Just remove from court — leave the slot empty.
      if (onTeamA) court.teamA.removeAt(slot);
      else         court.teamB.removeAt(slot);
    } else {
      // Swap with waiting-room player.
      Player? incoming;
      try { incoming = s.waitingRoom.firstWhere((p) => p.id == inPlayerId); }
      catch (_) { return; }

      s.waitingRoom.removeWhere((p) => p.id == inPlayerId);
      if (onTeamA) court.teamA[slot] = incoming;
      else         court.teamB[slot] = incoming;
    }

    _haptic();
    notifyListeners();
    _db.updateSession(s);
  }

  // ── Team assignment ────────────────────────────────────────

  List<List<Player>> _assignTeams(
      List<Player> players, TeamAssignmentMode mode, CourtType type) {
    if (type == CourtType.singles) {
      return [[players[0]], [players[1]]];
    }

    final paired   = <Player>[];
    final unpaired = <Player>[];
    final usedIds  = <String>{};

    for (final p in players) {
      if (usedIds.contains(p.id)) continue;
      if (p.preferredPartnerId != null) {
        final partnerIdx = players
            .indexWhere((x) => x.id == p.preferredPartnerId);
        if (partnerIdx != -1 && !usedIds.contains(p.preferredPartnerId)) {
          paired.addAll([p, players[partnerIdx]]);
          usedIds.addAll([p.id, p.preferredPartnerId!]);
          continue;
        }
      }
      if (!usedIds.contains(p.id)) {
        unpaired.add(p);
        usedIds.add(p.id);
      }
    }

    if (paired.length == 2 && unpaired.length == 2) {
      return [paired, unpaired];
    }
    if (paired.length == 4) {
      return [[paired[0], paired[1]], [paired[2], paired[3]]];
    }

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