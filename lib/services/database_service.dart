// lib/services/database_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/player.dart';
import '../models/session.dart';
import 'queue_service.dart' show MatchRecord;

class DatabaseService {
  static const _sessionsKey = 'aero_sessions';
  static const _playersKey = 'aero_players';
  static const _historyKey = 'aero_history';

  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── Sessions ──────────────────────────────────────────────

  Future<List<Session>> loadSessions() async {
    final raw = _prefs.getString(_sessionsKey);
    if (raw == null) return [];
    final List<dynamic> jsonList = jsonDecode(raw);
    final allPlayers = await _loadAllPlayers();

    return jsonList.map((j) {
      final id = j['id'] as String;
      final sessionPlayers = allPlayers
          .where((p) => p.sessionId == id)
          .map((p) => p.player)
          .toList();
      final courts = _decodeCourts(
        j['courtsJson'] as String? ?? '[]',
        sessionPlayers,
      );
      final onCourtIds = courts
          .expand((c) => c.allPlayers)
          .map((p) => p.id)
          .toSet();
      final waitingRoom = sessionPlayers
          .where((p) => !onCourtIds.contains(p.id))
          .toList();

      return Session(
        id: id,
        name: j['name'] as String,
        date: DateTime.parse(j['date'] as String),
        courtCount: j['courtCount'] as int? ?? 2,
        isActive: j['isActive'] as bool? ?? true,
        isEnded: j['isEnded'] as bool? ?? false,
        teamMode: TeamAssignmentMode.values.byName(
          j['teamMode'] as String? ?? 'balanced',
        ),
        defaultCourtType: CourtType.values.byName(
          j['defaultCourtType'] as String? ?? 'doubles',
        ),
        players: sessionPlayers,
        waitingRoom: waitingRoom,
        activeCourts: courts,
      );
    }).toList();
  }

  Future<void> saveSession(Session session) async {
    final sessions = await _loadRaw(_sessionsKey);
    final idx = sessions.indexWhere((s) => s['id'] == session.id);
    final encoded = _encodeSession(session);
    if (idx == -1) {
      sessions.insert(0, encoded);
    } else {
      sessions[idx] = encoded;
    }
    await _prefs.setString(_sessionsKey, jsonEncode(sessions));
    await _savePlayers(session);
  }

  Future<void> updateSession(Session s) => saveSession(s);

  Future<void> endSession(String sessionId) async {
    final sessions = await _loadRaw(_sessionsKey);
    final idx = sessions.indexWhere((s) => s['id'] == sessionId);
    if (idx == -1) return;
    sessions[idx]['isActive'] = false;
    sessions[idx]['isEnded'] = true;
    await _prefs.setString(_sessionsKey, jsonEncode(sessions));
  }

  Future<void> deleteSession(String sessionId) async {
    final sessions = await _loadRaw(_sessionsKey);
    sessions.removeWhere((s) => s['id'] == sessionId);
    await _prefs.setString(_sessionsKey, jsonEncode(sessions));
    final players = await _loadRaw(_playersKey);
    players.removeWhere((p) => p['sessionId'] == sessionId);
    await _prefs.setString(_playersKey, jsonEncode(players));
  }

  // ── Players ───────────────────────────────────────────────

  Future<void> savePlayer(Player player, String sessionId) async {
    final all = await _loadRaw(_playersKey);
    final idx = all.indexWhere((p) => p['id'] == player.id);
    final enc = _encodePlayer(player, sessionId);
    if (idx == -1) {
      all.add(enc);
    } else {
      all[idx] = enc;
    }
    await _prefs.setString(_playersKey, jsonEncode(all));
  }

  Future<void> savePlayers(List<Player> players, String sessionId) async {
    final all = await _loadRaw(_playersKey);
    for (final p in players) {
      final idx = all.indexWhere((x) => x['id'] == p.id);
      final enc = _encodePlayer(p, sessionId);
      if (idx == -1) {
        all.add(enc);
      } else {
        all[idx] = enc;
      }
    }
    await _prefs.setString(_playersKey, jsonEncode(all));
  }

  Future<void> deletePlayer(String playerId) async {
    final all = await _loadRaw(_playersKey);
    all.removeWhere((p) => p['id'] == playerId);
    await _prefs.setString(_playersKey, jsonEncode(all));
  }

