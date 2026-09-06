import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/models/collection_model.dart';
import 'package:neostation/providers/collections_provider.dart';
import 'package:neostation/widgets/collection_badge.dart';

/// The mark a game carries when it is filed in a collection.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child) => ScreenUtilInit(
    designSize: const Size(1280, 720),
    builder: (context, _) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );

  testWidgets('the plate form sizes itself to the host card', (tester) async {
    await tester.pumpWidget(host(const CollectionBadge(size: 22)));
    final box = tester.widget<Container>(
      find
          .ancestor(
            of: find.byIcon(Symbols.bookmark_rounded),
            matching: find.byType(Container),
          )
          .first,
    );
    expect((box.constraints?.maxWidth ?? 0), 22);
  });

  testWidgets('the inline form is the glyph alone, in the row colour', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const CollectionBadge.inline(color: Colors.orange)),
    );
    final icon = tester.widget<Icon>(find.byIcon(Symbols.bookmark_rounded));
    expect(icon.color, Colors.orange);
    // No plate behind it: a text row has no artwork to sit on.
    expect(find.byType(Container), findsNothing);
  });

  group('CollectionsProvider.isInAnyCollection', () {
    test('a game with no rom path is never a member', () {
      final provider = CollectionsProvider();
      expect(provider.isInAnyCollection(null), isFalse);
      expect(provider.isInAnyCollection(''), isFalse);
    });

    test('an unknown rom path is not a member before anything is loaded', () {
      final provider = CollectionsProvider();
      expect(provider.isInAnyCollection('/roms/nes/Dr. Mario.zip'), isFalse);
    });
  });

  group('CollectionsProvider.totalGameCount', () {
    test('is zero before anything is loaded', () {
      expect(CollectionsProvider().totalGameCount, 0);
    });

    // The Collections card shows this number, and it counts a game once per
    // collection it is in — on purpose, so it agrees with the per-collection
    // counts the browser lists one level down. Changing it to a distinct
    // count would be a silent behaviour change, not a bug fix: that version
    // shipped for a day and was reversed because a card reading 6 over
    // collections of 1, 4 and 4 looks broken with nothing on screen to
    // explain the overlap.
    test('sums the per-collection counts, double-counting a shared game', () {
      final provider = CollectionsProvider();
      // Three collections holding 1, 4 and 4, where three games are filed in
      // two of them: 6 distinct games, 9 memberships. The card wants 9.
      provider.debugSetCollections(const [
        CollectionModel(id: 'a', name: 'Collection 1', gameCount: 1),
        CollectionModel(id: 'b', name: 'mario', gameCount: 4),
        CollectionModel(id: 'c', name: 'Collection 3', gameCount: 4),
      ]);
      expect(provider.totalGameCount, 9);
    });
  });
}
