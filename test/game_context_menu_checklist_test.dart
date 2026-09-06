import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/widgets/context_menu/anchored_context_menu.dart';
import 'package:neostation/widgets/context_menu/game_context_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Covers the `Add to…` checklist that replaced the `Add to…` / `Remove from…`
/// split.
///
/// The split is what these tests exist to keep from coming back. It sorted each
/// bucket into one submenu or the other by the game's *current* membership, so
/// a bucket moved every time it was used and no press was twice in the same
/// place; and because activating a row closed the whole menu, putting one game
/// into three collections meant opening the menu three times. Both properties
/// are pinned below: every bucket is in one list whatever its state, and a
/// ticked row leaves the menu standing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // SoLoud has no native library in the test host.
    SfxService().setEnabled(false);
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
  });

  Widget host(Widget child) => ScreenUtilInit(
    designSize: const Size(1920, 1080),
    builder: (context, _) => MaterialApp(
      localizationsDelegates:
          FlutterLocalization.instance.localizationsDelegates,
      supportedLocales: FlutterLocalization.instance.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.reset);

    late BuildContext ctx;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ctx;
  }

  String label(BuildContext context, String key) => key.getString(context);

  /// Whether [name]'s row is currently ticked, read off the trailing glyph.
  ///
  /// A row lays out as leading icon, label, trailing icon, so the last Icon
  /// under the label's nearest Row is the checkbox.
  bool isTicked(WidgetTester tester, String name) {
    final row = find
        .ancestor(of: find.text(name), matching: find.byType(Row))
        .first;
    final icons = tester.widgetList<Icon>(
      find.descendant(of: row, matching: find.byType(Icon)),
    );
    return icons.last.icon == Symbols.check_box_rounded;
  }

  Future<void> openChecklist(WidgetTester tester, BuildContext ctx) async {
    await tester.tap(find.text(label(ctx, AppLocale.addTo)));
    await tester.pumpAndSettle();
  }

  testWidgets('every bucket is in one list, whatever the game is in', (
    tester,
  ) async {
    final ctx = await pumpHost(tester);
    // ignore: unawaited_futures
    showGameContextMenu(
      context: ctx,
      targets: <GameContextMenuTarget>[
        GameContextMenuTarget(
          id: 'favorites',
          label: 'Favorite',
          icon: Symbols.favorite_rounded,
          isMember: true,
          setMember: (_) async => true,
        ),
        GameContextMenuTarget(
          id: 'collection:a',
          label: 'Shooters',
          icon: Symbols.bookmark_rounded,
          isMember: false,
          setMember: (_) async => true,
        ),
      ],
      onSettings: () {},
    );
    await tester.pumpAndSettle();

    // One parent row, not two: `Remove from…` is gone as a concept.
    expect(find.text(label(ctx, AppLocale.addTo)), findsOneWidget);

    await openChecklist(tester, ctx);

    // A member and a non-member, side by side in the same list, each showing
    // its state rather than being filed by it.
    expect(find.text('Favorite'), findsOneWidget);
    expect(find.text('Shooters'), findsOneWidget);
    expect(isTicked(tester, 'Favorite'), isTrue);
    expect(isTicked(tester, 'Shooters'), isFalse);
  });

  testWidgets('ticking a row reports it and leaves the menu open', (
    tester,
  ) async {
    final ctx = await pumpHost(tester);
    final calls = <String>[];
    // ignore: unawaited_futures
    showGameContextMenu(
      context: ctx,
      targets: <GameContextMenuTarget>[
        GameContextMenuTarget(
          id: 'collection:a',
          label: 'Shooters',
          icon: Symbols.bookmark_rounded,
          isMember: false,
          setMember: (member) async {
            calls.add('a=$member');
            return true;
          },
        ),
        GameContextMenuTarget(
          id: 'collection:b',
          label: 'Puzzlers',
          icon: Symbols.bookmark_rounded,
          isMember: true,
          setMember: (member) async {
            calls.add('b=$member');
            return true;
          },
        ),
      ],
      onSettings: () {},
    );
    await tester.pumpAndSettle();
    await openChecklist(tester, ctx);

    // Three changes without reopening the menu once — the thing the old
    // close-on-activate submenus made impossible.
    await tester.tap(find.text('Shooters'));
    await tester.pumpAndSettle();
    expect(isTicked(tester, 'Shooters'), isTrue);

    await tester.tap(find.text('Puzzlers'));
    await tester.pumpAndSettle();
    expect(isTicked(tester, 'Puzzlers'), isFalse);

    await tester.tap(find.text('Shooters'));
    await tester.pumpAndSettle();
    expect(isTicked(tester, 'Shooters'), isFalse);

    expect(calls, <String>['a=true', 'b=false', 'a=false']);
    // Still standing, on the same rows.
    expect(find.text('Shooters'), findsOneWidget);
  });

  testWidgets('a write that does not stick springs the box back', (
    tester,
  ) async {
    final ctx = await pumpHost(tester);
    // ignore: unawaited_futures
    showGameContextMenu(
      context: ctx,
      targets: <GameContextMenuTarget>[
        GameContextMenuTarget(
          id: 'collection:a',
          label: 'Shooters',
          icon: Symbols.bookmark_rounded,
          isMember: false,
          setMember: (_) async => false,
        ),
      ],
      onSettings: () {},
    );
    await tester.pumpAndSettle();
    await openChecklist(tester, ctx);

    await tester.tap(find.text('Shooters'));
    await tester.pumpAndSettle();

    // The menu is optimistic, so the box ticked on the press — and came back
    // off when the write reported failure. A menu left claiming a membership
    // the database never took is the one outcome worse than the error toast.
    expect(isTicked(tester, 'Shooters'), isFalse);
  });

  testWidgets('New collection… is the one row that still closes the menu', (
    tester,
  ) async {
    final ctx = await pumpHost(tester);
    var created = 0;
    // ignore: unawaited_futures
    showGameContextMenu(
      context: ctx,
      targets: <GameContextMenuTarget>[
        GameContextMenuTarget(
          id: 'collection:a',
          label: 'Shooters',
          icon: Symbols.bookmark_rounded,
          isMember: false,
          setMember: (_) async => true,
        ),
      ],
      onSettings: () {},
      onCreateTarget: () async => created++,
      createTargetLabel: label(ctx, AppLocale.newCollection),
    );
    await tester.pumpAndSettle();
    await openChecklist(tester, ctx);

    await tester.tap(find.text(label(ctx, AppLocale.newCollection)));
    await tester.pumpAndSettle();

    expect(created, 1);
    // It is an action, not a membership, so the whole stack goes.
    expect(find.text('Shooters'), findsNothing);
    expect(find.text(label(ctx, AppLocale.addTo)), findsNothing);
  });

  testWidgets('a checkable row never resolves the menu', (tester) async {
    final ctx = await pumpHost(tester);
    String? result = 'unset';
    // ignore: unawaited_futures
    showAnchoredContextMenu(
      context: ctx,
      items: const <ContextMenuItem>[
        ContextMenuItem(id: 'a', label: 'Shooters', checkable: true),
      ],
      onToggle: (id, {required checked}) async => true,
    ).then((value) => result = value);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Shooters'));
    await tester.pumpAndSettle();
    // Still open: the future has not completed at all yet.
    expect(result, 'unset');

    // Dismissed by hand, which is the only way a checklist ends.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
