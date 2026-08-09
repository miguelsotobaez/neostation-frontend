import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/providers/scraping_provider.dart';
import 'package:neostation/services/global_notification_service.dart';
import 'package:neostation/widgets/scraping_notification_listener.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  setUp(() {
    GlobalNotificationService().dismiss();
  });

  Future<void> pumpListener(
    WidgetTester tester,
    ScrapingProvider provider,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(
            body: ScrapingNotificationListener(child: SizedBox.shrink()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  GlobalNotificationData scrapingNotification() {
    return GlobalNotificationService().notifier.value.firstWhere(
      (n) => n.id == 'scraping_progress',
    );
  }

  testWidgets('advances the header notification while the provider updates', (
    tester,
  ) async {
    final provider = ScrapingProvider();
    await pumpListener(tester, provider);

    // _startScraping shows the notification up front.
    GlobalNotificationService().show(
      id: 'scraping_progress',
      message: 'Scraping in progress',
      type: GlobalNotificationType.info,
      progress: 0,
    );

    provider.startScraping(maxThreads: 2);
    provider.updateProgress(
      totalGames: 10,
      processedGames: 4,
      successfulGames: 3,
      failedGames: 1,
    );
    await tester.pump();

    final first = scrapingNotification();
    expect(first.progress, 4 / 10);
    expect(first.message, contains('4 / 10'));

    provider.updateProgress(
      totalGames: 10,
      processedGames: 8,
      successfulGames: 7,
      failedGames: 1,
    );
    await tester.pump();

    expect(scrapingNotification().progress, 8 / 10);
    expect(scrapingNotification().message, contains('8 / 10'));
  });

  testWidgets('leaves the notification untouched once the session stops', (
    tester,
  ) async {
    final provider = ScrapingProvider();
    await pumpListener(tester, provider);

    GlobalNotificationService().show(
      id: 'scraping_progress',
      message: 'Scraping in progress',
      type: GlobalNotificationType.info,
      progress: 0,
    );

    provider.startScraping(maxThreads: 2);
    provider.updateProgress(
      totalGames: 10,
      processedGames: 5,
      successfulGames: 5,
      failedGames: 0,
    );
    await tester.pump();
    final beforeStop = scrapingNotification();

    provider.stopScraping();
    await tester.pump();

    // The completion message is written by _startScraping; the listener must
    // not overwrite it after the session ends.
    expect(scrapingNotification().message, beforeStop.message);
    expect(scrapingNotification().progress, beforeStop.progress);
  });
}
