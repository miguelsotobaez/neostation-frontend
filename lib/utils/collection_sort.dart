import '../models/collection_model.dart';

/// Sort keys accepted by [sortCollections], as stored in
/// `user_config.collection_sort_by`.
class CollectionSortBy {
  const CollectionSortBy._();

  static const String name = 'name';
  static const String dateAdded = 'date_added';
  static const String gameCount = 'game_count';
}

/// Orders the collections browser's cards.
///
/// Kept out of the screen so the ordering is testable on its own and so every
/// read of the list goes through one implementation: the browser's selection
/// index is a position in this list, and a build that ordered differently from
/// the screen's own accessor would put the cursor on the wrong collection.
///
/// The repository deliberately returns storage order (`sort_order`, which is
/// what manual reordering would write); display order is applied here.
///
/// Ties break on name so the result is stable and readable rather than
/// arbitrary — apart from [CollectionSortBy.name] itself, where the name *is*
/// the key. Returns a new list; [collections] is not modified.
List<CollectionModel> sortCollections(
  List<CollectionModel> collections,
  String sortBy,
  String sortOrder,
) {
  final sorted = [...collections];

  int byName(CollectionModel a, CollectionModel b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());

  switch (sortBy) {
    case CollectionSortBy.dateAdded:
      sorted.sort((a, b) {
        final at = a.createdAt;
        final bt = b.createdAt;
        // A row with no parseable timestamp keeps its stored position rather
        // than jumping to one end of the list.
        if (at == null || bt == null) {
          return a.sortOrder.compareTo(b.sortOrder);
        }
        final byDate = at.compareTo(bt);
        return byDate != 0 ? byDate : byName(a, b);
      });
    case CollectionSortBy.gameCount:
      sorted.sort((a, b) {
        final byCount = a.gameCount.compareTo(b.gameCount);
        return byCount != 0 ? byCount : byName(a, b);
      });
    default:
      sorted.sort(byName);
  }

  if (sortOrder == 'desc') {
    return sorted.reversed.toList();
  }
  return sorted;
}
