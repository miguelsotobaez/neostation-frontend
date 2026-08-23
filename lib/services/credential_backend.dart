/// A place a credential can be kept.
///
/// Implemented by the platform keychain wrapper and by the app's own encrypted
/// file, so [CredentialStore] can try them in order without caring which is
/// which.
abstract class CredentialBackend {
  /// Returns the stored value, or null when nothing is stored for [key].
  /// Throws when the store itself could not be read — the caller relies on that
  /// distinction to avoid treating an unreadable store as a signed-out user.
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}
