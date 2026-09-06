import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/config_model.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/screens/game_screen/game_details_card/tabs/game_details_game_info_tab.dart';
import 'package:neostation/themes/chrome_surface.dart';

/// The game info tab reads in one language: the user's.
///
/// It used to carry a strip of chips, one per language the game happened to be
/// scraped in, which the D-pad walked left and right. That put a language
/// picker in front of someone who had already told the app which language they
/// read, on the one tab whose whole job is to be read, and it charged the
/// description a band of height for the privilege on any game with more than
/// one translation.
class _ConfigAt extends SqliteConfigProvider {
  _ConfigAt(this.language);

  final String language;

  @override
  ConfigModel get config => ConfigModel.empty.copyWith(appLanguage: language);
}

const _system = SystemModel(
  folderName: 'psx',
  realName: 'Sony PlayStation',
  iconImage: '',
  color: '#FFFFFF',
);

/// Distinct text per language, so a finder can only match the right one.
GameModel _game({Map<String, String?>? descriptions}) => GameModel(
  romname: 'A Game (USA).chd',
  realname: 'A Game',
  name: 'A Game',
  year: '1999',
  developer: '',
  publisher: 'Sony',
  genre: 'RPG',
  players: '1',
  rating: 18.0,
  descriptions:
      descriptions ??
      const {
        'en': 'ENGLISH BLURB',
        'fr': 'BLURB FRANCAIS',
        'de': 'DEUTSCHER TEXT',
        'jp': 'JAPANESE TEXT',
        'zh': 'CHINESE TEXT',
      },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await FlutterLocalization.instance.ensureInitialized();
    FlutterLocalization.instance.init(
      mapLocales: [MapLocale('en', AppLocale.en)],
      initLanguageCode: 'en',
    );
  });

  Future<void> pumpTab(
    WidgetTester tester, {
    required String appLanguage,
    Map<String, String?>? descriptions,
  }) async {
    tester.view.physicalSize = const Size(640, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SqliteConfigProvider>(
            create: (_) => _ConfigAt(appLanguage),
          ),
        ],
        child: ScreenUtilInit(
          designSize: const Size(640, 480),
          builder: (context, _) => MaterialApp(
            theme: ThemeData(
              brightness: Brightness.dark,
              extensions: [ChromeSurface.standard()],
            ),
            localizationsDelegates:
                FlutterLocalization.instance.localizationsDelegates,
            supportedLocales: FlutterLocalization.instance.supportedLocales,
            home: Scaffold(
              body: Stack(
                fit: StackFit.expand,
                children: [
                  GameDetailsGameInfoTab(
                    system: _system,
                    game: _game(descriptions: descriptions),
                    fileProvider: FileProvider(),
                    // Non-empty, so the panel renders the scraped view rather
                    // than its "nothing here yet, scrape it" state.
                    description: 'ENGLISH BLURB',
                    isScrapingGame: false,
                    onScrapeGame: () {},
                    bottomOffset: 90,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the description is in the app language, and only that one', (
    tester,
  ) async {
    await pumpTab(tester, appLanguage: 'fr');

    expect(find.text('BLURB FRANCAIS'), findsOneWidget);
    for (final other in [
      'ENGLISH BLURB',
      'DEUTSCHER TEXT',
      'JAPANESE TEXT',
      'CHINESE TEXT',
    ]) {
      expect(
        find.text(other),
        findsNothing,
        reason: 'only the user\'s language is on the panel',
      );
    }
  });

  testWidgets('a language the scraper files differently still resolves', (
    tester,
  ) async {
    // The app calls it 'ja'; ScreenScraper writes the bucket as 'jp'. Without
    // the mapping this game reads in English on a Japanese install.
    await pumpTab(tester, appLanguage: 'ja');

    expect(find.text('JAPANESE TEXT'), findsOneWidget);
    expect(find.text('ENGLISH BLURB'), findsNothing);
  });

  testWidgets('both Chinese variants share the scraper\'s one bucket', (
    tester,
  ) async {
    await pumpTab(tester, appLanguage: 'zh_Hant');
    expect(find.text('CHINESE TEXT'), findsOneWidget);

    await pumpTab(tester, appLanguage: 'zh');
    expect(find.text('CHINESE TEXT'), findsOneWidget);
  });

  testWidgets('a language the game was not scraped in falls back to English', (
    tester,
  ) async {
    // 'id' has no bucket at ScreenScraper at all, so it is the strongest case:
    // the language is legitimate, the text simply does not exist.
    await pumpTab(tester, appLanguage: 'id');

    expect(find.text('ENGLISH BLURB'), findsOneWidget);
  });

  testWidgets(
    'a game with neither the user\'s language nor English still reads',
    (tester) async {
      // Better the one translation the game has than an empty pane.
      await pumpTab(
        tester,
        appLanguage: 'ko',
        descriptions: const {'de': 'DEUTSCHER TEXT'},
      );

      expect(find.text('DEUTSCHER TEXT'), findsOneWidget);
    },
  );

  testWidgets('no language chips are left to press or walk', (tester) async {
    await pumpTab(tester, appLanguage: 'fr');

    // The chips were the strip's only horizontally-scrolling list, and each
    // wore the name of its language.
    expect(find.byType(ListView), findsNothing);
    for (final label in ['English', 'Francais', 'Deutsch']) {
      expect(find.text(label), findsNothing);
    }
  });
}
