import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/providers/collection_provider.dart';
import 'package:neostation/screens/collections_screen/collections_tab.dart';
import 'package:neostation/screens/collections_screen/collection_add_games_dialog.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/providers/sqlite_database_provider.dart';
import 'package:neostation/providers/neo_assets_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neostation/models/game_model.dart';
import 'package:neostation/widgets/game_collections_dropdown.dart';

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

  testWidgets('CollectionsTab renders overview with platform UI components', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CollectionProvider()),
          ChangeNotifierProvider(create: (_) => SqliteConfigProvider()),
          ChangeNotifierProvider(create: (_) => SqliteDatabaseProvider()),
          ChangeNotifierProvider(create: (_) => NeoAssetsProvider()),
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

    expect(find.text(AppLocale.en[AppLocale.createCollection]!), findsWidgets);
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

  testWidgets(
    'GameCollectionsDropdown renders Favorite and collections options',
    (tester) async {
      final collectionProvider = CollectionProvider();
      await collectionProvider.createCollection(name: 'Action Hits');

      bool favoriteToggled = false;
      bool collectionsUpdated = false;

      final game = GameModel(
        romname: 'mario.zip',
        realname: 'Super Mario World',
        name: 'Super Mario World',
        year: '1990',
        developer: 'Nintendo',
        publisher: 'Nintendo',
        genre: 'Platform',
        players: '2',
        rating: 5.0,
        romPath: '/roms/snes/mario.zip',
        isFavorite: false,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [ChangeNotifierProvider.value(value: collectionProvider)],
          child: ScreenUtilInit(
            designSize: const Size(1920, 1080),
            builder: (context, child) => MaterialApp(
              localizationsDelegates:
                  FlutterLocalization.instance.localizationsDelegates,
              supportedLocales: FlutterLocalization.instance.supportedLocales,
              home: Scaffold(
                body: Builder(
                  builder: (ctx) => ElevatedButton(
                    onPressed: () {
                      GameCollectionsDropdown.show(
                        context: ctx,
                        game: game,
                        onFavoriteToggled: () => favoriteToggled = true,
                        onCollectionsUpdated: () => collectionsUpdated = true,
                      );
                    },
                    child: const Text('Open Dropdown'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Dropdown'));
      await tester.pumpAndSettle();

      expect(find.text('Super Mario World'), findsOneWidget);
      expect(find.text(AppLocale.en[AppLocale.favorite]!), findsOneWidget);
      expect(find.text('Action Hits'), findsOneWidget);
      expect(
        find.text(AppLocale.en[AppLocale.createCollection]!),
        findsOneWidget,
      );

      // Tap Favorite
      await tester.tap(find.text(AppLocale.en[AppLocale.favorite]!));
      await tester.pumpAndSettle();
      expect(favoriteToggled, isTrue);

      // Tap Action Hits collection
      await tester.tap(find.text('Action Hits'));
      await tester.pumpAndSettle();
      expect(collectionsUpdated, isTrue);
    },
  );
}
