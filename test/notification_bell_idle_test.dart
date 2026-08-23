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
/// transientCallbackCount is the assertion that catches it: a running ticker
/// registers exactly one, so "no notifications" must mean zero.
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

  testWidgets('pulses while a notification is active', (tester) async {
    await pumpBell(tester);
    await tester.pumpAndSettle();

    GlobalNotificationService().show(id: 'test', message: 'hello');
    await tester.pump();

    expect(tester.binding.transientCallbackCount, greaterThan(0));
  });

  testWidgets('stops the pulse again when the last notification clears', (
    tester,
  ) async {
    await pumpBell(tester);
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
