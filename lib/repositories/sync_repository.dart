import '../data/datasources/sqlite_service.dart';

/// Repository for cloud save synchronization state.
///
/// State is keyed on ([provider], filePath): every row is owned by the sync
/// provider that wrote it, so RomM and NeoSync never overwrite each other's
/// recorded cloud timestamps for the same local file.
class SyncRepository {
  /// Persists local synchronization state for a file under [provider].
  static Future<void> saveSyncState(
    String provider,
    String filePath,
    int localModifiedAt,
    int cloudUpdatedAt,
    int fileSize, {
    String? fileHash,
  }) => SqliteService.saveSyncState(
    provider,
    filePath,
    localModifiedAt,
    cloudUpdatedAt,
    fileSize,
    fileHash: fileHash,
  );

  /// Retrieves the recorded synchronization state for [provider]'s copy of a
  /// specific file path.
  static Future<Map<String, dynamic>?> getSyncState(
    String provider,
    String filePath,
  ) => SqliteService.getSyncState(provider, filePath);
}
