import '../data/datasources/sqlite_service.dart';
import '../models/collection_model.dart';
import '../models/database_game_model.dart';

/// Repository handling data persistence for user collections and game memberships.
class CollectionRepository {
  /// Fetches all user collections with game counts and cover previews.
  static Future<List<CollectionModel>> getCollections() async {
    return await SqliteService.getCollections();
  }

  /// Fetches a single collection by [id].
  static Future<CollectionModel?> getCollection(int id) async {
    return await SqliteService.getCollection(id);
  }

  /// Creates a new collection and returns its ID.
  static Future<int> createCollection({
    required String name,
    String? icon,
    String? color,
  }) async {
    return await SqliteService.createCollection(
      name: name,
      icon: icon,
      color: color,
    );
  }

  /// Updates an existing collection's details.
  static Future<void> updateCollection(
    int id, {
    required String name,
    String? icon,
    String? color,
  }) async {
    await SqliteService.updateCollection(
      id,
      name: name,
      icon: icon,
      color: color,
    );
  }

  /// Sets custom background and/or logo images for a collection.
  static Future<void> setCustomImages(
    int collectionId, {
    String? backgroundPath,
    String? logoPath,
  }) async {
    await SqliteService.setCollectionCustomImages(
      collectionId,
      backgroundPath: backgroundPath,
      logoPath: logoPath,
    );
  }

  /// Deletes a collection and its associated ROM mappings.
  static Future<void> deleteCollection(int id) async {
    await SqliteService.deleteCollection(id);
  }

  /// Retrieves all games assigned to a collection.
  static Future<List<DatabaseGameModel>> getGamesForCollection(
    int collectionId,
  ) async {
    return await SqliteService.getGamesForCollection(collectionId);
  }

  /// Associates games with a collection.
  static Future<void> addGamesToCollection(
    int collectionId,
    List<String> romPaths,
  ) async {
    await SqliteService.addGamesToCollection(collectionId, romPaths);
  }

  /// Removes games from a collection.
  static Future<void> removeGamesFromCollection(
    int collectionId,
    List<String> romPaths,
  ) async {
    await SqliteService.removeGamesFromCollection(collectionId, romPaths);
  }

  /// Overwrites the full list of games in a collection.
  static Future<void> setGamesForCollection(
    int collectionId,
    List<String> romPaths,
  ) async {
    await SqliteService.setGamesForCollection(collectionId, romPaths);
  }

  /// Checks if a game exists within a collection.
  static Future<bool> isGameInCollection(
    int collectionId,
    String romPath,
  ) async {
    return await SqliteService.isGameInCollection(collectionId, romPath);
  }

  /// Returns IDs of collections containing the given game.
  static Future<List<int>> getCollectionIdsForGame(String romPath) async {
    return await SqliteService.getCollectionIdsForGame(romPath);
  }
}
