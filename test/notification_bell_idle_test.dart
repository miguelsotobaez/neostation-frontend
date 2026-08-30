import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/services/global_notification_service.dart';
import 'package:neostation/widgets/notification_bell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The bell's pulse used to `repeat()` unconditionally from initState, and the
/// bell lives in the header on every screen. A ticker that never stops asks the
/// engine for a frame every vsync, so the whole display re-rastered at 60 fps
/// while the user sat still — measured at ~48% of a core on an idle AYN Thor,
/// 26% of it in the raster thread alone.
///
/// Making the pulse conditional on the list being non-empty only moved the
/// problem, because notifications never auto-dismiss: an "ES-DE import
/// complete" notice — a success message with no reason to ever clear it — held
/// the app at a frame every vsync for the rest of the session, measured at 0.53
/// of a core and 17% of the GPU on a 3440x1440 240 Hz Windows display. So the
/// pulse is now an arrival cue that runs a fixed number of cycles and stops
/// while the notification is still sitting there.
///
/// transientCallbackCount is the assertion that catches it: a running ticker
/// registers exactly one, so an idle bell must mean zero.
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

  tearDown(() => GlobalNotificationService().dismiss());

  Future<void> pumpBell(WidgetTester tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1920, 1080)),
        child: ScreenUtilInit(
          designSize: const Size(1920, 1080),
          builder: (context, child) => MaterialApp(
            localizationsDelegates:
                FlutterLocalization.instance.localizationsDelegates,
            supportedLocales: FlutterLocalization.instance.supportedLocales,
            home: const Scaffold(body: Center(child: NotificationBell())),
          ),
        ),
      ),
    );
  }

  testWidgets('idles without a ticker when there are no notifications', (
    tester,
  ) async {
    await pumpBell(tester);

    // pumpAndSettle times out rather than returning if an animation never
    // finishes, so reaching the expect at all is half the assertion.
    await tester.pumpAndSettle();

    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('pulses when a notification arrives', (tester) async {
    await pumpBell(tester);
    await tester.pumpAndSettle();

    GlobalNotificationService().show(id: 'test', message: 'hello');
    await tester.pump();

    expect(tester.binding.transientCallbackCount, greaterThan(0));
  });

  testWidgets(
    'the arrival pulse ends on its own while the notification stays',
    (tester) async {
      await pumpBell(tester);
      await tester.pumpAndSettle();

      GlobalNotificationService().show(id: 'test', message: 'hello');
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      // The notification is never dismissed here — that is the whole point.
      // pumpAndSettle returns rather than timing out only because the pulse is
      // bounded, and the ticker has to be gone once it has.
      await tester.pumpAndSettle();

      expect(tester.binding.transientCallbackCount, 0);
      expect(GlobalNotificationService().notifier.value, isNotEmpty);

      // Parked opaque, not stranded at the faded end of the tween.
      final FadeTransition fade = tester.widget(
        find.descendant(
          of: find.byType(NotificationBell),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(fade.opacity.value, 1.0);
    },
  );

  testWidgets('does not pulse for a notification that predates the mount', (
    tester,
  ) async {
    GlobalNotificationService().show(id: 'test', message: 'hello');

    await pumpBell(tester);
    await tester.pumpAndSettle();

    // The bell is rebuilt on every screen that mounts a header, so treating
    // what is already in the tray as an arrival would re-pulse on every
    // navigation.
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('stops the pulse again when the last notification clears', (
    tester,
  ) async {
    await pumpBell(tester);
    await tester.pumpAndSettle();

    GlobalNotificationService().show(id: 'test', message: 'hello');
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    GlobalNotificationService().dismiss('test');
    await tester.pump();

    expect(tester.binding.transientCallbackCount, 0);
    // No stray scheduled work left behind either.
    await tester.pumpAndSettle();
  });
}
