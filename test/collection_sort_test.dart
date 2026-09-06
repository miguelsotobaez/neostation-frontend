import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/collection_model.dart';
import 'package:neostation/utils/collection_sort.dart';

/// Tests for the collections browser's display ordering.
///
/// The browser used to show whatever the repository returned — `sort_order`,
/// i.e. creation order, whose `LOWER(name)` tiebreak can never fire because
/// `sort_order` is unique per row. These pin the orderings that replaced it.
void main() {
  CollectionModel c(
    String name, {
    int count = 0,
    int sortOrder = 0,
    String? created,
  }) => CollectionModel(
    id: name,
    name: name,
    gameCount: count,
    sortOrder: sortOrder,
    createdAt: created == null ? null : DateTime.parse(created),
  );

  List<String> names(List<CollectionModel> list) =>
      list.map((e) => e.name).toList();

  group('sortCollections', () {
    test('name ascending is case-insensitive', () {
      final input = [c('zelda'), c('Mario'), c('animal crossing')];

      expect(names(sortCollections(input, CollectionSortBy.name, 'asc')), [
        'animal crossing',
        'Mario',
        'zelda',
      ]);
    });

    test('name descending reverses that order', () {
      final input = [c('zelda'), c('Mario'), c('animal crossing')];

      expect(names(sortCollections(input, CollectionSortBy.name, 'desc')), [
        'zelda',
        'Mario',
        'animal crossing',
      ]);
    });

    test('date added sorts oldest first, not by name', () {
      final input = [
        c('zelda', created: '2026-01-01'),
        c('animal crossing', created: '2026-06-01'),
        c('Mario', created: '2026-03-01'),
      ];

      expect(names(sortCollections(input, CollectionSortBy.dateAdded, 'asc')), [
        'zelda',
        'Mario',
        'animal crossing',
      ]);
    });

    test(
      'date added falls back to stored position when a timestamp is absent',
      () {
        final input = [c('b', sortOrder: 2), c('a', sortOrder: 1)];

        // Neither has a createdAt, so the stored order wins over the name.
        expect(
          names(sortCollections(input, CollectionSortBy.dateAdded, 'asc')),
          ['a', 'b'],
        );
      },
    );

    test('game count sorts smallest first and breaks ties on name', () {
      final input = [
        c('zelda', count: 4),
        c('mario', count: 4),
        c('solo', count: 1),
      ];

      expect(names(sortCollections(input, CollectionSortBy.gameCount, 'asc')), [
        'solo',
        'mario',
        'zelda',
      ]);
    });

    test('an unknown sort key falls back to name', () {
      final input = [c('b'), c('a')];

      expect(names(sortCollections(input, 'nonsense', 'asc')), ['a', 'b']);
    });

    test('the input list is not modified', () {
      final input = [c('b'), c('a')];

      sortCollections(input, CollectionSortBy.name, 'asc');

      expect(names(input), ['b', 'a']);
    });

    test('the device case: 1/4/4 orders alphabetically, not by creation', () {
      // The Thor's DB: XZZZ was created first, so creation order led with it.
      final input = [
        c('XZZZ', count: 1, sortOrder: 0, created: '2026-08-19'),
        c('mario', count: 4, sortOrder: 1, created: '2026-08-20'),
        c('Collection 3', count: 4, sortOrder: 2, created: '2026-08-20'),
      ];

      expect(names(sortCollections(input, CollectionSortBy.name, 'asc')), [
        'Collection 3',
        'mario',
        'XZZZ',
      ]);
    });
  });
}
