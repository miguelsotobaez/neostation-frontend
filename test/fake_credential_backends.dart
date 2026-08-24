import 'package:neostation/services/credential_backend.dart';

/// A backend that works, so the happy path can be asserted.
class MemoryBackend implements CredentialBackend {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// A backend that fails the way a missing Secret Service does: every call
/// throws, including the read. Paired with a null file store it produces the
/// session-only write outcome and the "could not look" read.
class BrokenBackend implements CredentialBackend {
  @override
  Future<String?> read(String key) async {
    throw Exception('secret_service_get_sync: the name is not activatable');
  }

  @override
  Future<void> write(String key, String value) async {
    throw Exception('secret_password_storev_sync: Object does not exist');
  }

  @override
  Future<void> delete(String key) async {
    throw Exception('secret_service_get_sync: the name is not activatable');
  }
}
