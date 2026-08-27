import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/collection_model.dart';
import 'package:neostation/providers/collection_provider.dart';
import 'package:neostation/repositories/collection_repository.dart';
import 'package:neostation/screens/collections_screen/create_edit_collection_dialog.dart';
import 'package:neostation/widgets/collection_options_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database_test_helper.dart';

void main() {
  final dbHelper = DatabaseTestHelper();
  late DatabaseAdapter db;

  setUp(() async {
    db = await dbHelper.setUp();
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

  group('CreateEditCollectionDialog input validation', () {
    testWidgets('trims whitespace and rejects empty name input', (
      tester,
    ) async {
      ({String name, String? description})? savedResult;

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
                    CreateEditCollectionDialog.show(
                      context: ctx,
                      onSave: (result) {
                        savedResult = result;
                      },
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Enter only spaces into the name field
      await tester.enterText(find.byType(TextField).first, '   ');
      await tester.tap(find.text('Save [A]'));
      await tester.pumpAndSettle();

      // Dialog should still be open and result must NOT be submitted
      expect(savedResult, isNull);
      expect(find.byType(CreateEditCollectionDialog), findsOneWidget);

      // Now enter valid name with surrounding whitespace
      await tester.enterText(find.byType(TextField).first, '  RPG Favorites  ');
      await tester.enterText(find.byType(TextField).last, '  Best RPGs ever  ');
      await tester.tap(find.text('Save [A]'));
      await tester.pumpAndSettle();

      expect(savedResult, isNotNull);
      expect(savedResult!.name, equals('RPG Favorites'));
      expect(savedResult!.description, equals('Best RPGs ever'));
      expect(find.byType(CreateEditCollectionDialog), findsNothing);
    });
  });

  group('CollectionOptionsDropdown actions', () {
    testWidgets('renders collection options and handles selection', (
      tester,
    ) async {
      final collection = CollectionModel(
        id: 42,
        name: 'Speedrun Hits',
        description: 'Games to speedrun',
        romCount: 5,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

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
              home: Scaffold(
                body: Builder(
                  builder: (ctx) => ElevatedButton(
                    onPressed: () {
                      CollectionOptionsDropdown.show(
                        context: ctx,
                        collection: collection,
                      );
                    },
                    child: const Text('Options'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Options'));
      await tester.pumpAndSettle();

      expect(find.text('Speedrun Hits'), findsOneWidget);
      expect(find.text('5 games'), findsOneWidget);
      expect(find.text(AppLocale.en[AppLocale.addGames]!), findsOneWidget);
      expect(
        find.text(AppLocale.en[AppLocale.editCollection]!),
        findsOneWidget,
      );
      expect(
        find.text(AppLocale.en[AppLocale.deleteCollection]!),
        findsOneWidget,
      );
    });
  });

  group('Multi-System Collection Domain & System Mapping', () {
    test('creates multi-system collection and queries cross-system ROMs', () async {
      await db.execute(
        "INSERT INTO app_systems (id, real_name, folder_name) VALUES ('snes', 'Super Nintendo', 'snes')",
      );
      await db.execute(
        "INSERT INTO app_systems (id, real_name, folder_name) VALUES ('ps1', 'Sony PlayStation', 'ps1')",
      );
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, title_name) "
        "VALUES ('mario.sfc', '/roms/snes/mario.sfc', 'snes', 'Super Mario World')",
      );
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, title_name) "
        "VALUES ('crash.chd', '/roms/ps1/crash.chd', 'ps1', 'Crash Bandicoot')",
      );
      await db.execute(
        "INSERT INTO user_screenscraper_metadata (app_system_id, filename, real_name) "
        "VALUES ('snes', 'mario.sfc', 'Super Mario World')",
      );
      await db.execute(
        "INSERT INTO user_screenscraper_metadata (app_system_id, filename, real_name) "
        "VALUES ('ps1', 'crash.chd', 'Crash Bandicoot')",
      );

      final collectionId = await CollectionRepository.createCollection(
        name: 'Multi-System Platformers',
        description: 'Great platformers across consoles',
      );

      await CollectionRepository.addGamesToCollection(collectionId, [
        '/roms/snes/mario.sfc',
        '/roms/ps1/crash.chd',
      ]);

      final collection = await CollectionRepository.getCollection(collectionId);
      expect(collection, isNotNull);
      expect(collection!.romCount, equals(2));

      // Test toSystemModel conversion
      final systemModel = collection.toSystemModel();
      expect(systemModel.id, equals('collection_$collectionId'));
      expect(systemModel.folderName, equals('collection_$collectionId'));
      expect(systemModel.realName, equals('Multi-System Platformers'));
      expect(systemModel.isMultiSystem, isTrue);

      // Verify ROMs loaded for this collection
      final games = await CollectionRepository.getGamesForCollection(
        collectionId,
      );
      expect(games.length, equals(2));
      final names = games.map((g) => g.realName ?? g.filename).toSet();
      expect(names, containsAll(['Super Mario World', 'Crash Bandicoot']));
      final systems = games
          .map((g) => g.systemFolderName ?? g.appSystemId)
          .toSet();
      expect(systems, containsAll(['snes', 'ps1']));
    });
  });
}
