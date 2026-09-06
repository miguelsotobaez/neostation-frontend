import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/providers/collections_provider.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/screens/game_screen/game_list_view.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The selection highlight is positioned in viewport space as
/// `(selection * itemHeight) + padding - scrollOffset`, and the list scrolls the
/// selected row back to the centre. Mid-list the two terms therefore cancel: a
/// correctly synchronised bar holds still while the rows slide under it.
///
/// They only cancel while the highlight animation and the centring scroll share
/// a duration and a curve. When they did not — 250ms against 360ms, and 120
/// against 180 while navigating fast — the bar detached from its row, slid
/// towards the next one and was dragged back as the scroll caught up. Measured
/// by frame differencing on the Thor: 22px of a 78px row for ~100ms on every
/// ordinary move, and 40–76px sustained for over a second with the D-pad held,
/// which reads as one highlight covering two rows at once.
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

/// Long enough that the viewport cannot hold it, so the list really scrolls and
/// the cancellation above is actually exercised.
final _games = List.generate(200, (i) => game('game$i.sfc', 'Game Number $i'));

/// The bar is the only [Container] in the tree carrying a shadowed
/// [BoxDecoration]; the rows draw no background of their own.
final Finder _highlight = find.byWidgetPredicate((w) {
  if (w is! Container) return false;
  final d = w.decoration;
  return d is BoxDecoration && d.color != null && d.boxShadow != null;
});

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
    SfxService().setEnabled(false);
  });

  Future<void> pumpAt(WidgetTester tester, int selectedIndex) =>
      tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1920, 1080)),
          child: ScreenUtilInit(
            designSize: const Size(1920, 1080),
            builder: (context, child) => MaterialApp(
              localizationsDelegates:
                  FlutterLocalization.instance.localizationsDelegates,
              supportedLocales: FlutterLocalization.instance.supportedLocales,
              home: MultiProvider(
                providers: [
                  ChangeNotifierProvider<SqliteConfigProvider>(
                    create: (_) => SqliteConfigProvider(),
                  ),
                  ChangeNotifierProvider<CollectionsProvider>(
                    create: (_) => CollectionsProvider(),
                  ),
                ],
                child: Scaffold(
                  body: GameListView(
                    system: _system,
                    games: _games,
                    selectedIndex: selectedIndex,
                    systemColor: Colors.pink,
                    onGameSelected: (_) {},
                    onGameConfirmed: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  /// Puts the list in the settled, centred, mid-list state it holds on a device
  /// between moves, and returns the bar's resting y.
  ///
  /// The centring [CenteredScrollController.initialize] schedules sits behind a
  /// delayed timer whose follow-up post-frame callback does not land inside a
  /// widget test, so the list would otherwise still be at the top and the first
  /// move would be an 800px catch-up scroll that measures nothing. [jumpToIndex]
  /// is the view's own synchronous route to the same place.
  Future<double> settleMidList(WidgetTester tester, int index) async {
    await pumpAt(tester, index);
    await tester.pump(const Duration(milliseconds: 300));

    tester
        .state<GameListViewState>(find.byType(GameListView))
        .jumpToIndex(index);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    final y = tester.getTopLeft(_highlight).dy;
    // Guard the guard: off-screen or jammed against an end means the
    // cancellation under test is not being exercised, and any excursion
    // measured against it would be meaningless.
    expect(
      y,
      inInclusiveRange(200.0, 900.0),
      reason: 'the list did not settle mid-viewport; bar at ${y}px',
    );
    return y;
  }

  /// Worst distance the bar strays from [settled] while [steps] moves play out.
  Future<double> wander(
    WidgetTester tester,
    double settled,
    List<int> steps,
    int framesEach,
  ) async {
    double worst = 0;
    void sample() {
      final d = (tester.getTopLeft(_highlight).dy - settled).abs();
      if (d > worst) worst = d;
    }

    for (final step in steps) {
      await pumpAt(tester, step);
      // The frame pumpWidget itself renders, before any post-frame callback has
      // advanced anything. Skipping it hides a whole class of one-frame fault:
      // a tween rebuilt against a controller still resting at 1.0 evaluates to
      // its own end value, and the bar teleports a full row for exactly this
      // frame. Measured on the Thor before it was sampled here.
      sample();
      for (var i = 0; i < framesEach; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        sample();
      }
    }
    // Drain the centring timer so it does not outlive the tree.
    await tester.pump(const Duration(milliseconds: 900));
    return worst;
  }

  testWidgets('the highlight holds its place while the rows scroll under it', (
    tester,
  ) async {
    // Deep enough in the list that the scroll is clamped at neither end.
    final settled = await settleMidList(tester, 100);
    // 30 frames covers the longer of the two animations with room to spare.
    final worst = await wander(tester, settled, [101], 30);

    expect(
      worst,
      lessThan(1.0),
      reason:
          'mid-list the highlight should be stationary: its one-row advance is '
          'cancelled by the scroll. It wandered ${worst.toStringAsFixed(1)}px, '
          'which means the two animations are no longer on one clock.',
    );
  });

  testWidgets('it holds its place across a run of fast-navigation moves', (
    tester,
  ) async {
    // isNavigatingFast picks the shorter pair; those must match as well, and
    // the lag compounds when moves interrupt each other.
    final settled = await settleMidList(tester, 100);
    final worst = await wander(tester, settled, [101, 102, 103, 104, 105], 6);

    expect(
      worst,
      lessThan(1.0),
      reason:
          'stepping quickly must not let the highlight run ahead of the rows; '
          'it wandered ${worst.toStringAsFixed(1)}px',
    );
  });
}
