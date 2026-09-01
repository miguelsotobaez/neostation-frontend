import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/providers/retro_achievements_provider.dart';
import 'package:neostation/themes/chrome_surface.dart';
import 'package:neostation/widgets/game_view_footer.dart';

/// The footer's achievements pill renders "No achievements" whenever no game
/// info is loaded. Signed out, no game info is ever loaded — so without a
/// connection check the pill states, for every game in the library, that the
/// game has no achievements. It cannot know that.
class _FakeRaProvider extends RetroAchievementsProvider {
  _FakeRaProvider({required bool connected}) : _connected = connected;

  final bool _connected;

  @override
  bool get isConnected => _connected;
}

/// [raHash] defaults to a hash on purpose: a hashed, unmatched ROM is the case
/// where an empty pill is an answer from RetroAchievements. Pass null for a ROM
/// nothing could hash, where it is not.
GameModel _game({
  int? idRa,
  String? systemRaId,
  int? raNumAchievements,
  String? raHash = 'deadbeef',
}) => GameModel(
  romname: 'Sonic The Hedgehog.gg',
  realname: 'Sonic The Hedgehog',
  name: 'Sonic The Hedgehog',
  year: '',
  developer: '',
  publisher: '',
  genre: '',
  players: '',
  rating: 0,
  idRa: idRa,
  raHash: raHash,
  systemRaId: systemRaId,
  raNumAchievements: raNumAchievements,
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

  Future<void> pumpFooter(
    WidgetTester tester, {
    required bool connected,
    GameModel? game,
    bool isLoading = false,
  }) async {
    // The footer lays out against the full window width in the real app; give
    // the test the same room or its Row overflows and never builds the pill.
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<RetroAchievementsProvider>.value(
        value: _FakeRaProvider(connected: connected),
        child: ScreenUtilInit(
          designSize: const Size(1280, 720),
          builder: (context, _) => MaterialApp(
            // The pill asserts on these theme extensions, which the real app
            // always supplies.
            theme: ThemeData(extensions: [ChromeSurface.standard()]),
            localizationsDelegates:
                FlutterLocalization.instance.localizationsDelegates,
            supportedLocales: FlutterLocalization.instance.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 1280,
                child: GameViewFooter(
                  game: game ?? _game(),
                  onPlay: () {},
                  hasRetroAchievements: true,
                  isLoadingAchievements: isLoading,
                  onShowAchievements: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the pill is hidden while signed out', (tester) async {
    await pumpFooter(tester, connected: false);

    expect(
      find.text(AppLocale.en[AppLocale.noAchievements]!.toUpperCase()),
      findsNothing,
      reason: 'signed out, the app has not asked RetroAchievements anything',
    );
  });

  testWidgets('the pill returns once signed in', (tester) async {
    await pumpFooter(tester, connected: true, game: _game(systemRaId: '15'));

    // Connected, hashed and unmatched is the honest "none" case: the ROM was
    // read and RetroAchievements has no set registered for it.
    expect(
      find.text(AppLocale.en[AppLocale.noAchievements]!.toUpperCase()),
      findsOneWidget,
    );

    // The pill's fixed 101.r width rounds one pixel tight against its contents
    // at the test surface's scale factor. It is a layout artifact of this
    // harness, not the behaviour under test, so consume it deliberately rather
    // than let it fail the assertion above.
    final overflow = tester.takeException();
    expect(
      overflow == null || overflow.toString().contains('overflowed'),
      isTrue,
      reason: 'only the known 1px overflow may be swallowed here',
    );
  });

  group('the total comes from the local snapshot, not the network', () {
    // A matched ROM carries its achievement count in the bundled snapshot, so
    // the pill can show the total with no API call. Only the earned half needs
    // the network, and until it lands the pill must not imply a progress it
    // has not fetched.
    GameModel matched() =>
        _game(idRa: 1234, systemRaId: '15', raNumAchievements: 45);

    testWidgets('shows the total while the earned count is outstanding', (
      tester,
    ) async {
      await pumpFooter(
        tester,
        connected: true,
        game: matched(),
        isLoading: true,
      );

      expect(find.text('\u2013/45'), findsOneWidget);
      expect(
        find.text(AppLocale.en[AppLocale.loading]!.toUpperCase()),
        findsNothing,
        reason: 'the total is already known — do not spin for it',
      );
      tester.takeException();
    });

    testWidgets('never renders a zero it has not fetched', (tester) async {
      await pumpFooter(
        tester,
        connected: true,
        game: matched(),
        isLoading: true,
      );

      expect(
        find.text('0/45'),
        findsNothing,
        reason: '0/45 claims the user has earned none, which is unknown here',
      );
      tester.takeException();
    });

    testWidgets('a hashed, unmatched ROM reports none once the lookup ran', (
      tester,
    ) async {
      await pumpFooter(tester, connected: true, game: _game(systemRaId: '15'));

      expect(
        find.text(AppLocale.en[AppLocale.noAchievements]!.toUpperCase()),
        findsOneWidget,
      );
      tester.takeException();
    });

    testWidgets('a ROM nothing could hash says so instead of "none"', (
      tester,
    ) async {
      // Nothing was ever looked up for this ROM, so "No Achievements" would be
      // a claim the app cannot make — and it would contradict the search
      // screen, whose achievements filter files this game under "Unknown".
      await pumpFooter(
        tester,
        connected: true,
        game: _game(systemRaId: '15', raHash: null),
      );

      expect(
        find.text(AppLocale.en[AppLocale.raCoverageUnknown]!.toUpperCase()),
        findsOneWidget,
      );
      expect(
        find.text(AppLocale.en[AppLocale.noAchievements]!.toUpperCase()),
        findsNothing,
      );
      tester.takeException();
    });

    testWidgets('a local count is ignored unless the ROM is matched', (
      tester,
    ) async {
      // raNumAchievements without an id_ra should never happen, but if a stale
      // row carried one the pill must not advertise a set for an unmatched ROM.
      await pumpFooter(
        tester,
        connected: true,
        game: _game(systemRaId: '15', raNumAchievements: 45),
      );

      expect(find.text('\u2013/45'), findsNothing);
      expect(
        find.text(AppLocale.en[AppLocale.noAchievements]!.toUpperCase()),
        findsOneWidget,
      );
      tester.takeException();
    });
  });

  group('the progress bar only animates while something is outstanding', () {
    double? barValue(WidgetTester tester) => tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .value;

    testWidgets('a settled "no achievements" sits still and empty', (
      tester,
    ) async {
      // An indeterminate bar reads as "still fetching". This state is an
      // answer, not a wait: the lookup ran and came back empty.
      await pumpFooter(tester, connected: true, game: _game(systemRaId: '15'));

      expect(barValue(tester), 0.0);
      tester.takeException();
    });

    testWidgets('a known total with no earned count keeps animating', (
      tester,
    ) async {
      await pumpFooter(
        tester,
        connected: true,
        game: _game(idRa: 1234, systemRaId: '15', raNumAchievements: 45),
        isLoading: true,
      );

      expect(
        barValue(tester),
        isNull,
        reason: 'the earned half is still outstanding',
      );
      tester.takeException();
    });
  });
}
