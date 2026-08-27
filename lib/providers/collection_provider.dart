import 'package:flutter/foundation.dart';
import '../models/collection_model.dart';
import '../models/game_model.dart';
import '../repositories/collection_repository.dart';
import '../services/logger_service.dart';

/// Provider managing collections state and games assigned to collections.
class CollectionProvider extends ChangeNotifier {
  static final _log = LoggerService.instance;

  List<CollectionModel> _collections = [];
  bool _isLoading = false;
  CollectionModel? _activeCollection;
  List<GameModel> _activeGames = [];
  bool _isLoadingGames = false;
  String? _errorMessage;

  // Getters
  List<CollectionModel> get collections => _collections;
  bool get isLoading => _isLoading;
  CollectionModel? get activeCollection => _activeCollection;
  List<GameModel> get activeGames => _activeGames;
  bool get isLoadingGames => _isLoadingGames;
  String? get errorMessage => _errorMessage;

  /// Loads all user collections from the database.
  Future<void> loadCollections({bool notify = true}) async {
    _isLoading = true;
    _errorMessage = null;
    if (notify) notifyListeners();

    try {
      _collections = await CollectionRepository.getCollections();

      // If viewing an active collection, refresh its metadata (e.g. game count)
      if (_activeCollection != null) {
        final match = _collections.where((c) => c.id == _activeCollection!.id);
        if (match.isNotEmpty) {
          _activeCollection = match.first;
        }
      }
    } catch (e, stack) {
      _log.e('Error loading collections: $e\n$stack');
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Creates a new collection and reloads the collection list.
  Future<CollectionModel?> createCollection({
    required String name,
    String? icon,
    String? color,
  }) async {
    try {
      final id = await CollectionRepository.createCollection(
        name: name,
        icon: icon,
        color: color,
      );
      await loadCollections(notify: false);
      final match = _collections.where((c) => c.id == id);
      return match.isNotEmpty ? match.first : null;
    } catch (e, stack) {
      _log.e('Error creating collection: $e\n$stack');
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Updates an existing collection's details.
  Future<void> updateCollection(
    int id, {
    required String name,
    String? icon,
    String? color,
  }) async {
    try {
      await CollectionRepository.updateCollection(
        id,
        name: name,
        icon: icon,
        color: color,
      );
      await loadCollections(notify: false);
      if (_activeCollection?.id == id) {
        final match = _collections.where((c) => c.id == id);
        if (match.isNotEmpty) {
          _activeCollection = match.first;
        }
      }
      notifyListeners();
    } catch (e, stack) {
      _log.e('Error updating collection $id: $e\n$stack');
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Sets custom background and/or logo images for a collection.
  Future<void> setCustomImages(
    int id, {
    String? backgroundPath,
    String? logoPath,
  }) async {
    try {
      await CollectionRepository.setCustomImages(
        id,
        backgroundPath: backgroundPath,
        logoPath: logoPath,
      );
      await loadCollections(notify: true);
    } catch (e, stack) {
      _log.e('Error setting custom images for collection $id: $e\n$stack');
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Deletes a collection and removes it from local state.
  Future<void> deleteCollection(int id) async {
    try {
      await CollectionRepository.deleteCollection(id);
      if (_activeCollection?.id == id) {
        _activeCollection = null;
        _activeGames = [];
      }
      await loadCollections(notify: true);
    } catch (e, stack) {
      _log.e('Error deleting collection $id: $e\n$stack');
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Selects [collection] as the active collection and loads its games.
  Future<void> openCollection(CollectionModel collection) async {
    _activeCollection = collection;
    notifyListeners();
    await loadActiveCollectionGames();
  }

  /// Clears the active collection and returns to overview mode.
  void closeCollection() {
    _activeCollection = null;
    _activeGames = [];
    _isLoadingGames = false;
    notifyListeners();
  }

  /// Fetches games belonging to the current [activeCollection].
  Future<void> loadActiveCollectionGames() async {
    if (_activeCollection == null) return;

    _isLoadingGames = true;
    notifyListeners();

    try {
      final dbGames = await CollectionRepository.getGamesForCollection(
        _activeCollection!.id,
      );
      _activeGames = dbGames
          .map((g) => GameModel.fromDatabaseModel(g))
          .toList();
    } catch (e, stack) {
      _log.e(
        'Error loading games for collection ${_activeCollection!.id}: $e\n$stack',
      );
      _activeGames = [];
    } finally {
      _isLoadingGames = false;
      notifyListeners();
    }
  }

  /// Adds games to the current active collection.
  Future<void> addGamesToActiveCollection(List<String> romPaths) async {
    if (_activeCollection == null || romPaths.isEmpty) return;

    try {
      await CollectionRepository.addGamesToCollection(
        _activeCollection!.id,
        romPaths,
      );
      await Future.wait([
        loadActiveCollectionGames(),
        loadCollections(notify: false),
      ]);
      notifyListeners();
    } catch (e, stack) {
      _log.e('Error adding games to collection: $e\n$stack');
    }
  }

  /// Removes a single game from the current active collection.
  Future<void> removeGameFromActiveCollection(String romPath) async {
    if (_activeCollection == null) return;

    try {
      await CollectionRepository.removeGamesFromCollection(
        _activeCollection!.id,
        [romPath],
      );
      await Future.wait([
        loadActiveCollectionGames(),
        loadCollections(notify: false),
      ]);
      notifyListeners();
    } catch (e, stack) {
      _log.e('Error removing game from collection: $e\n$stack');
    }
  }

  /// Sets the complete list of games for a specific collection.
  Future<void> setGamesForCollection(
    int collectionId,
    List<String> romPaths,
  ) async {
    try {
      await CollectionRepository.setGamesForCollection(collectionId, romPaths);
      if (_activeCollection?.id == collectionId) {
        await loadActiveCollectionGames();
      }
      await loadCollections(notify: false);
      notifyListeners();
    } catch (e, stack) {
      _log.e('Error setting games for collection $collectionId: $e\n$stack');
    }
  }

  /// Sets the complete list of games for the current active collection.
  Future<void> setGamesForActiveCollection(List<String> romPaths) async {
    if (_activeCollection == null) return;
    await setGamesForCollection(_activeCollection!.id, romPaths);
  }
}
