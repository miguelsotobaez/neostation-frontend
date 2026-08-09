import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/screens/game_screen/game_list_view.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

GameModel game(String romname, String name) => GameModel(
  romname: romname,
  realname: name,
  name: name,
  year: '',
  developer: '',
  publisher: '',
  genre: '',
  players: '',
  rating: 0,
);

final _system = SystemModel(
  id: 'snes',
  folderName: 'snes',
  realName: 'Super Nintendo',
  iconImage: '',
  color: '#ff006a',
);

final _games = [
  game('mario.sfc', 'Super Mario World'),
  game('zelda.sfc', 'A Link to the Past'),
  game('metroid.sfc', 'Super Metroid'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/gamepads'),
          (call) async => <dynamic>[],
        );

    await FlutterLocalization.instance.ensureInitialized();
    FlutterLocalization.instance.init(
      mapLocales: [MapLocale('en', AppLocale.en)],
      initLanguageCode: 'en',
    );

    // Every tap plays a nav/enter sound; SoLoud has no place in a widget test,
    // and disabling makes each play() return before touching the engine.
    SfxService().setEnabled(false);
  });

  /// Pumps a [GameListView] with [selectedIndex] already selected, appending to
  /// [selected]/[confirmed] as taps land. Both are lists so the caller observes
  /// mutations after this returns.
  Future<void> pumpList(
    WidgetTester tester, {
    required int selectedIndex,
    required List<String> selected,
    required List<int> confirmed,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1920, 1080)),
        child: ScreenUtilInit(
          designSize: const Size(1920, 1080),
          builder: (context, child) => MaterialApp(
            localizationsDelegates:
                FlutterLocalization.instance.localizationsDelegates,
            supportedLocales: FlutterLocalization.instance.supportedLocales,
            home: Scaffold(
              body: GameListView(
                system: _system,
                games: _games,
                selectedIndex: selectedIndex,
                systemColor: Colors.pink,
                onGameSelected: (g) => selected.add(g.romname),
                onGameConfirmed: () => confirmed.add(selectedIndex),
              ),
            ),
          ),
        ),
      ),
    );
    // MarqueeText scrolls forever, so pumpAndSettle would never return.
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder rowFor(String title) => find
      .ancestor(of: find.text(title), matching: find.byType(GestureDetector))
      .first;

  /// Drains the centering-scroll timer the list schedules on init, which
  /// otherwise outlives the widget tree and trips the pending-timer invariant.
  Future<void> drain(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 500));

  testWidgets('tapping an unselected row selects it without confirming', (
    tester,
  ) async {
    final selected = <String>[];
    final confirmed = <int>[];
    await pumpList(
      tester,
      selectedIndex: 0,
      selected: selected,
      confirmed: confirmed,
    );

    await tester.tap(rowFor('A Link to the Past'));
    await tester.pump();

    expect(selected, ['zelda.sfc']);
    expect(confirmed, isEmpty, reason: 'an unselected row must not launch');

    await drain(tester);
  });

  testWidgets('tapping the already-selected row confirms it', (tester) async {
    final selected = <String>[];
    final confirmed = <int>[];
    await pumpList(
      tester,
      selectedIndex: 1,
      selected: selected,
      confirmed: confirmed,
    );

    await tester.tap(rowFor('A Link to the Past'));
    await tester.pump();

    expect(confirmed, hasLength(1), reason: 'the selected row launches on tap');
    expect(selected, isEmpty, reason: 'confirming must not re-fire selection');

    await drain(tester);
  });
}