  // ── Match history ─────────────────────────────────────────

  Future<List<MatchRecord>> loadMatchHistory() async {
    final raw = _prefs.getString(_historyKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((j) => MatchRecord.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveMatchRecord(MatchRecord record) async {
    final all = await _loadRaw(_historyKey);
    all.insert(0, record.toJson());
    await _prefs.setString(_historyKey, jsonEncode(all));
  }

  // ── Helpers ───────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _loadRaw(String key) async {
    final raw = _prefs.getString(key);
    if (raw == null) return [];
    return List<Map<String, dynamic>>.from(jsonDecode(raw));
  }

  Future<List<({Player player, String sessionId})>> _loadAllPlayers() async {
    final raw = await _loadRaw(_playersKey);
    return raw
        .map(
          (j) =>
              (player: _decodePlayer(j), sessionId: j['sessionId'] as String),
        )
        .toList();
  }

  Future<void> _savePlayers(Session session) async {
    await savePlayers(session.players, session.id);
  }

  Future<void> saveAllMatchHistory(List<MatchRecord> records) async {
    await _prefs.setString(
      _historyKey,
      jsonEncode(records.map((r) => r.toJson()).toList()),
    );
  }

  Map<String, dynamic> _encodeSession(Session s) => {
    'id': s.id,
    'name': s.name,
    'date': s.date.toIso8601String(),
    'courtCount': s.courtCount,
    'isActive': s.isActive,
    'isEnded': s.isEnded,
    'teamMode': s.teamMode.name,
    'defaultCourtType': s.defaultCourtType.name,
    'courtsJson': _encodeCourts(s.activeCourts),
  };

  Map<String, dynamic> _encodePlayer(Player p, String sessionId) => {
    'id': p.id,
    'sessionId': sessionId,
    'name': p.name,
    'skill': p.skill.name,
    'gamesPlayed': p.gamesPlayed,
    'wins': p.wins,
    'losses': p.losses,
    'currentStreak': p.currentStreak,
    'isPresent': p.isPresent,
    'lastWaitStartTime': p.lastWaitStartTime.toIso8601String(),
    'headToHead': p.headToHead,
    'preferredPartnerId': p.preferredPartnerId,
  };

  Player _decodePlayer(Map<String, dynamic> j) {
    final h2h = <String, List<int>>{};
    final raw = j['headToHead'] as Map<String, dynamic>? ?? {};
    for (final e in raw.entries) {
      h2h[e.key] = List<int>.from(e.value as List);
    }
    return Player(
      id: j['id'] as String,
      name: j['name'] as String,
      skill: SkillLevel.values.byName(j['skill'] as String),
      gamesPlayed: j['gamesPlayed'] as int? ?? 0,
      wins: j['wins'] as int? ?? 0,
      losses: j['losses'] as int? ?? 0,
      currentStreak: j['currentStreak'] as int? ?? 0,
      isPresent: j['isPresent'] as bool? ?? true,
      lastWaitStartTime: DateTime.parse(j['lastWaitStartTime'] as String),
      headToHead: h2h,
      preferredPartnerId: j['preferredPartnerId'] as String?,
    );
  }

  String _encodeCourts(List<Court> courts) => jsonEncode(
    courts
        .map(
          (c) => {
            'index': c.index,
            'teamA': c.teamA.map((p) => p.id).toList(),
            'teamB': c.teamB.map((p) => p.id).toList(),
            'type': c.type.name,
            'matchStartTime': c.matchStartTime?.toIso8601String(),
          },
        )
        .toList(),
  );

  List<Court> _decodeCourts(String json, List<Player> players) {
    final list = jsonDecode(json) as List<dynamic>;
    final playerMap = {for (final p in players) p.id: p};
    return list
        .map(
          (c) => Court(
            index: c['index'] as int,
            teamA: (c['teamA'] as List)
                .map((id) => playerMap[id as String])
                .whereType<Player>()
                .toList(),
            teamB: (c['teamB'] as List)
                .map((id) => playerMap[id as String])
                .whereType<Player>()
                .toList(),
            type: CourtType.values.byName(c['type'] as String? ?? 'doubles'),
            matchStartTime: c['matchStartTime'] != null
                ? DateTime.parse(c['matchStartTime'] as String)
                : null,
          ),
        )
        .toList();
  }
}
