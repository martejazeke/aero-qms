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

  Future<void> addPlayerToSession({
    required String sessionId,
    required String name,
    required SkillLevel skill,
  }) async {
    final s = getSession(sessionId);
    if (s == null) return;
    _haptic();
    final player = Player(
      id:    '${sessionId}_${DateTime.now().millisecondsSinceEpoch}',
      name:  name,
      skill: skill,
    );
    s.players.add(player);
    s.waitingRoom.add(player);
    notifyListeners();
    await _db.savePlayer(player, sessionId);
  }

  Future<void> removePlayerFromSession({
    required String sessionId,
    required String playerId,
  }) async {
    final s = getSession(sessionId);
    if (s == null) return;
    // Clear partner references
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

  /// Set or clear a player's preferred partner.
  /// Also sets the reverse link so both point to each other.
  Future<void> setPreferredPartner({
    required String sessionId,
    required String playerId,
    required String? partnerId, // null = clear
  }) async {
    final s = getSession(sessionId);
    if (s == null) return;

    Player? player;
    try { player = s.players.firstWhere((p) => p.id == playerId); }
    catch (_) { return; }

    // Clear old reverse link
    if (player.preferredPartnerId != null) {
      try {
        final oldPartner = s.players
            .firstWhere((p) => p.id == player!.preferredPartnerId);
        oldPartner.preferredPartnerId = null;
      } catch (_) {}
    }

    player.preferredPartnerId = partnerId;

    // Set reverse link
    if (partnerId != null) {
      try {
        final partner = s.players.firstWhere((p) => p.id == partnerId);
        // Clear partner's old reverse link first
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
    s.activeCourts.add(Court(
      index: s.activeCourts.length,
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
    // Return excess players to queue if switching to singles
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
    for (var i = 0; i < s.activeCourts.length; i++) {
      final c = s.activeCourts[i];
      s.activeCourts[i] = Court(
          index: i, teamA: c.teamA, teamB: c.teamB, type: c.type);
    }
    notifyListeners();
    _db.updateSession(s);
  }

  // ── Matchmaking ────────────────────────────────────────────

  bool fillCourt({
    required String sessionId,
    int courtIndex = -1,
    CourtType? courtType,
  }) {
    final s = getSession(sessionId);
    if (s == null) return false;

    // Determine court type for this fill
    CourtType type;
    if (courtIndex >= 0 && courtIndex < s.activeCourts.length) {
      type = s.activeCourts[courtIndex].type;
    } else {
      type = courtType ?? s.defaultCourtType;
    }

    final needed = type == CourtType.singles ? 2 : 4;
    if (s.waitingRoom.length < needed) return false;

    _haptic();
    final result   = _engine.findBestMatch(s.waitingRoom, needed);
    final selected = result.selectedPlayers;

    for (final p in selected) {
      s.waitingRoom.removeWhere((x) => x.id == p.id);
    }

    final teams = _assignTeams(selected, s.teamMode, type);
    final court = Court(
      index: courtIndex == -1 ? s.activeCourts.length : courtIndex,
      teamA: teams[0],
      teamB: teams[1],
      type:  type,
    );

    if (courtIndex == -1 || courtIndex >= s.activeCourts.length) {
      s.activeCourts.add(court);
    } else {
      s.activeCourts[courtIndex] = court;
    }

    _engine.recordMatch(selected);
    notifyListeners();
    _db.updateSession(s);
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
    final court  = s.activeCourts[courtIndex];
    final list   = team == 'A' ? court.teamA : court.teamB;
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

    // Reset court to empty (keep slot visible)
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

  // ── Team assignment ────────────────────────────────────────

  List<List<Player>> _assignTeams(
      List<Player> players, TeamAssignmentMode mode, CourtType type) {
    // For singles, teams are always 1v1
    if (type == CourtType.singles) {
      return [[players[0]], [players[1]]];
    }

    // For doubles with preferred partners, keep pairs together
    final paired    = <Player>[];
    final unpaired  = <Player>[];
    final usedIds   = <String>{};

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

    // If we have exactly one pair + 2 unpaired → pair vs unpaired
    if (paired.length == 2 && unpaired.length == 2) {
      return [paired, unpaired];
    }

    // If two pairs → pair A vs pair B
    if (paired.length == 4) {
      return [[paired[0], paired[1]], [paired[2], paired[3]]];
    }

    // Fallback: use mode-based assignment
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