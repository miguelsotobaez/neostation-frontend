import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/retro_achievements_dashboard_models.dart';
import 'package:neostation/models/retro_achievements_gotw.dart';

void main() {
  final weekStartedAt = DateTime.utc(2026, 9, 1);

  group('AotwPersonalProgress.resolve', () {
    test('accepts a matching winner record as positive evidence', () {
      final progress = AotwPersonalProgress.resolve(
        weekStartedAt: weekStartedAt,
        achievementFound: false,
        weeklyUnlockFound: true,
        weeklyUnlockWasHardcore: true,
        weeklyUnlockDate: '2026-09-02T12:00:00+00:00',
      );

      expect(progress.state, AotwUserState.earnedHardcoreThisWeek);
      expect(progress.earnedAt, DateTime.utc(2026, 9, 2, 12));
    });

    test('does not treat an old Unlocks record as earned this week', () {
      final progress = AotwPersonalProgress.resolve(
        weekStartedAt: weekStartedAt,
        achievementFound: true,
        weeklyUnlockFound: true,
        weeklyUnlockWasHardcore: true,
        weeklyUnlockDate: '2026-08-20T12:00:00+00:00',
      );

      expect(progress.state, AotwUserState.earnedBeforeWeek);
      expect(progress.earnedAt, DateTime.utc(2026, 8, 20, 12));
    });

    test('recognizes a hardcore unlock earned during the week', () {
      final progress = AotwPersonalProgress.resolve(
        weekStartedAt: weekStartedAt,
        achievementFound: true,
        dateEarned: '2026-09-02 08:00:00',
        dateEarnedHardcore: '2026-09-02 08:00:00',
      );

      expect(progress.state, AotwUserState.earnedHardcoreThisWeek);
    });

    test('recognizes a casual unlock earned during the week', () {
      final progress = AotwPersonalProgress.resolve(
        weekStartedAt: weekStartedAt,
        achievementFound: true,
        dateEarned: '2026-09-02 08:00:00',
      );

      expect(progress.state, AotwUserState.earnedCasualThisWeek);
    });

    test('distinguishes an achievement earned before the week', () {
      final progress = AotwPersonalProgress.resolve(
        weekStartedAt: weekStartedAt,
        achievementFound: true,
        dateEarnedHardcore: '2026-08-20 08:00:00',
      );

      expect(progress.state, AotwUserState.earnedBeforeWeek);
    });

    test('reports not earned only when achievement data is authoritative', () {
      final progress = AotwPersonalProgress.resolve(
        weekStartedAt: weekStartedAt,
        achievementFound: true,
      );

      expect(progress.state, AotwUserState.notEarned);
    });

    test('does not turn missing or malformed evidence into not earned', () {
      final missing = AotwPersonalProgress.resolve(
        weekStartedAt: weekStartedAt,
        achievementFound: false,
      );
      final malformed = AotwPersonalProgress.resolve(
        weekStartedAt: weekStartedAt,
        achievementFound: true,
        dateEarned: 'not-a-date',
      );

      expect(missing.state, AotwUserState.unknown);
      expect(malformed.state, AotwUserState.unknown);
    });

    test('requires an official week start for date comparison', () {
      final progress = AotwPersonalProgress.resolve(
        weekStartedAt: null,
        achievementFound: true,
        dateEarned: '2026-09-02 08:00:00',
      );

      expect(progress.state, AotwUserState.unknown);
    });
  });

  test('AOTW model parses nullable nested payloads and UTC start time', () {
    final empty = RetroAchievementsGOTW.fromJson(const {
      'Achievement': null,
      'Console': null,
      'Game': null,
      'StartAt': null,
    });
    final active = RetroAchievementsGOTW.fromJson(const {
      'Achievement': {'ID': 1},
      'Console': {'ID': 7, 'Title': 'NES'},
      'Game': {'ID': 42, 'Title': 'Game'},
      'StartAt': '2026-09-01T00:00:00.000000Z',
    });

    expect(empty.achievement.id, 0);
    expect(empty.startDateUtc, isNull);
    expect(active.startDateUtc, DateTime.utc(2026, 9, 1));
  });
}
