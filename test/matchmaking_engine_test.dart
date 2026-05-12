import 'package:aero/logic/matchmaking_engine.dart';
import 'package:aero/models/player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('doubles selection keeps two preferred pairs together', () {
    final now = DateTime.now();

    Player player(String id, int waitMinutes, {String? partnerId}) {
      return Player(
        id: id,
        name: 'Player $id',
        skill: SkillLevel.intermediate,
        preferredPartnerId: partnerId,
        lastWaitStartTime: now.subtract(Duration(minutes: waitMinutes)),
      );
    }

    final players = [
      player('2', 80, partnerId: '8'),
      player('1', 70),
      player('7', 60, partnerId: '6'),
      player('3', 50),
      player('4', 40),
      player('5', 30),
      player('6', 20, partnerId: '7'),
      player('8', 10, partnerId: '2'),
    ];

    final result = MatchmakingEngine().findBestMatch(players, 4);
    final selectedIds = result.selectedPlayers.map((p) => p.id).toList();

    expect(selectedIds, containsAll(['2', '8', '6', '7']));
    expect(selectedIds, isNot(contains('1')));
  });
}
