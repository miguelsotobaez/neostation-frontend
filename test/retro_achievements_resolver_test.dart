import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/secondary_achievement_item.dart';
import 'package:neostation/services/retro_achievements_resolver.dart';

void main() {
  group('SecondaryAchievementsSnapshot.earnedIds', () {
    SecondaryAchievementItem item(int id, {required bool earned}) {
      return SecondaryAchievementItem(
        id: id,
        title: 'a$id',
        description: '',
        points: 0,
        badgeName: '',
        displayOrder: id,
        earned: earned,
        earnedHardcore: false,
      );
    }

    test('returns only the ids of earned achievements', () {
      const gameId = 1;
      final snapshot = SecondaryAchievementsSnapshot(
        gameId: gameId,
        gameTitle: 'Game',
        achievements: [
          item(10, earned: true),
          item(20, earned: false),
          item(30, earned: true),
        ],
        earned: 2,
        total: 3,
        points: 0,
        pointsTotal: 0,
        completionPct: '66.67%',
      );

      expect(snapshot.earnedIds, {10, 30});
    });

    test('is empty when nothing is earned', () {
      final snapshot = SecondaryAchievementsSnapshot(
        gameId: 1,
        gameTitle: 'Game',
        achievements: [item(1, earned: false), item(2, earned: false)],
        earned: 0,
        total: 2,
        points: 0,
        pointsTotal: 0,
        completionPct: '0.00%',
      );

      expect(snapshot.earnedIds, isEmpty);
    });
  });
}
