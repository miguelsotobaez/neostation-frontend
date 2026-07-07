import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/retro_achievements_user_awards.dart';
import 'package:neostation/services/retro_achievements_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('RetroAchievementsService', () {
    test('uses the supplied API key when provided', () {
      expect(RetroAchievementsService.resolveApiKey('demo-key'), 'demo-key');
    });

    test('falls back to the environment key when no API key is supplied', () {
      expect(RetroAchievementsService.resolveApiKey(''), '');
    });

    test('should return correct console ID for NES', () {
      expect(RetroAchievementsService.getConsoleIdForSystem('nes'), 7);
    });

    test('should return correct console ID for SNES', () {
      expect(RetroAchievementsService.getConsoleIdForSystem('snes'), 3);
    });

    test('should return correct console ID for Genesis', () {
      expect(RetroAchievementsService.getConsoleIdForSystem('genesis'), 1);
    });

    test('should return correct console ID for PSX', () {
      expect(RetroAchievementsService.getConsoleIdForSystem('psx'), 12);
    });

    test('should be case-insensitive', () {
      expect(RetroAchievementsService.getConsoleIdForSystem('PSX'), 12);
      expect(RetroAchievementsService.getConsoleIdForSystem('Psx'), 12);
    });

    test('should return null for unknown system', () {
      expect(RetroAchievementsService.getConsoleIdForSystem('unknown'), null);
    });

    test('should return null for empty string', () {
      expect(RetroAchievementsService.getConsoleIdForSystem(''), null);
    });

    test(
      'requests newest achievement comments with documented parameters',
      () async {
        late Uri requestedUri;
        final client = MockClient((request) async {
          requestedUri = request.url;
          return http.Response(
            '{"Count":1,"Total":1,"Results":[{"User":"Tester","ULID":"01ABC","Submitted":"2024-07-31T11:22:23Z","CommentText":"Helpful"}]}',
            200,
          );
        });

        final result = await RetroAchievementsService.getAchievementComments(
          1234,
          count: 25,
          offset: 50,
          apiKey: 'secret-key',
          client: client,
        );

        expect(requestedUri.path, '/API/API_GetComments.php');
        expect(requestedUri.queryParameters['t'], '2');
        expect(requestedUri.queryParameters['i'], '1234');
        expect(requestedUri.queryParameters['c'], '25');
        expect(requestedUri.queryParameters['o'], '50');
        expect(requestedUri.queryParameters['sort'], '-submitted');
        expect(requestedUri.queryParameters['y'], 'secret-key');
        expect(result.results.single.commentText, 'Helpful');
      },
    );

    test('rejects comments requests without an API key', () async {
      expect(
        () => RetroAchievementsService.getAchievementComments(1234, apiKey: ''),
        throwsStateError,
      );
    });

    test('requests recent unlocks with documented lookback parameter', () async {
      late Uri requestedUri;
      final client = MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          '[{"Date":"2023-12-27 16:04:50","HardcoreMode":1,"AchievementID":98012,"Title":"Beginner I","Description":"Clear stages 01 - 05 in Quest.","BadgeName":"108302","Points":5,"TrueRatio":25,"Type":null,"Author":"jos","AuthorULID":"ULID","GameTitle":"Pokemon Pinball mini","GameIcon":"/Images/028399.png","GameID":14715,"ConsoleName":"Pokemon Mini","BadgeURL":"/Badge/108302.png","GameURL":"/game/14715"}]',
          200,
        );
      });

      final result = await RetroAchievementsService.getUserRecentAchievements(
        'Scott',
        minutes: 43200,
        apiKey: 'secret-key',
        client: client,
      );

      expect(requestedUri.path, '/API/API_GetUserRecentAchievements.php');
      expect(requestedUri.queryParameters['u'], 'Scott');
      expect(requestedUri.queryParameters['m'], '43200');
      expect(requestedUri.queryParameters['y'], 'secret-key');
      expect(result.single.gameId, 14715);
    });

    test('requests recently played games with documented pagination', () async {
      late Uri requestedUri;
      final client = MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          '[{"GameID":11332,"ConsoleID":12,"ConsoleName":"PlayStation","Title":"Final Fantasy Origins","ImageIcon":"/Images/060249.png","ImageTitle":"/Images/026707.png","ImageIngame":"/Images/026708.png","ImageBoxArt":"/Images/046257.png","LastPlayed":"2023-10-27 00:30:04","AchievementsTotal":119,"NumPossibleAchievements":119,"PossibleScore":945,"NumAchieved":38,"ScoreAchieved":382,"NumAchievedHardcore":38,"ScoreAchievedHardcore":382}]',
          200,
        );
      });

      final result = await RetroAchievementsService.getUserRecentlyPlayedGames(
        'MaxMilyin',
        count: 12,
        offset: 3,
        apiKey: 'secret-key',
        client: client,
      );

      expect(requestedUri.path, '/API/API_GetUserRecentlyPlayedGames.php');
      expect(requestedUri.queryParameters['u'], 'MaxMilyin');
      expect(requestedUri.queryParameters['c'], '12');
      expect(requestedUri.queryParameters['o'], '3');
      expect(result.single.consoleName, 'PlayStation');
    });

    test('requests completion progress with documented pagination', () async {
      late Uri requestedUri;
      final client = MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          '{"Count":100,"Total":1287,"Results":[{"GameID":20246,"Title":"Knuckles","ImageIcon":"/Images/074560.png","ConsoleID":1,"ConsoleName":"Mega Drive / Genesis","MaxPossible":0,"NumAwarded":0,"NumAwardedHardcore":0,"MostRecentAwardedDate":"2023-10-27T02:52:34+00:00","HighestAwardKind":"beaten-hardcore","HighestAwardDate":"2023-10-27T02:52:34+00:00"}]}',
          200,
        );
      });

      final result = await RetroAchievementsService.getUserCompletionProgress(
        'MaxMilyin',
        count: 100,
        offset: 25,
        apiKey: 'secret-key',
        client: client,
      );

      expect(requestedUri.path, '/API/API_GetUserCompletionProgress.php');
      expect(requestedUri.queryParameters['u'], 'MaxMilyin');
      expect(requestedUri.queryParameters['c'], '100');
      expect(requestedUri.queryParameters['o'], '25');
      expect(result.total, 1287);
      expect(result.results.single.highestAwardKind, 'beaten-hardcore');
    });

    test(
      'user awards expose mastery and completion rows via AwardDataExtra mode',
      () {
        final awards = RetroAchievementsUserAwards.fromJson({
          'TotalAwardsCount': 2,
          'HiddenAwardsCount': 0,
          'MasteryAwardsCount': 1,
          'CompletionAwardsCount': 1,
          'BeatenHardcoreAwardsCount': 0,
          'BeatenSoftcoreAwardsCount': 0,
          'EventAwardsCount': 0,
          'SiteAwardsCount': 0,
          'VisibleUserAwards': [
            {
              'AwardedAt': '2024-01-02T00:00:00+00:00',
              'AwardType': 'Mastery/Completion',
              'AwardData': 100,
              'AwardDataExtra': 1,
              'DisplayOrder': 0,
              'Title': 'Hardcore Game',
              'ConsoleID': 1,
              'ConsoleName': 'Mega Drive / Genesis',
              'Flags': 0,
              'ImageIcon': '/Images/1.png',
            },
            {
              'AwardedAt': '2024-01-03T00:00:00+00:00',
              'AwardType': 'Mastery/Completion',
              'AwardData': 101,
              'AwardDataExtra': 0,
              'DisplayOrder': 0,
              'Title': 'Softcore Game',
              'ConsoleID': 1,
              'ConsoleName': 'Mega Drive / Genesis',
              'Flags': 0,
              'ImageIcon': '/Images/2.png',
            },
          ],
        });

        final masteries = awards.visibleUserAwards
            .where(
              (award) =>
                  award.awardType == 'Mastery/Completion' &&
                  award.awardDataExtra == 1,
            )
            .toList();
        final completions = awards.visibleUserAwards
            .where(
              (award) =>
                  award.awardType == 'Mastery/Completion' &&
                  award.awardDataExtra == 0,
            )
            .toList();

        expect(masteries.single.title, 'Hardcore Game');
        expect(completions.single.title, 'Softcore Game');
      },
    );
  });
}
