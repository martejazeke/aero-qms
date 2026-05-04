// lib/models/session.dart

import 'player.dart';

class Session {
  final String id;
  String name;
  final DateTime date;
  final int courtCount;
  bool isActive;
  bool isEnded;
  TeamAssignmentMode teamMode;

  final List<Player> players;
  final List<Player> waitingRoom;
  final List<Court> activeCourts;

  Session({
    required this.id,
    required this.name,
    required this.date,
    this.courtCount = 2,
    this.isActive   = true,
    this.isEnded    = false,
    this.teamMode   = TeamAssignmentMode.balanced,
    List<Player>?  players,
    List<Player>?  waitingRoom,
    List<Court>?   activeCourts,
  })  : players      = players      ?? [],
        waitingRoom  = waitingRoom  ?? [],
        activeCourts = activeCourts ?? [];

  int get playerCount => players.length;
}