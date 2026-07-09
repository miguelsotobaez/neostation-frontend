import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/widgets/confirm_action_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // FlutterLocalization reads the saved locale from SharedPreferences.
    SharedPreferences.setMockInitialValues({});

    // Stub the gamepads plugin so GamepadNavigation.initialize() finds no
    // devices instead of relying on a real platform channel.
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

  /// Pumps a minimal localized + ScreenUtil-initialized host and hands back a
  /// [BuildContext] under the MaterialApp navigator, ready to open a dialog.
  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1920, 1080)),
        child: ScreenUtilInit(
          designSize: const Size(1920, 1080),
          builder: (context, child) => MaterialApp(
            localizationsDelegates:
                FlutterLocalization.instance.localizationsDelegates,
            supportedLocales: FlutterLocalization.instance.supportedLocales,
            home: Builder(
              builder: (context) {
                ctx = context;
                return const Scaffold(body: SizedBox.shrink());
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ctx;
  }

  testWidgets('shows the title, body and confirm label', (tester) async {
    final ctx = await pumpHost(tester);
    // ignore: unawaited_futures
    ConfirmActionDialog.show(
      ctx,
      title: 'Reset Play Time',
      body: 'This cannot be undone.',
      confirmLabel: 'Reset',
      cancelLabel: 'Keep',
      icon: Symbols.timer_off_rounded,
    );
    await tester.pumpAndSettle();

    expect(find.text('Reset Play Time'), findsOneWidget);
    expect(find.text('This cannot be undone.'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
    expect(find.text('Keep'), findsOneWidget);
  });

  testWidgets('resolves true when the confirm button is tapped', (
    tester,
  ) async {
    final ctx = await pumpHost(tester);
    bool? result;
    // ignore: unawaited_futures
    ConfirmActionDialog.show(
      ctx,
      title: 'Reset Play Time',
      body: 'This cannot be undone.',
      confirmLabel: 'Reset',
      cancelLabel: 'Keep',
      icon: Symbols.timer_off_rounded,
    ).then((value) => result = value);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(find.text('Reset Play Time'), findsNothing);
  });

  testWidgets('resolves false when the cancel button is tapped', (
    tester,
  ) async {
    final ctx = await pumpHost(tester);
    bool? result;
    // ignore: unawaited_futures
    ConfirmActionDialog.show(
      ctx,
      title: 'Reset Play Time',
      body: 'This cannot be undone.',
      confirmLabel: 'Reset',
      cancelLabel: 'Keep',
      icon: Symbols.timer_off_rounded,
    ).then((value) => result = value);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(find.text('Reset Play Time'), findsNothing);
  });

  testWidgets('falls back to the localized Cancel label when none is given', (
    tester,
  ) async {
    final ctx = await pumpHost(tester);
    // ignore: unawaited_futures
    ConfirmActionDialog.show(
      ctx,
      title: 'Remove ROM Folder',
      body: 'Removes this source.',
      confirmLabel: 'Remove',
      icon: Symbols.folder_delete_rounded,
    );
    await tester.pumpAndSettle();

    expect(find.text(AppLocale.en['cancel']), findsOneWidget);
  });
}
