import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/providers/collection_provider.dart';
import 'package:neostation/screens/collections_screen/collections_tab.dart';
import 'package:neostation/screens/collections_screen/collection_add_games_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database_test_helper.dart';

void main() {
  final dbHelper = DatabaseTestHelper();

  setUp(() async {
    await dbHelper.setUp();

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
  });

  tearDown(() async {
    await dbHelper.tearDown();
  });

  testWidgets('CollectionsTab renders overview and create button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CollectionProvider()),
        ],
        child: ScreenUtilInit(
          designSize: const Size(1920, 1080),
          builder: (context, child) => MaterialApp(
            localizationsDelegates:
                FlutterLocalization.instance.localizationsDelegates,
            supportedLocales: FlutterLocalization.instance.supportedLocales,
            home: const Scaffold(body: CollectionsTab()),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text(AppLocale.en[AppLocale.collections]!), findsOneWidget);
    expect(find.text('Create Collection [X]'), findsOneWidget);
  });

  testWidgets('CollectionAddGamesDialog renders search and filter chips', (
    tester,
  ) async {
    Set<String>? savedPaths;

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(1920, 1080),
        builder: (context, child) => MaterialApp(
          localizationsDelegates:
              FlutterLocalization.instance.localizationsDelegates,
          supportedLocales: FlutterLocalization.instance.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  CollectionAddGamesDialog.show(
                    context: ctx,
                    collectionName: 'RPG Favorites',
                    initialSelectedRomPaths: {'/roms/snes/chrono.zip'},
                    onSave: (paths) {
                      savedPaths = paths;
                    },
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Dialog'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('RPG Favorites'), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text(AppLocale.en[AppLocale.allSystems]!), findsOneWidget);
    expect(find.text('Done [B]'), findsOneWidget);

    // Tap Done
    await tester.tap(find.text('Done [B]'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(savedPaths, isNotNull);
    expect(savedPaths!.contains('/roms/snes/chrono.zip'), isTrue);
  });
}
